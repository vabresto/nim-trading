import std/asyncdispatch
import std/net
import std/options
import std/sequtils
import std/strutils
import std/sugar

import chronicles
import mummy

import ny/apps/monitor/render_server_info
import ny/apps/monitor/render_strategy_state
import ny/apps/monitor/routes/server
import ny/apps/monitor/sender
import ny/apps/monitor/ws_manager
import ny/core/env/envs
import ny/core/inspector/server as inspector_server

const kHost = "0.0.0.0"
const kPort = 8080.Port

var senderThread: Thread[SenderThreadArgs]
var monitorThread: Thread[void]


proc main() = 
  let targets = block:
    let requestedTargets = getOptEnv("NY_MON_TARGETS")
    if requestedTargets.isSome:
      let parsed = requestedTargets.get.split(",").map(x => x.strip)
      if parsed.len > 0:
        info "Monitoring services", parsed
        parsed
      else:
        warn "No monitor targets requested, defaulted to local (127.0.0.1)"
        @["127.0.0.1"]
    else:
      warn "No monitor targets requested, defaulted to local (127.0.0.1)"
      @["127.0.0.1"]

  info "Serving ...", host=kHost, port=kPort

  let senders: seq[WsSendRender] = @[getRenderNumConnectedClients(), getRenderStrategyStates()]
  let senderThreadArgs = SenderThreadArgs(targets: targets, functions: senders)
  createThread(senderThread, runSenderThread, senderThreadArgs)
  createThread(monitorThread, runMonitorServer)
  let server = makeServer()
  server.serve(kPort, kHost)


when isMainModule:
  main()
