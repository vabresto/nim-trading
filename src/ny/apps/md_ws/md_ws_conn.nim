import std/asyncdispatch
import std/json

import chronicles except toJson
import jsony
import ws as tf_ws

import ny/core/md/alpaca/types
# import ny/apps/md_ws/parsing
import ny/core/types/timestamp
import ny/core/md/alpaca/parsing

export types


type
  MdWsReply* = object
    receiveTs*: Timestamp
    parsedMd*: seq[AlpacaMdWsReply]
    rawMd*: seq[JsonNode]


proc receiveMdWsReply*(ws: WebSocket): Future[MdWsReply] {.async.} =
  let rawReply = await ws.receiveStrPacket()
  let receiveTimestamp = getNowUtc()
  info "Receive ts", ts=receiveTimestamp
  if rawReply == "":
    return MdWsReply(receiveTs: receiveTimestamp, parsedMd: @[], rawMd: @[])
  let parsed = rawReply.fromJson(seq[AlpacaMdWsReply])
  
  let rawMd = block:
    var rawMd = newSeq[JsonNode]()
    for node in rawReply.parseJson():
      rawMd.add node
    rawMd

  return MdWsReply(receiveTs: receiveTimestamp, parsedMd: parsed, rawMd: rawMd)


proc initWebsocket*(feed: string, alpacaKey: string, alpacaSecret: string): Future[WebSocket] {.async.} =
  # First, create the socket
  var socket: WebSocket = await newWebSocket("wss://stream.data.alpaca.markets/v2/" & feed)
  socket.setupPings(60)

  # Will raise if we fail to auth
  while true:
    let reply = await socket.receiveMdWsReply()
    if reply.parsedMd.len > 0:
      if reply.parsedMd[0].kind == AlpacaMdWsReplyKind.ConnectOk:
        # Got the message we wanted
        break
      elif reply.parsedMd[0].kind == AlpacaMdWsReplyKind.AuthOk:
        # Unexpected but ok
        break
      elif reply.parsedMd[0].kind == AlpacaMdWsReplyKind.AuthErr:
        var authException = newException(AlpacaAuthError, reply.parsedMd[0].error.msg)
        authException.code = reply.parsedMd[0].error.code
        raise authException

  # Next, send auth
  let authMsg = $ %*{
    "action": "auth",
    "key": alpacaKey,
    "secret": alpacaSecret,
  }
  await socket.send(authMsg)

  # Wait for confirmation
  while true:
    let reply = await socket.receiveMdWsReply()
    if reply.parsedMd.len > 0:
      if reply.parsedMd[0].kind == AlpacaMdWsReplyKind.ConnectOk:
        # Unexpected but ok
        break
      elif reply.parsedMd[0].kind == AlpacaMdWsReplyKind.AuthOk:
        # Got the message we wanted
        break
      elif reply.parsedMd[0].kind == AlpacaMdWsReplyKind.AuthErr:
        var authException = newException(AlpacaAuthError, reply.parsedMd[0].error.msg)
        authException.code = reply.parsedMd[0].error.code
        raise authException

  # All set up, return the socket we created
  socket


proc subscribeData*(ws: WebSocket, symbols: seq[string]) {.async.} =
  let subscribeMessage = $ %*{
    "action": "subscribe",
    "trades": symbols,
    "quotes": symbols,
    "bars": symbols,
  }
  await ws.send(subscribeMessage)
