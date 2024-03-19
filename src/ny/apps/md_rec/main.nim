## This is a market data recorder
## It subscribes to a redis stream, and forwards the data into a db

# import std/json
import std/net
import std/options
import std/os
import std/tables
import std/times

import chronicles except toJson
import db_connector/db_postgres
import nim_redis

import ny/core/db/mddb
import ny/core/env/envs
import ny/core/md/utils
import ny/core/types/timestamp
import ny/core/utils/rec_parseopt
import ny/core/utils/sim_utils
import ny/core/streams/md_streams


logScope:
  topics = "ny-md-rec"

const kEventsProcessedHeartbeat = 1_000

proc main() =
  let cliArgs = parseCliArgs()

  var redisInitialized = false
  var dbInitialized = false

  var dbEverConnected = false

  var redis: RedisClient
  var db: DbConn

  var numProcessed = 0

  while true:
    try:
      info "Starting connections ..."
      info "Starting market data db ..."
      db = getMdDb(loadOrQuit("MD_PG_HOST"), loadOrQuit("MD_PG_USER"), loadOrQuit("MD_PG_PASS"), loadOrQuit("MD_PG_NAME"))
      dbInitialized = true
      info "Market data db connected"
      dbEverConnected = true

      info "Starting redis ..."
      redis = newRedisClient(loadOrQuit("MD_REDIS_HOST"), pass=some loadOrQuit("MD_REDIS_PASS"))
      redisInitialized = true
      info "Redis connected"

      let today = if cliArgs.date.isSome:
        let date = cliArgs.date.get.format("yyyy-MM-dd")
        setIsSimulation(true)
        info "Running for historical date", date
        date
      else:
        let date = getNowUtc().toDateTime().getDateStr()
        info "Running for live date", date
        date

      let mdSymbols = if cliArgs.symbols.len > 0:
        let symbols = cliArgs.symbols
        info "Running for manual override symbols", symbols
        symbols
      else:
        let mdFeed = db.getConfiguredMdFeed(today)
        let mdSymbols = db.getConfiguredMdSymbols(today, mdFeed)
        if mdSymbols.len == 0:
          error "No market data symbols requested; terminating", feed=mdFeed, symbols=mdSymbols
          quit 201
        info "Running for db configured symbols", symbols=mdSymbols
        mdSymbols

      var lastIds = initTable[string, string]()
      var streamEventsProcessed = initTable[string, int64]()
      var streamEventsExpected = initTable[string, int64]()
      for symbol in mdSymbols:
        let streamName = makeMdStreamName(today, symbol)
        lastIds[streamName] = getInitialStreamId()
        streamEventsProcessed[streamName] = 0

        if isSimuluation():
          let res = redis.cmd(@["XLEN", streamName])
          if res.isOk:
            streamEventsExpected[streamName] = res[].num
        else:
          streamEventsExpected[streamName] = int64.high

      info "Running main loop ...", streamEventsExpected
      while true:
        # We key by date; more efficient would be to only update this overnight, but whatever
        # This means we can just leave it running for multiple days in a row
        if cliArgs.date.isNone and getNowUtc().toDateTime().getDateStr() != today:
          break

        if isSimuluation():
          var keepRunning = false
          for symbol in mdSymbols:
            let streamName = makeMdStreamName(today, symbol)
            if streamEventsProcessed[streamName] < streamEventsExpected[streamName]:
              keepRunning = true
              break
          if not keepRunning:
            info "Done running md sim, processed all events", streamEventsExpected, streamEventsProcessed
            quit 0

        redis.send(makeReadStreamsCommand(lastIds, simulation=isSimuluation()))

        let replyRaw = redis.receive()
        if replyRaw.isOk:
          if replyRaw[].kind == Error:
            error "Got error reply from stream", err=replyRaw[].err
            continue

          let replyParseAttempt = replyRaw[].parseMdStreamResponse
          if replyParseAttempt.isOk:
            let reply = replyParseAttempt[]
            lastIds[reply.stream] = reply.id
            inc streamEventsProcessed[reply.stream]

            let recordTs = getNowUtc()
            db.insertRawMdEvent(reply.id, today, reply.mdReply, reply.rawJson, reply.receiveTimestamp, recordTs)
            inc numProcessed

            if numProcessed mod kEventsProcessedHeartbeat == 0:
              info "Total events processed", numProcessed
        else:
          warn "Error receiving", err=replyRaw.error.msg

    except OSError:
      error "OSError", msg=getCurrentExceptionMsg()

    except DbError:
      if not dbEverConnected:
        warn "DbError", msg=getCurrentExceptionMsg()  
      else:
        error "DbError", msg=getCurrentExceptionMsg()

    except Exception:
      error "Generic uncaught exception", msg=getCurrentExceptionMsg()

    finally:
      if dbInitialized:
        try:
          db.close()
        finally:
          dbInitialized = false

      if redisInitialized:
        try:
          redis.close()
        finally:
          redisInitialized = false

    sleep(1_000)


when isMainModule:
  main()
