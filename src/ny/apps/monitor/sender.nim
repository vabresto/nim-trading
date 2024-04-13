import std/net
import std/os

import chronicles

import ny/apps/monitor/ws_manager
import ny/core/heartbeat/client
import ny/apps/monitor/heartbeats

import ny/apps/monitor/pages


type
  SenderThreadArgs* = object
    targets*: seq[string]


proc runSenderThread*(args: SenderThreadArgs) {.thread, gcsafe, raises: [].} =
  ## This thread is responsible for pinging services we need to track, and checking their heartbeats
  while true:
    for target in args.targets:
      setHeartbeat(target, target.pingHeartbeat)
    incHeartbeatsProcessed()
    
    getWsManager().send(renderPage)

    # 12 count, 5 sec sleep per heartbeat = log once per minute
    if getHeartbeatsProcessed() mod 12 == 0:
      info "Monitor server still alive", totalNumHeartbeatsProcessed=getHeartbeatsProcessed()
    
    sleep(5_000)
