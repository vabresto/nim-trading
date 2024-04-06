import std/json
import std/math
import std/tables
import std/times
import std/strformat

import ny/core/inspector/server as inspector_server
import ny/apps/monitor/db_wrapper
import ny/apps/monitor/ws_manager

import chronicles
import db_connector/db_postgres


func formatDuration(dur: Duration): string =
  const nanosecondsPerSecond = 1_000_000_000
  const nanosecondsPerMinute = 60 * nanosecondsPerSecond

  let nanos = dur.inNanoseconds

  let minutes = floorDiv(nanos, nanosecondsPerMinute)
  let seconds = floorDiv(nanos mod nanosecondsPerMinute, nanosecondsPerSecond)
  let fractionalSeconds = (nanos mod nanosecondsPerSecond)

  fmt"{minutes:02}:{seconds:02}.{fractionalSeconds:09}"


proc renderStatsDailyLatency*(state: WsClientState): string =
  result = """<div id="stats-daily-latency" hx-swap-oob="true">"""

  try:
    let stats = getDailyLatencyStats()
    result &= "<h2>Stats</h2>"
    result &= """
      <section>
        <h3>Daily Latency Stats</h3>
        <div class="overflow-auto">
          <table class="striped">
            <thead>
              <tr>
                <th>Date</th>
                <th>Num Events</th>
                <th>Avg Network Time</th>
                <th>Avg Internal Time</th>
                <th>Avg Total Time</th>
                <th>p50 Network Time</th>
                <th>p75 Network Time</th>
                <th>p99 Network Time</th>
                <th>p50 Internal Time</th>
                <th>p75 Internal Time</th>
                <th>p99 Internal Time</th>
                <th>p50 Total Time</th>
                <th>p75 Total Time</th>
                <th>p99 Total Time</th>
              </tr>
            </thead>
          <tbody>
    """
    
    if stats.len == 0:
      result &= """
        <tr>
          <td colspan="14" style="text-align: center;">No Latency Stats</td>
        </tr>
      """

    for item in stats:
      result &= fmt"""
        <tr>
          <td>{item.date}</td>
          <td>{item.numEvents}</td>
          <td>{item.avgNetworkTime.formatDuration}</td>
          <td>{item.avgInternalTime.formatDuration}</td>
          <td>{item.avgTotalTime.formatDuration}</td>
          <td>{item.p50NetworkTime.formatDuration}</td>
          <td>{item.p75NetworkTime.formatDuration}</td>
          <td>{item.p99NetworkTime.formatDuration}</td>
          <td>{item.p50InternalTime.formatDuration}</td>
          <td>{item.p75InternalTime.formatDuration}</td>
          <td>{item.p99InternalTime.formatDuration}</td>
          <td>{item.p50TotalTime.formatDuration}</td>
          <td>{item.p75TotalTime.formatDuration}</td>
          <td>{item.p99TotalTime.formatDuration}</td>
        </tr>
      """

    result &= """
          </tbody>
        </table>
      </div>
    </section>
    """
  except DbError:
    error "DB error in renderStatsDailyLatency", error=getCurrentExceptionMsg()
  finally:
    result &= "</div>"


proc renderStatsDailyLatencyPage*(state: WsClientState): string =
  fmt"""
    <div id="page">
      {renderStatsDailyLatency(state)}
    </div>
  """
