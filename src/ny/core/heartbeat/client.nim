import std/json
import std/net

import chronicles

import ny/core/heartbeat/shared

logScope:
  topics = "sys sys:heartbeat:client"

proc pingHeartbeat*(address: string, port: Port = kServerPort): bool {.raises: [].} =
  try:
    var client = newSocket()
    client.connect(address, port)

    let response = client.recvLine()
    trace "Got heartbeat", response
    true
  except TimeoutError:
    warn "Heartbeat timed out", address, port
    false
  except IOError, ValueError, JsonParsingError, OSError, SslError:
    error "Heartbeat errored!", address, port
    false

when isMainModule:
  let heartbeat = pingHeartbeat("127.0.0.1", kServerPort)
  info "Checking local heartbeat", heartbeat
