import std/options
import std/strformat

import chronicles

import ny/apps/monitor/ws_manager
import ny/apps/monitor/render_server_info
import ny/core/types/timestamp
import ny/apps/monitor/render_heartbeats
import ny/apps/monitor/heartbeats


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
