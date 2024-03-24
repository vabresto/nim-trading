import std/strformat

import std/json
import std/options
import std/strformat
import std/tables

import chronicles

import ny/core/inspector/server as inspector_server
import ny/apps/monitor/ws_manager



proc renderStrategyStates*(state: WsClientState): string =
  {.gcsafe.}:
    let strategyStates = getStrategyStates()
  fmt"""
    <div id="strategy-states" hx-swap-oob="true">
      {strategyStates}
    </div>
  """


proc renderStrategyDetailsPage*(state: WsClientState): string =
  fmt"""
    <div id="page">
      {renderStrategyStates(state)}
    </div>
  """
