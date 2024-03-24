import std/strformat

import std/json
import std/options
import std/strformat
import std/tables

import chronicles

import ny/core/inspector/server as inspector_server
import ny/apps/monitor/ws_manager



proc renderStrategyStates*(): string =
  {.gcsafe.}:
    let strategyStates = getStrategyStates()
  fmt"""
    <div id="strategy-states" hx-swap-oob="true">
      {strategyStates}
    </div>
  """


proc getRenderStrategyStates*(): WsSendRender =
  (proc (state: WsClientState): Option[string] {.nimcall, gcsafe, raises: [].} =
    try:
      some renderStrategyStates()
    except ValueError:
      error "Failed to render strategy states"
      none[string]()
  )


proc renderStrategyDetailsPage*(): string =
  fmt"""
    <div id="page">
      {renderStrategyStates()}
    </div>
  """
