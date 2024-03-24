import std/strformat
import std/tables

import chronicles

import ny/core/types/timestamp


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
