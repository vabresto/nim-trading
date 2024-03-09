import std/asyncdispatch
import std/json
import std/os

import jsony
import ws as tf_ws

import apps/mdconn/parsing
import core/md/alpaca/types

export types


proc receiveMdWsReply*(ws: WebSocket): Future[seq[AlpacaMdWsReply]] {.async.} =
  let rawReply = await ws.receiveStrPacket()
  if rawReply == "":
    return @[]
  let parsed = rawReply.fromJson(seq[AlpacaMdWsReply])
  return parsed


proc initWebsocket*(feed: string): Future[WebSocket] {.async.} =
  # First, create the socket
  var socket: WebSocket = await newWebSocket("wss://stream.data.alpaca.markets/v2/" & feed)
  socket.setupPings(60)

  # Will raise if we fail to auth
  while true:
    let reply = await socket.receiveMdWsReply()
    if reply.len > 0:
      if reply[0].kind == AlpacaMdWsReplyKind.ConnectOk:
        # Got the message we wanted
        break
      elif reply[0].kind == AlpacaMdWsReplyKind.AuthOk:
        # Unexpected but ok
        break
      elif reply[0].kind == AlpacaMdWsReplyKind.AuthErr:
        var authException = newException(AlpacaAuthError, reply[0].authErrMsg)
        authException.code = reply[0].code
        raise authException

  # Next, send auth
  let authMsg = $ %*{
    "action": "auth",
    "key": getEnv("ALPACA_PAPER_KEY"),
    "secret": getEnv("ALPACA_PAPER_SECRET"),
  }
  await socket.send(authMsg)

  # Wait for confirmation
  while true:
    let reply = await socket.receiveMdWsReply()
    if reply.len > 0:
      if reply[0].kind == AlpacaMdWsReplyKind.ConnectOk:
        # Unexpected but ok
        break
      elif reply[0].kind == AlpacaMdWsReplyKind.AuthOk:
        # Got the message we wanted
        break
      elif reply[0].kind == AlpacaMdWsReplyKind.AuthErr:
        var authException = newException(AlpacaAuthError, reply[0].authErrMsg)
        authException.code = reply[0].code
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
