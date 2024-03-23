import std/asyncdispatch
import std/asyncnet
import std/json
import std/net
import std/rlocks
import std/tables

import chronicles

import ny/core/inspector/shared


var gStrategyStatesLock: RLock
# Strategy -> Symbol -> JsonNode
var gStrategyStates {.guard: gStrategyStatesLock.} = initTable[string, Table[string, JsonNode]]()
gStrategyStatesLock.initRLock()


proc getStrategyStates*(): lent Table[string, Table[string, JsonNode]] =
  withRLock(gStrategyStatesLock):
    return gStrategyStates


const kPerPeerLogFrequency = 10


proc handleClient(client: AsyncSocket) {.async, gcsafe.} =
  let peer = client.getPeerAddr
  var numMessagesFromPeer = 0
  logScope:
    peerIp=peer[0]
    peerPort=peer[1]

  info "Client connected"
  while true:
    try:
      let msgFromclient = await client.recvLine()
      inc numMessagesFromPeer
      debug "Client sent message", msgFromClient

      if numMessagesFromPeer mod kPerPeerLogFrequency == 0:
        info "Got N messages from peer", n=numMessagesFromPeer

      if client.isClosed():
        info "Client closed connection"
        return

      if msgFromclient.len == 0:
        info "Got empty message from client, closing connection"
        return

      try:
        let parsed = msgFromclient.parseJson
        let symbol = parsed["symbol"].getStr
        let strategyId = parsed["base"]["strategyId"].getStr

        withRLock(gStrategyStatesLock):
          {.gcsafe.}:
            if strategyId notin gStrategyStates:
              gStrategyStates[strategyId] = initTable[string, JsonNode]()
            gStrategyStates[strategyId][symbol] = parsed

      except JsonParsingError:
        error "Failed to parse strategy state message from client", msgFromclient
      except KeyError:
        error "Failed to lookup expected key from client message", msgFromclient

    except Exception:
      error "handleClient got unhandled generic exception", msg=getCurrentExceptionMsg()


proc serve() {.async, gcsafe .} =
  var server = newAsyncSocket()
  server.bindAddr(kMonitorServerPort)
  server.listen()
  info "Monitor server listening on port ", port=kMonitorServerPort

  while true:
    let client = await server.accept()
    asyncCheck handleClient(client)


proc runMonitorServer*() {.gcsafe.} =
  asyncCheck serve()
  runForever()


when isMainModule:
  runMonitorServer()
