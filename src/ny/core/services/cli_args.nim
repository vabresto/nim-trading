# import std/json
import std/net
import std/options
# import std/os
import std/tables
import std/times

import chronicles except toJson
import db_connector/db_postgres
import nim_redis

import ny/core/db/mddb
# import ny/core/env/envs
# import ny/core/md/utils
import ny/core/types/timestamp
import ny/core/utils/rec_parseopt
import ny/core/utils/sim_utils
# import ny/core/streams/md_streams
# import ny/core/heartbeat/server
import ny/core/services/postgres
import ny/core/services/redis

export rec_parseopt
export postgres
export redis

template withCliArgs*(cliArgs: ParsedCliArgs, db: DbConn, today: untyped, mdSymbols: untyped, mdFeed: untyped, actions: untyped): untyped =
  var today: string
  today = if cliArgs.date.isSome:
    let date = cliArgs.date.get.format("yyyy-MM-dd")
    setIsSimulation(true)
    info "Running for historical date", date
    date
  else:
    let date = getNowUtc().toDateTime().getDateStr()
    info "Running for live date", date
    date

  logScope:
    isSim = isSimuluation()

  var mdSymbols: seq[string]
  var mdFeed: string
  (mdSymbols, mdFeed) = if cliArgs.symbols.len > 0:
    let symbols = cliArgs.symbols
    info "Running for manual override symbols", symbols
    (symbols, "manual")
  else:
    let mdFeed = db.getConfiguredMdFeed(today)
    let mdSymbols = db.getConfiguredMdSymbols(today, mdFeed)
    if mdSymbols.len == 0:
      error "No market data symbols requested; terminating", feed=mdFeed, symbols=mdSymbols
      quit 201
    info "Running for db configured symbols", symbols=mdSymbols
    (mdSymbols, mdFeed)
  
  actions
