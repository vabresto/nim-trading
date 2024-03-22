# import std/json
import std/net
import std/options
# import std/os
import std/tables
import std/times

import chronicles except toJson
import db_connector/db_postgres
import nim_redis

# import ny/core/db/mddb
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

import ny/core/services/cli_args

template processStreams*(cliArgs: ParsedCliArgs, db: DbConn, redis: RedisClient, makeStreamNameFunc: (proc (date: string, symbol: string): string {.noSideEffect.}), today: untyped, lastIds: untyped, streamEventsProcessed: untyped, actions: untyped): untyped = 
  withCliArgs(cliArgs, db, today, mdSymbols, mdFeed):
    var lastIds = initTable[string, string]()
    var streamEventsProcessed = initTable[string, int64]()
    var streamEventsExpected = initTable[string, int64]()
    for symbol in mdSymbols:
      let streamName = makeStreamNameFunc(today, symbol)
      lastIds[streamName] = getInitialStreamId()
      streamEventsProcessed[streamName] = 0

      if isSimuluation():
        let res = redis.cmd(@["XLEN", streamName])
        if res.isOk:
          streamEventsExpected[streamName] = res[].num
      else:
        streamEventsExpected[streamName] = int64.high

    info "Running main loop ...", streamEventsExpected=streamEventsExpected
    while true:
      # We key by date; more efficient would be to only update this overnight, but whatever
      # This means we can just leave it running for multiple days in a row
      if cliArgs.date.isNone and getNowUtc().toDateTime().getDateStr() != today:
        break

      if isSimuluation():
        var keepRunning = false
        for symbol in mdSymbols:
          let streamName = makeStreamNameFunc(today, symbol)
          if streamEventsProcessed[streamName] < streamEventsExpected[streamName]:
            keepRunning = true
            break
        if not keepRunning:
          info "Done running md sim, processed all events", streamEventsExpected=streamEventsExpected, streamEventsProcessed=streamEventsProcessed
          quit 0

      redis.send(makeReadStreamsCommand(lastIds, simulation=isSimuluation()))
      actions
