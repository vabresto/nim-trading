import std/json
import std/options
import std/strformat
import std/tables

import chronicles

import ny/core/inspector/server as inspector_server
import ny/apps/monitor/ws_manager


proc getRenderStrategyStates*(): WsSendRender =
  (proc (state: WsClientState): Option[string] {.nimcall, gcsafe, raises: [].} =
    {.gcsafe.}:
      let strategyStates = getStrategyStates()

    try:
      some fmt"""
      <div id="strategy-states" hx-swap-oob="true">
        {strategyStates}
      </div>
      """
    except ValueError:
      error "Failed to render strategy states"
      none[string]()
  )
