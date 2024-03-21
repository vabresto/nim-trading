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
  info "Client connected", peerIp=peer[0], peerPort=peer[1]
  let resp = %* {
    "now": $getNowUtc(),
  }
  client.send($resp & "\n")
  info "Responded"

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
