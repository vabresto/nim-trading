import std/net
import std/options
import std/os

import chronicles

import ny/apps/monitor/ws_manager
import ny/core/heartbeat/client
import ny/core/types/timestamp
import ny/apps/monitor/render_heartbeats
import ny/apps/monitor/heartbeats


type
  SenderThreadArgs* = object
    targets*: seq[string]
    functions*: seq[WsSendRender]


proc runSenderThread*(args: SenderThreadArgs) {.thread, gcsafe, raises: [].} =
  while true:
    let curTime = getNowUtc()
    
    for target in args.targets:
      setHeartbeat(target, target.pingHeartbeat)

    var msg = renderHeartbeats(curTime, getHeartbeats())

    let manager = getWsManager()
    manager.send do (state: WsClientState) -> Option[string] {.closure, gcsafe, raises: [].} :
      if state.kind == Overview:
        some msg
      else:
        none[string]()
    for f in args.functions:
      manager.send(f)

    incHeartbeatsProcessed()

    # 12 count, 5 sec sleep per heartbeat = log once per minute
    if getHeartbeatsProcessed() mod 12 == 0:
      info "Monitor server still alive", totalNumHeartbeatsProcessed=getHeartbeatsProcessed()
    
    sleep(5_000)
