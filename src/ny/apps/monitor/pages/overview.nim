import std/options
import std/strformat

import chronicles

import ny/apps/monitor/ws_manager
import ny/core/types/timestamp
import ny/apps/monitor/heartbeats


proc renderHeartbeats*(curTime: Timestamp, heartbeats: Table[string, bool]): string =
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
  msg


proc renderNumConnectedClientsImpl*(manager: WsManager): string {.gcsafe.} =
  fmt"""
  <div id="server-info" hx-swap-oob="true">
    <p>Num connected clients: {manager.numClients()}<p>
  </div>
  """


proc getRenderNumConnectedClients*(): WsSendRender =
  (proc (state: WsClientState): Option[string] {.nimcall, gcsafe, raises: [].} =
    let manager = getWsManager()
    if state.kind == Overview:
      try:
        some renderNumConnectedClientsImpl(manager)
      except ValueError:
        error "Value error trying to render num connected clients"
        none[string]()
    else:
      none[string]()
  )


proc renderOverviewPage*(): string =
  fmt"""
    <div id="page">
      {renderHeartbeats(getNowUtc(), getHeartbeats())}
      {renderNumConnectedClientsImpl(getWsManager())}
    </div>
  """


proc getRenderOverviewPage*(): WsSendRender =
  (proc (state: WsClientState): Option[string] {.closure, gcsafe, raises: [].} =
    try:
      some renderOverviewPage()
    except ValueError:
      error "Failed to render overview page"
      none[string]()
  )
