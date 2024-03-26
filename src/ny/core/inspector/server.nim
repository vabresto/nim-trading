import std/asyncdispatch
import std/asyncnet
import std/json
import std/net
import std/os
import std/rlocks
import std/strutils
import std/tables

import chronicles except toJson

import ny/core/env/envs
import ny/core/inspector/shared


type
  StrategyStatesObj = Table[string, Table[string, Table[string, JsonNode]]]

var gStrategyStatesLock: RLock
# Date -> Strategy -> Symbol -> JsonNode
var gStrategyStates {.guard: gStrategyStatesLock.}: StrategyStatesObj = initTable[string, Table[string, Table[string, JsonNode]]]()
gStrategyStatesLock.initRLock()


proc getStrategyStates*(): lent StrategyStatesObj =
  withRLock(gStrategyStatesLock):
    return gStrategyStates


proc loadStrategyStates() =
  let dumpFilePath = loadOrQuit("STRATEGY_DUMP_FILE")
  if not dumpFilePath.fileExists:
    info "No strategy dump file found; starting fresh"
    return

  info "Loading strategy states from saved file", dumpFilePath
  let dumpFile = open(dumpFilePath, fmRead)
  defer: dumpFile.close()

  let rawData = dumpFile.readAll.strip
  if rawData.len == 0:
    return
  
  withRLock(gStrategyStatesLock):
    {.gcsafe.}:
      gStrategyStates = rawData.parseJson.to(StrategyStatesObj)


proc dumpStrategyStates*() {.gcsafe.} =
  let dumpFile = open(loadOrQuit("STRATEGY_DUMP_FILE"), fmWrite)
  defer: dumpFile.close()

  var strategyDump = newJObject()
  withRLock(gStrategyStatesLock):
    {.gcsafe.}:
      strategyDump = %* gStrategyStates

  dumpFile.write(strategyDump.pretty)


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
        let dateStr = parsed["date"].getStr
        let strategyId = parsed["base"]["strategyId"].getStr

        withRLock(gStrategyStatesLock):
          {.gcsafe.}:
            if dateStr notin gStrategyStates:
              gStrategyStates[dateStr] = initTable[string, Table[string, JsonNode]]()
            if strategyId notin gStrategyStates[dateStr]:
              gStrategyStates[dateStr][strategyId] = initTable[string, JsonNode]()
            gStrategyStates[dateStr][strategyId][symbol] = parsed

        dumpStrategyStates()

      except JsonParsingError:
        error "Failed to parse strategy state message from client", msgFromclient, msg=getCurrentExceptionMsg()
      except KeyError:
        error "Failed to lookup expected key from client message", msgFromclient, msg=getCurrentExceptionMsg()

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
  loadStrategyStates()

  asyncCheck serve()
  runForever()


when isMainModule:
  runMonitorServer()
