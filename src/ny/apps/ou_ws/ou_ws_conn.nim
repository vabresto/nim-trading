import std/asyncdispatch
import std/json
import std/options
import std/strutils

import chronicles except toJson
import jsony
import ws as tf_ws

# import ny/core/trading/types
import ny/core/types/timestamp
import ny/core/md/alpaca/ou_types


logScope:
  topics = "ny-ou-ws"


proc toString(str: seq[byte]): string =
  result = newStringOfCap(len(str))
  for ch in str:
    add(result, ch.char)

# proc renameHook*(v: var AlpacaOrder, fieldName: var string) =
#   if fieldName == "qty":
#     fieldName = "size"

proc receiveTradeUpdateReply*(ws: WebSocket, usesBinaryFrames: bool): Future[Option[tuple[ou: AlpacaOuWsReply, receiveTs: Timestamp]]] {.async.} =
  let rawPacket = if usesBinaryFrames:
    (await ws.receiveBinaryPacket()).toString()
  else:
    await ws.receiveStrPacket()

  let receiveTimestamp = getNowUtc()

  # Skip heartbeats
  if rawPacket == "":
    return none[tuple[ou: AlpacaOuWsReply, receiveTs: Timestamp]]()

  info "Got packet", rawPacket

  var packet = rawPacket.fromJson(AlpacaOuWsReply)
  packet.raw = rawPacket.parseJson

  # if "data" in packet.raw:
  #   if "order" in packet.raw["data"]:
  #     if "symbol" in packet.raw["data"]["order"]:
  #       packet.symbol = packet.raw["data"]["order"]["symbol"].getStr()

  return some (packet, receiveTimestamp)


proc initWebsocket*(baseUrl: string, alpacaKey: string, alpacaSecret: string): Future[WebSocket] {.async.} =
  ## Important note: paper trading websocket returns binary frames, but prod uses text frames
  let usesBinaryFrames = "paper" in baseUrl

  # First, create the socket
  var socket: WebSocket = await newWebSocket(baseUrl)
  socket.setupPings(60)

  # Next, send auth
  let authMsg = $ %*{
    "action": "auth",
    "key": alpacaKey,
    "secret": alpacaSecret,
  }
  await socket.send(authMsg)

  # Next, send listen
  let listenMsg = $ %*{
    "action": "listen",
    "data": {
      "streams": ["trade_updates"],
    }
  }
  await socket.send(listenMsg)

  var isAuthorized = false
  var isListening = false

  # Wait for confirmation
  # Should consider if it is possible for data to come before we exit the loop here
  while true:
    let rawPacket = if usesBinaryFrames:
      (await socket.receiveBinaryPacket()).toString
    else:
      await socket.receiveStrPacket()

    # Skip heartbeats
    if rawPacket == "":
      continue

    let packet = rawPacket.parseJson()

    if "stream" in packet:
      let streamName = packet["stream"].getStr()
      if streamName == "authorization":
        if "data" in packet and "status" in packet["data"]:
          if packet["data"]["status"].getStr() == "authorized":
            isAuthorized = true
            info "Got auth confirmation"
      elif streamName == "listening":
        if "data" in packet and "streams" in packet["data"]:
          if "trade_updates".newJString in packet["data"]["streams"].getElems():
            isListening = true
            info "Got listening confirmation"
      else:
        error "Got non-auth packet", packet
    
    if isAuthorized and isListening:
      break

  # All set up, return the socket we created
  socket
