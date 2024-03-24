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
      <section>
        <h2>Heartbeats</h2>
        <h4>{curTime.friendlyString}</h4>
        <table class="striped">
          <thead>
            <tr>
              <th>Service</th>
              <th>Status</th>
            </tr>
          </thead>
          <tbody>
    """

    for target, status in heartbeats:
      let statusColor = if status:
        "green"
      else:
        "red"

      msg &= fmt"""
      <tr>
        <td>{target}</td>
        <td style="color: {statusColor};">{status}</td>
      </tr>
      """

    msg &= fmt"""
          </tbody>
        </table>
      </section>
    </div>
    """
  except ValueError:
    error "Failed to prepare websocket message"
  msg


proc renderNumConnectedClientsImpl*(manager: WsManager): string {.gcsafe.} =
  fmt"""
  <div id="server-info" hx-swap-oob="true">
    <section>
      <h2>Server Info</h2>
      <p>Num connected clients: {manager.numClients()}</p>
    </section>
  </div>
  """


proc renderOverviewPage*(state: WsClientState): string =
  fmt"""
    <div id="page">
      {renderHeartbeats(getNowUtc(), getHeartbeats())}
      {renderNumConnectedClientsImpl(getWsManager())}
    </div>
  """
