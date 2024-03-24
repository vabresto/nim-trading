import std/strformat

import std/strformat
import std/tables

import chronicles

import ny/core/inspector/server as inspector_server
import ny/apps/monitor/ws_manager



proc renderStrategyList*(state: WsClientState): string =
  {.gcsafe.}:
    let strategyStates = getStrategyStates()

  result = """<div id="strategy-list" hx-swap-oob="true">"""
  result &= "<h2>Running Strategies</h2>"
  if strategyStates.len > 0:
    result &= "<ul>"
    for strategy, strategyDetails in strategyStates:
      result &= "<li><p>" & strategy & "</p>"
      result &= "<ul>"
      for symbol, symbolDetails in strategyDetails:
        result &= fmt"""
          <li>
          <form ws-send>
            <input type="hidden" id="type" name="type" value="change-page">
            <input type="hidden" id="new-page" name="new-page" value="strategy-details">
            <input type="hidden" id="strategy" name="strategy" value="{strategy}">
            <input type="hidden" id="symbol" name="symbol" value="{symbol}">
            <button type="submit">{symbol}</button>
          </form>
          </li>
        """
      result &= "</ul>"
      result &= "</li>"
    result &= "</ul>"
  else:
    result &= "No strategies"
  result &= "</div>"


proc renderStrategyListPage*(state: WsClientState): string =
  fmt"""
    <div id="page">
      {renderStrategyList(state)}
    </div>
  """
