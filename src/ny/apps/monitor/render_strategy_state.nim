import std/json
import std/strformat
import std/tables

import ny/core/inspector/server as inspector_server


proc renderStrategyStates*(): string {.gcsafe.} =
  {.gcsafe.}:
    let strategyStates = getStrategyStates()

  fmt"""
  <div id="strategy-states" hx-swap-oob="true">
    {strategyStates}
  </div>
  """
