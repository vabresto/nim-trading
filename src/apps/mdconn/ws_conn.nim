import std/asyncdispatch
import std/json
import std/os

import jsony
import ws as tf_ws

import apps/mdconn/alpaca/parsing
import apps/mdconn/alpaca/types


proc receiveMdWsReply*(ws: WebSocket): Future[seq[AlpacaMdWsReply]] {.async.} =
  let rawReply = await ws.receiveStrPacket()
  # echo "Got raw reply: ", rawReply
  if rawReply == "":
    return @[]
  let parsed = rawReply.fromJson(seq[AlpacaMdWsReply])
  # echo "Parsed: ", parsed
  return parsed


proc initWebsocket*(): Future[WebSocket] {.async.} =
  # First, create the socket
  var socket: WebSocket = await newWebSocket("wss://stream.data.alpaca.markets/v2/test")
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

  socket


proc subscribeFakeData*(ws: WebSocket) {.async.} =
  let subscribeMessage = $ %*{
    "action": "subscribe",
    "trades": @["FAKEPACA"],
    "quotes": @["FAKEPACA"],
    "bars": @["FAKEPACA"],
  }
  await ws.send(subscribeMessage)


proc mdWsEventLoop*(ws: WebSocket) {.async.} =
  discard
