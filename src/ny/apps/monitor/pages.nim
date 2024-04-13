import std/options

import chronicles
import db_connector/db_postgres

import ny/apps/monitor/ws_manager

import ny/apps/monitor/pages/overview
import ny/apps/monitor/pages/stats_daily_latency
import ny/apps/monitor/pages/strategy_details
import ny/apps/monitor/pages/strategy_list


proc renderPage*(state: WsClientState): Option[string] {.gcsafe, raises: [].} =
  ## Utility function to render based on the client's state (which is all tracked server-side)
  case state.kind
  of Overview:
    try:
      some renderOverviewPage(state)
    except ValueError:
      error "Failed to render overview page", err=getCurrentExceptionMsg()
      none[string]()
  of StatsDailyLatency:
    try:
      some renderStatsDailyLatencyPage(state)
    except ValueError:
      error "ValueError: Failed to render stats daily latency page", err=getCurrentExceptionMsg()
      none[string]()
    except DbError:
      error "DbError: Failed to render stats daily latency page", err=getCurrentExceptionMsg()
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
      error "ValueError: Failed to render strategy details page", err=getCurrentExceptionMsg()
      none[string]()
    except DbError:
      error "DbError: Failed to render strategy details page", err=getCurrentExceptionMsg()
      none[string]()
