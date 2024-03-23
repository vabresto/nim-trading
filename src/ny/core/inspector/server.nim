import std/asyncdispatch
import std/asyncnet
import std/json
import std/net

import chronicles

import ny/core/inspector/shared


const kPerPeerLogFrequency = 10


proc handleClient(client: AsyncSocket) {.async.} =
  let peer = client.getPeerAddr
  var numMessagesFromPeer = 0
  logScope:
    peerIp=peer[0]
    peerPort=peer[1]

  info "Client connected"
  while true:
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


proc serve() {.async.} =
  var server = newAsyncSocket()
  server.bindAddr(kMonitorServerPort)
  server.listen()
  info "Server listening on port ", port=kMonitorServerPort

  while true:
    let client = await server.accept()
    asyncCheck handleClient(client)


proc serverLoop() =
  asyncCheck serve()
  runForever()


when isMainModule:
  serverLoop()
