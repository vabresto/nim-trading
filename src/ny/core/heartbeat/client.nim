## # Overview
## 
## The heartbeat client is primarily used by the ny-monitor service to ping the various
## services for liveness heartbeats. It uses a simple custom TCP protocol

import std/json
import std/net

import chronicles

import ny/core/heartbeat/shared

logScope:
  topics = "sys sys:heartbeat:client"

proc pingHeartbeat*(address: string, port: Port = kServerPort): bool {.raises: [].} =
  try:
    var client = newSocket()
    var response: string

    # Not all consumers compile with ssl support enabled, so we need to handle both situations
    when declared(SslError):
      try:
        client.connect(address, port)
        response = client.recvLine()
      except SslError:
        error "Ssl errored!", address, port, error=getCurrentExceptionMsg()
    else:
      client.connect(address, port)
      response = client.recvLine()

    trace "Got heartbeat", response
    true
  except TimeoutError:
    warn "Heartbeat timed out", address, port
    false
  except IOError, ValueError, JsonParsingError, OSError:
    error "Heartbeat errored!", address, port
    false

when isMainModule:
  let heartbeat = pingHeartbeat("127.0.0.1", kServerPort)
  info "Checking local heartbeat", heartbeat
