import std/options

import chronicles

import ny/apps/monitor/ws_manager

import ny/apps/monitor/pages/overview
import ny/apps/monitor/pages/strategy_details


proc renderPage*(state: WsClientState): Option[string] {.gcsafe, raises: [].} =
  case state.kind
  of Overview:
    try:
      some renderOverviewPage(state)
    except ValueError:
      error "Failed to render overview page"
      none[string]()
  of StrategyDetails:
    try:
      some renderStrategyDetailsPage(state)
    except ValueError:
      error "Failed to render strategy details page"
      none[string]()
