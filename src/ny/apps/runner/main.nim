import std/enumerate
import std/os
import std/tables
import std/times
import std/enumerate
import std/json
import std/net
import std/options
import std/os
import std/tables
import std/times

import chronicles
import db_connector/db_postgres
import nim_redis
import threading/channels

import ny/apps/runner/live/chans
import ny/apps/runner/live/runner as live_runner
import ny/apps/runner/live/timer # used
import ny/apps/runner/live/timer_types
import ny/apps/runner/simulated/market_data
import ny/apps/runner/simulated/runner as sim_runner
import ny/core/db/mddb
import ny/core/env/envs
import ny/core/types/strategy_base
import ny/core/env/envs
import ny/core/db/mddb
import ny/core/env/envs
import ny/core/md/alpaca/types
import ny/core/md/utils
import ny/core/types/timestamp
import ny/core/utils/rec_parseopt
import ny/core/utils/sim_utils

proc main(simulated: bool) =
  let cliArgs = parseCliArgs()

  var redisInitialized = false
  var dbInitialized = false

  var dbEverConnected = false

  var redis: RedisClient
  var db: DbConn

  var numProcessed = 0

  info "Running ..."
  
  try:
    if simulated:
      info "Starting SIMULATED runner ..."
      var sim = initSimulator()
      sim.simulate()
      info "Simulated runner done"
    else:
      info "Starting LIVE runner ..."

      createTimerThread()

      var symbols = @["AMD"]
      var runnerThreads = newSeq[Thread[RunnerThreadArgs]](symbols.len)
      for idx, symbol in enumerate(symbols):
        createThread(runnerThreads[idx], runner, RunnerThreadArgs(symbol: symbol))

      info "Starting redis ..."
      redis = newRedisClient(loadOrQuit("MD_REDIS_HOST"), pass=some loadOrQuit("MD_REDIS_PASS"))
      redisInitialized = true
      info "Redis connected"

      info "Starting market data db ..."
      db = getMdDb(loadOrQuit("MD_PG_HOST"), loadOrQuit("MD_PG_USER"), loadOrQuit("MD_PG_PASS"), loadOrQuit("MD_PG_NAME"))
      dbInitialized = true
      info "Market data db connected"
      dbEverConnected = true

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
          quit 1
        info "Running for db configured symbols", symbols=mdSymbols
        mdSymbols

      var lastIds = initTable[string, string]()
      var streamEventsProcessed = initTable[string, int64]()
      var streamEventsExpected = initTable[string, int64]()
      for symbol in mdSymbols:
        for streamName in [makeMdStreamName(today, symbol), makeOuStreamName(today, symbol)]:
          lastIds[streamName] = getInitialStreamId()
          streamEventsProcessed[streamName] = 0

          if isSimuluation():
            let res = redis.cmd(@["XLEN", streamName])
            if res.isOk:
              streamEventsExpected[streamName] = res[].num
          else:
            streamEventsExpected[streamName] = int64.high

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
            info "Done running sim, processed all events", streamEventsExpected, streamEventsProcessed
            quit 0

        redis.send(makeReadStreamsCommand(lastIds, simulation=isSimuluation()))

        let replyRaw = redis.receive()
        if replyRaw.isOk:
          if replyRaw[].kind == Error:
            error "Got error reply from stream", err=replyRaw[].err
            continue
        else:
          warn "Error receiving", err=replyRaw.error.msg

      # sleep(1000)
      # info "Sending message"
      # let (ic, oc) = getChannelsForSymbol(symbol)
      # let tc = getTimerChannel()
      # ic.send(InputEvent(kind: Timer))

      # var resp: OutputEvent
      # oc.recv(resp)
      # info "Main got", resp

      # if resp.kind == Timer:
      #   tc.send(TimerChanMsg(kind: CreateTimer, create: RequestTimer(timer: resp.timer)))
      
      # sleep(1000)

      # let db = getMdDb(loadOrQuit("MD_PG_HOST"), loadOrQuit("MD_PG_USER"), loadOrQuit("MD_PG_PASS"), loadOrQuit("MD_PG_NAME"))
      # let mdItr = createMarketDataIterator(db, "FAKEPACA", dateTime(2024, mMar, 15))
      # for row in mdItr():
      #   info "Got md", row
  
  except DbError:
    error "Failed to connect to db to start simulation", msg=getCurrentExceptionMsg()
  except Exception:
    error "Simulator raised generic exception", msg=getCurrentExceptionMsg(), trace=getCurrentException().getStackTrace()


when isMainModule:
  main(false)
