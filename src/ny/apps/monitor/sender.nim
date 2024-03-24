import std/net
import std/options
import std/os
import std/strformat
import std/tables

import chronicles

import ny/apps/monitor/ws_manager
import ny/core/heartbeat/client
import ny/core/types/timestamp


type
  SenderThreadArgs* = object
    targets*: seq[string]
    functions*: seq[WsSendRender]


proc runSenderThread*(args: SenderThreadArgs) {.thread, gcsafe, raises: [].} =
  var totalNumHeartbeatsProcessed = 0
  var heartbeats = initTable[string, bool]()

  while true:
    let curTime = getNowUtc()
    
    for target in args.targets:
      heartbeats[target] = target.pingHeartbeat

    var msg = ""
    
    try:
      msg = fmt"""
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

      msg &= fmt"""
          </tbody>
        </table>
        <br>
      </div>
      """
    except ValueError:
      error "Failed to prepare websocket message"

    let manager = getWsManager()
    manager.send do (state: WsClientState) -> Option[string] {.closure, gcsafe, raises: [].} :
      if state.kind == Overview:
        some msg
      else:
        none[string]()
    for f in args.functions:
      manager.send(f)

    inc totalNumHeartbeatsProcessed

    # 12 count, 5 sec sleep per heartbeat = log once per minute
    if totalNumHeartbeatsProcessed mod 12 == 0:
      info "Monitor server still alive", totalNumHeartbeatsProcessed
    
    sleep(5_000)
