import std/options

import chronicles

import ny/apps/monitor/ws_manager

import ny/apps/monitor/pages/overview
import ny/apps/monitor/pages/strategy_details
import ny/apps/monitor/pages/strategy_list


proc renderPage*(state: WsClientState): Option[string] {.gcsafe, raises: [].} =
  case state.kind
  of Overview:
    try:
      some renderOverviewPage(state)
    except ValueError:
      error "Failed to render overview page", err=getCurrentExceptionMsg()
      none[string]()
  of StrategyList:
    try:
      some renderStrategyListPage(state)
    except ValueError:
      error "Failed to render strategy list page", err=getCurrentExceptionMsg()
      none[string]()
  of StrategyDetails:
    try:
      some renderStrategyDetailsPage(state)
    except ValueError:
      error "Failed to render strategy details page", err=getCurrentExceptionMsg()
      none[string]()
