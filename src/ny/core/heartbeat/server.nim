## # Overview
## 
## The heartbeat server module runs in an independent thread, is used for liveness checks by
## the ny-monitor service. It uses a simple custom TCP protocol.

import std/json
import std/net
import std/rlocks

import chronicles

import ny/core/heartbeat/shared
import ny/core/types/timestamp

logScope:
  topics = "sys sys:heartbeat:server"

var gHeartbeatLock: RLock
var gStartedHeartbeatThread {.guard: gHeartbeatLock.} = false
var heartbeatServerThread: Thread[void]

proc handleClient(client: Socket) =
  let peer = client.getPeerAddr
  trace "Client connected", peerIp=peer[0], peerPort=peer[1]
  let resp = %* {
    "now": $getNowUtc(),
  }
  client.send($resp & "\n")
  trace "Responded", peerIp=peer[0], peerPort=peer[1]

proc serverLoop() =
  var server = newSocket()
  server.bindAddr(kServerPort)
  server.listen()

  info "Server listening on port ", kServerPort

  while true:
    var client: Socket
    server.accept(client)
    handleClient(client)

proc startHeartbeatServerThread*() {.raises: [].}=
  withRLock(gHeartbeatLock):
    if not gStartedHeartbeatThread:
      info "Starting heartbeat thread"
      gStartedHeartbeatThread = true
      try:
        createThread(heartbeatServerThread, serverLoop)
      except ResourceExhaustedError:
        error "Failed to start heartbeat thread", error=getCurrentExceptionMsg()

when isMainModule:
  serverLoop()
