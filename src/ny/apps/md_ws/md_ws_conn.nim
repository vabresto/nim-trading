import std/asyncdispatch
import std/json
import std/times

import jsony
import ws as tf_ws

import ny/apps/md_ws/parsing
import ny/core/md/alpaca/types
import ny/core/utils/time_utils

export types


proc receiveMdWsReply*(ws: WebSocket): Future[tuple[md: seq[AlpacaMdWsReply], receiveTs: DateTime]] {.async.} =
  let rawReply = await ws.receiveStrPacket()
  let receiveTimestamp = getNowUtc()
  if rawReply == "":
    return (@[], receiveTimestamp)
  let parsed = rawReply.fromJson(seq[AlpacaMdWsReply])
  return (parsed, receiveTimestamp)


proc initWebsocket*(feed: string, alpacaKey: string, alpacaSecret: string): Future[WebSocket] {.async.} =
  # First, create the socket
  var socket: WebSocket = await newWebSocket("wss://stream.data.alpaca.markets/v2/" & feed)
  socket.setupPings(60)

  # Will raise if we fail to auth
  while true:
    let (reply, _) = await socket.receiveMdWsReply()
    if reply.len > 0:
      if reply[0].kind == AlpacaMdWsReplyKind.ConnectOk:
        # Got the message we wanted
        break
      elif reply[0].kind == AlpacaMdWsReplyKind.AuthOk:
        # Unexpected but ok
        break
      elif reply[0].kind == AlpacaMdWsReplyKind.AuthErr:
        var authException = newException(AlpacaAuthError, reply[0].error.msg)
        authException.code = reply[0].error.code
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
    let (reply, _) = await socket.receiveMdWsReply()
    if reply.len > 0:
      if reply[0].kind == AlpacaMdWsReplyKind.ConnectOk:
        # Unexpected but ok
        break
      elif reply[0].kind == AlpacaMdWsReplyKind.AuthOk:
        # Got the message we wanted
        break
      elif reply[0].kind == AlpacaMdWsReplyKind.AuthErr:
        var authException = newException(AlpacaAuthError, reply[0].error.msg)
        authException.code = reply[0].error.code
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
