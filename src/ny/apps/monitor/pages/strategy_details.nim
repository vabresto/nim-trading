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

  result = """<div id="strategy-states" hx-swap-oob="true">"""
  result &= $strategyStates
  result &= "</div>"


proc renderStrategyDetailsPage*(state: WsClientState): string =
  fmt"""
    <div id="page">
      {renderStrategyStates(state)}
    </div>
  """
