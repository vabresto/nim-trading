import std/enumerate
import std/tables
import std/times
import std/net
import std/options
import std/strutils

import chronicles
import db_connector/db_postgres
import nim_redis
import threading/channels

import ny/apps/runner/live/chans
import ny/apps/runner/live/runner as live_runner
import ny/apps/runner/live/timer # used
import ny/apps/runner/simulated/runner as sim_runner
import ny/core/db/mddb
import ny/core/env/envs
import ny/core/types/strategy_base
import ny/core/env/envs
import ny/core/md/alpaca/types
import ny/core/md/utils
import ny/core/types/timestamp
import ny/core/utils/rec_parseopt
import ny/core/utils/sim_utils
import ny/core/streams/stream_utils
import ny/core/streams/ou_streams
import ny/core/streams/md_streams
import ny/core/md/alpaca/conversions
import ny/apps/runner/live/mkt_output
import ny/core/md/alpaca/ou_types

logScope:
  topics = "sys runner"

type
  MergedStreamKind = enum
    MarketData
    OrderUpdate
  
  MergedStreamResponse = object
    stream: string
    id: string
    case kind: MergedStreamKind
    of MarketData:
      md: MdStreamResponse
    of OrderUpdate:
      ou: OuStreamResponse

const kEventsProcessedHeartbeat = 25

proc parseMergedStreamResponse(val: RedisValue): ?!MergedStreamResponse =
  # Need to parse both md and ou stream data
  # Ideally would like to reuse the existing code somehow
  let (streamName, id) = ?val.getStreamName

  if streamName.startsWith "md:":
    success MergedStreamResponse(
      stream: streamName,
      id: id,
      kind: MarketData,
      md: ?val.parseMdStreamResponse,
    )
  elif streamName.startsWith "ou:":
    success MergedStreamResponse(
      stream: streamName,
      id: id,
      kind: OrderUpdate,
      ou: ?val.parseOuStreamResponse,
    )
  else:
    error "Got unknown stream", streamName
    failure "Unknown stream type: " & streamName

proc symbol(resp: MergedStreamResponse): Option[string] =
  case resp.kind
  of MarketData:
    # Note: This is because we can get auth replies from alpaca
    # However, those replies don't get propagated down to here
    # It would mean writing another type to convert, not important now
    resp.md.mdReply.getSymbol
  of OrderUpdate:
    some resp.ou.ouReply.symbol

proc main() =
  let cliArgs = parseCliArgs()

  var redisInitialized = false
  var dbInitialized = false

  var dbEverConnected = false

  var redis: RedisClient
  var db: DbConn

  var numProcessed = 0

  let (date, dateStr) = if cliArgs.date.isSome:
    let date = cliArgs.date.get
    let dateStr = date.format("yyyy-MM-dd")
    setIsSimulation(true)
    info "Running for historical date", date=dateStr
    (date, dateStr)
  else:
    let date = getNowUtc().toDateTime()
    let dateStr = date.format("yyyy-MM-dd")
    info "Running for live date", date=dateStr
    (date, dateStr)

  let mdSymbols = if cliArgs.symbols.len > 0:
    let symbols = cliArgs.symbols
    info "Running for manual override symbols", symbols
    symbols
  else:
    info "Starting market data db ..."
    db = getMdDb(loadOrQuit("MD_PG_HOST"), loadOrQuit("MD_PG_USER"), loadOrQuit("MD_PG_PASS"), loadOrQuit("MD_PG_NAME"))
    dbInitialized = true
    info "Market data db connected"
    dbEverConnected = true

    let mdFeed = db.getConfiguredMdFeed(dateStr)
    let mdSymbols = db.getConfiguredMdSymbols(dateStr, mdFeed)
    if mdSymbols.len == 0:
      error "No market data symbols requested; terminating", feed=mdFeed, symbols=mdSymbols
      quit 204
    info "Running for db configured symbols", symbols=mdSymbols
    mdSymbols

  info "Running ..."
  
  try:
    if isSimuluation():
      info "Starting SIMULATED runner ..."
      let symbol = if cliArgs.symbols.len > 0:
        cliArgs.symbols[0]
      else:
        "FAKEPACA"
      var sim = initSimulator(date, symbol)
      sim.simulate()
      info "Simulated runner done"
    else:
      info "Starting LIVE runner ..."

      info "Starting redis ..."
      redis = newRedisClient(loadOrQuit("MD_REDIS_HOST"), pass=some loadOrQuit("MD_REDIS_PASS"))
      redisInitialized = true
      info "Redis connected"

      var runnerThreads = newSeq[Thread[RunnerThreadArgs]](mdSymbols.len)
      for idx, symbol in enumerate(mdSymbols):
        createThread(runnerThreads[idx], runner, RunnerThreadArgs(symbol: symbol))
      createTimerThread()
      createMarketOutputThread(mdSymbols)

      var lastIds = initTable[string, string]()
      var streamEventsProcessed = initTable[string, int64]()
      var streamEventsExpected = initTable[string, int64]()
      for symbol in mdSymbols:
        for streamName in [makeMdStreamName(dateStr, symbol), makeOuStreamName(dateStr, symbol)]:
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
        if cliArgs.date.isNone and getNowUtc().toDateTime().getDateStr() != dateStr:
          break

        if isSimuluation():
          var keepRunning = false
          for symbol in mdSymbols:
            let streamName = makeMdStreamName(dateStr, symbol)
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

          let replyParseAttempt = replyRaw[].parseMergedStreamResponse
          if replyParseAttempt.isOk:
            let reply = replyParseAttempt[]
            lastIds[reply.stream] = reply.id
            inc streamEventsProcessed[reply.stream]

            # Do the actual processing
            let symbol = if reply.symbol.isSome:
              reply.symbol.get
            else:
              error "Merged stream got symbol-less message", reply
              continue

            # Note: future optimization: can store these lookups somewhere
            # currently this function takes a look but that's not necessary
            let (ic, _) = getChannelsForSymbol(symbol)

            let inputEvent = case reply.kind
            of MarketData:
              let internalMd = reply.md.mdReply.parseMarketDataUpdate
              if internalMd.isErr:
                # Note: May want to log the error here, but we're likely to get a lot of messages that
                # we can't convert just because the mapping isn't done and they're not relevant
                # Bad practice to silently "fail" though
                continue

              InputEvent(
                kind: MarketData,
                md: internalMd[],
              )
            of OrderUpdate:
              let internalOu = reply.ou.ouReply.parseSysOrderUpdateEvent
              if internalOu.isErr:
                # Note: May want to log the error here, but we're likely to get a lot of messages that
                # we can't convert just because the mapping isn't done and they're not relevant
                # Bad practice to silently "fail" though
                continue

              InputEvent(
                kind: OrderUpdate,
                ou: internalOu[],
              )

            trace "Sending input event", inputEvent
            ic.send(inputEvent)
            
            inc numProcessed
            if numProcessed mod kEventsProcessedHeartbeat == 0:
              info "Total events processed", numProcessed
        else:
          warn "Error receiving", err=replyRaw.error.msg

  except DbError:
    error "Failed to connect to db to start simulation", msg=getCurrentExceptionMsg()
  except Exception:
    error "Simulator raised generic exception", msg=getCurrentExceptionMsg(), trace=getCurrentException().getStackTrace()


when isMainModule:
  main()
