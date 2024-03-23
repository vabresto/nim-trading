import std/asyncdispatch
import std/json
import std/net
import std/rlocks
import std/options
import std/os
import std/sequtils
import std/sets
import std/strformat
import std/strutils
import std/sugar
import std/tables

import chronicles
import mummy
import mummy/routers

import ny/core/env/envs
import ny/core/heartbeat/client
import ny/core/types/timestamp
import ny/core/inspector/server as inspector_server

const kHost = "0.0.0.0"
const kPort = 8080.Port

var gWebsocketsLock: RLock
gWebsocketsLock.initRLock()

var gWebsockets {.guard: gWebsocketsLock.} = initHashSet[WebSocket]()
var heartbeatsThread: Thread[seq[string]]
var monitorThread: Thread[void]

proc runHeartbeatsThread(targets: seq[string]) {.thread.} =
  while true:
    let curTime = getNowUtc()
    var heartbeats = initTable[string, bool]()
    for target in targets:
      heartbeats[target] = target.pingHeartbeat

    var msg = fmt"""
    <div id="heartbeats" hx-swap-oob="true">
      <h2>Heartbeats as of {$curTime}</h2>
      <table>
        <thead>
          <tr>
            <th>Target</th>
            <th>Status</th>
          </tr>
        </thead>
        <tbody>
    """

    for target, status in heartbeats:
      msg &= fmt"""
      <tr>
        <td>{target}</td>
        <td>{status}</td>
      </tr>
      """

    msg &= """
        </tbody>
      </table>
    """

    {.gcsafe.}:
      let strategyStates = getStrategyStates()

    msg &= fmt"""
      <br>
      <div>
        {strategyStates}
      </div>
    </div>
    """

    withRLock(gWebsocketsLock):
      {.gcsafe.}:
        for ws in gWebsockets:
          ws.send(msg)
    
    sleep(15_000)

proc indexHandler(request: Request) =
  var headers: HttpHeaders
  headers["Content-Type"] = "text/html"
  request.respond(200, headers, fmt"""
  <script src="https://unpkg.com/htmx.org@1.9.11" integrity="sha384-0gxUXCCR8yv9FM2b+U3FDbsKthCI66oH5IA9fHppQq9DDMHuMauqq1ZHBpJxQ0J0" crossorigin="anonymous"></script>
  <script src="https://unpkg.com/htmx.org@1.9.11/dist/ext/ws.js"></script>
  <div hx-ext="ws" ws-connect="/ws">
    <div id="heartbeats"</div>
  </div>
  """)

proc upgradeHandler(request: Request) =
  let websocket = request.upgradeToWebSocket()
  withRLock(gWebsocketsLock):
    {.gcsafe.}:
      gWebsockets.incl websocket

proc websocketHandler(
  websocket: WebSocket,
  event: WebSocketEvent,
  message: Message
) =
  warn "Unexpectedly got message from client websocket", event, message
  case event:
  of OpenEvent:
    discard
  of MessageEvent:
    echo message.kind, ": ", message.data
  of ErrorEvent:
    discard
  of CloseEvent:
    discard

var router: Router
router.get("/", indexHandler)
router.get("/ws", upgradeHandler)

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

let server = newServer(router, websocketHandler)
info "Serving ...", host=kHost, port=kPort
createThread(heartbeatsThread, runHeartbeatsThread, targets)
createThread(monitorThread, runMonitorServer)
server.serve(kPort, kHost)
