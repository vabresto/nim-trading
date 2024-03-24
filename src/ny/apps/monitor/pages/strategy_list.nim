import std/json
import std/tables
import std/strformat

import chronicles

import ny/core/inspector/server as inspector_server
import ny/apps/monitor/ws_manager



proc renderStrategyList*(state: WsClientState): string =
  {.gcsafe.}:
    let strategyStates = getStrategyStates()

  result = """<div id="strategy-list" hx-swap-oob="true">"""
  result &= "<h2>Running Strategies</h2>"
  if strategyStates.len > 0:
    for strategy, strategyDetails in strategyStates:
      result &= "<h4>" & strategy & "</h4><ul>"
      for symbol, symbolDetails in strategyDetails:
        let hxVals = %* {
          "type": "change-page",
          "new-page": "strategy-details",
          "strategy": strategy,
          "symbol": symbol,
        }
        result &= fmt"""
          <li><a ws-send hx-vals='{hxVals}'>{symbol}</a></li>
        """
      result &= "</ul>"
  else:
    result &= """<span>No strategies</span>"""
  result &= "</div>"


proc renderStrategyListPage*(state: WsClientState): string =
  fmt"""
    <div id="page">
      {renderStrategyList(state)}
    </div>
  """
