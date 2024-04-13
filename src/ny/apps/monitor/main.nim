## # Overview
## 
## The [monitor (ny-monitor)](src/ny/apps/monitor/main.nim) app is the user interface for visibility into the system. All
## of the other components are pinged by the monitor to provide simple overviews into the trading system. The paper
## trading demo is running and accessible at http://142.93.153.5:8080/
## 
## 
## It provides:
## - visibility into currently running services
## - info about historical system latency
## - live and historical info about strategy trading performance

import std/asyncdispatch
import std/net
import std/options
import std/sequtils
import std/strutils
import std/sugar

import chronicles
import mummy

import ny/apps/monitor/server
import ny/apps/monitor/sender
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

  let senderThreadArgs = SenderThreadArgs(targets: targets)
  createThread(senderThread, runSenderThread, senderThreadArgs)
  createThread(monitorThread, runMonitorServer)
  let server = makeServer()
  server.serve(kPort, kHost)


when isMainModule:
  main()
