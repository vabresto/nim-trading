import std/json
import std/tables
import std/strformat

import ny/core/inspector/server as inspector_server
import ny/apps/monitor/ws_manager



proc renderStrategyList*(state: WsClientState): string =
  ## This function renders the table of historical strategy runs
  {.gcsafe.}:
    let strategyStates = getStrategyStates()

  result = """<div id="strategy-list" hx-swap-oob="true">"""
  result &= "<h2>Strategies</h2>"
  if strategyStates.len > 0:
    for date, strategies in strategyStates:
      result &= "<h3>" & date & "</h3><ul>"
      for strategy, strategyDetails in strategies:
        result &= "<h4>" & strategy & "</h4><ul>"
        for symbol, symbolDetails in strategyDetails:
          let hxVals = %* {
            "type": "change-page",
            "new-page": "strategy-details",
            "strategy": strategy,
            "symbol": symbol,
            "date": date,
          }
          result &= fmt"""
            <li><a ws-send hx-vals='{hxVals}'>{symbol}</a></li>
          """
        result &= "</ul>"
      result &= "</ul>"
  else:
    result &= """<span>No strategies</span>"""
  result &= "</div>"


proc renderStrategyListPage*(state: WsClientState): string =
  ## Renders the list of strategies (what ran historically)
  fmt"""
    <div id="page">
      {renderStrategyList(state)}
    </div>
  """
