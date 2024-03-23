import std/asyncdispatch
import std/json
import std/parseutils
import std/strutils

import chronicles
import jsony
import ws as tf_ws

import ny/core/md/alpaca/types
import ny/core/types/timestamp
import ny/core/md/alpaca/parsing

export types


type
  MdWsReply = object
    receiveTs: Timestamp
    parsedMd: seq[AlpacaMdWsReply]
    rawMd: seq[JsonNode]

  MdWsRawMsg* = object
    symbol*: string
    msg*: string

  MdWsQuickReply* = object
    receiveTs*: Timestamp
    rawMd*: seq[MdWsRawMsg]


proc skimJson*(s: string): seq[MdWsRawMsg] =
  ## NOTE: This is not intended to be a public function, but that's required for runnable examples
  runnableExamples:
    let res1 = skimJson(""" [{"S":"AMD","T":"q","c":["R"],"t":"2024-03-18T13:30:01.842926026Z","z":"C","ap":194.24,"as":1,"ax":"V","bp":192.4,"bs":2,"bx":"V"}] """)
    assert res1.len == 1
    assert res1[0].symbol == "AMD"
    assert res1[0].msg == """{"S":"AMD","T":"q","c":["R"],"t":"2024-03-18T13:30:01.842926026Z","z":"C","ap":194.24,"as":1,"ax":"V","bp":192.4,"bs":2,"bx":"V"}"""

    let res2 = skimJson("""[
      {"S":"AMD","T":"q","c":["R"],"t":"2024-03-18T13:30:01.843783221Z","z":"C","ap":194.24,"as":1,"ax":"V","bp":193.1,"bs":2,"bx":"V"},
      {"S":"AMD","T":"q","c":["R"],"t":"2024-03-18T13:30:01.394366053Z","z":"C","ap":194.24,"as":1,"ax":"V","bp":179.35,"bs":1,"bx":"V"}
    ] """)
    assert res2.len == 2
    assert res2[0].symbol == "AMD"
    assert res2[0].msg == """{"S":"AMD","T":"q","c":["R"],"t":"2024-03-18T13:30:01.843783221Z","z":"C","ap":194.24,"as":1,"ax":"V","bp":193.1,"bs":2,"bx":"V"}"""
    assert res2[1].symbol == "AMD"
    assert res2[1].msg == """{"S":"AMD","T":"q","c":["R"],"t":"2024-03-18T13:30:01.394366053Z","z":"C","ap":194.24,"as":1,"ax":"V","bp":179.35,"bs":1,"bx":"V"}"""

  var idx = 0
  while idx < s.len:
    let letter = s[idx]
    case letter
    of '[':
      # Start of array, do nothing
      # Should only see this at the top level, and we should be parsing everything else in between
      discard
    of '{':
      var msg: string
      let consumed = parseUntil(s, token=msg, until='}', start=idx)

      idx += consumed
      if consumed > 0:
        msg &= '}'
        inc idx
      else:
        error "Got malformed market data message", s
        break

      # Next get the symbol
      var symbol: string
      let symbolLoc = msg.find("\"S\":")
      if symbolLoc > -1:
        discard parseUntil(msg, token=symbol, until='"', start=symbolLoc+5)
      else:
        error "Failed to find symbol from market data message", msg, s
        continue

      result.add MdWsRawMsg(symbol: symbol, msg: msg)
    else:
      # Ignore any other characters
      discard
    inc idx


proc skimMdWsReply*(ws: WebSocket): Future[MdWsQuickReply] {.async.} =
  let rawReply = await ws.receiveStrPacket()
  let receiveTimestamp = getNowUtc()
  if rawReply == "":
    return MdWsQuickReply(receiveTs: receiveTimestamp, rawMd: @[])
  return MdWsQuickReply(receiveTs: receiveTimestamp, rawMd: rawReply.skimJson())


proc receiveMdWsReply(ws: WebSocket): Future[MdWsReply] {.async.} =
  let rawReply = await ws.receiveStrPacket()
  let receiveTimestamp = getNowUtc()
  if rawReply == "":
    return MdWsReply(receiveTs: receiveTimestamp, parsedMd: @[], rawMd: @[])
  # TODO: Write manual parsing for this - all we need is to extract the symbol and the containing json object from a list
  # Further optimization, md never has nested json objects (but can have arrays in the objects)
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
  socket.setupPings(15)

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
