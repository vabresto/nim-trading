## This is a market data recorder
## It subscribes to a redis stream, and forwards the data into a db

import std/enumerate
import std/json
import std/net
import std/options
import std/os
import std/tables
import std/times

import chronicles except toJson
import db_connector/db_postgres
import jsony
import nim_redis

import ny/core/db/mddb
import ny/core/env/envs
# import ny/core/md/alpaca/types
import ny/core/md/alpaca/ou_types
import ny/core/md/utils
import ny/core/utils/sim_utils
import ny/core/utils/time_utils
import ny/core/types/timestamp

logScope:
  topics = "ny-ou-rec"


type
  StreamResponse = object
    stream: string
    id: string
    rawContents: RedisValue
    rawJson: JsonNode
    ouReply: AlpacaOuWsReply
    receiveTimestamp: Timestamp



const kEventsProcessedHeartbeat = 5


proc parseStreamResponse(val: RedisValue): ?!StreamResponse {.raises: [].} =
  var resp = StreamResponse()
  try:
    case val.kind
    of Array:
      var dataIdx = 0
      var timestampIdx = 0

      let inner = val.arr[0].arr[1].arr[0].arr[1]
      for curIdx, item in enumerate(inner.arr):
        case item.kind
        of SimpleString, BulkString:
          if item.str == "data":
            dataIdx = curIdx + 1
            resp.ouReply = inner.arr[curIdx + 1].str.fromJson(AlpacaOuWsReply)
            resp.rawJson = inner.arr[curIdx + 1].str.parseJson()
          if item.str == "receive_timestamp":
            timestampIdx = curIdx + 1
            resp.receiveTimestamp = inner.arr[curIdx + 1].str.parseTimestamp
        else:
          discard

      resp.stream = val.arr[0].arr[0].str
      resp.id = val.arr[0].arr[1].arr[0].arr[0].str
      resp.rawContents = val.arr[0].arr[1].arr[0].arr[1]
      return success resp
    of Null, Error, SimpleString, BulkString, Integer:
      return failure "Unable to parse non-array stream value: " & $val
  except OSError, IOError:
    return failure "Error parsing raw json: " & $val
  except ValueError:
    return failure "Error parsing as a stream response: " & $val


proc main() =
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

      let today = getNowUtc().toDateTime().getDateStr()
      let mdFeed = db.getConfiguredMdFeed(today)
      let mdSymbols = db.getConfiguredMdSymbols(today, mdFeed)
      if mdSymbols.len == 0:
        error "No market data symbols requested; terminating", feed=mdFeed, symbols=mdSymbols
        quit 1

      var lastIds = initTable[string, string]()
      for symbol in mdSymbols:
        lastIds[makeOuStreamName(today, symbol)] = getInitialStreamId()

      info "Running main loop ..."
      while true:
        # We key by date; more efficient would be to only update this overnight, but whatever
        # This means we can just leave it running for multiple days in a row
        if getNowUtc().toDateTime().getDateStr() != today:
          break

        redis.send(makeReadMdStreamsCommand(lastIds, simulation=isSimuluation()))

        let replyRaw = redis.receive()
        if replyRaw.isOk:
          if replyRaw[].kind == Error:
            error "Got error reply from stream", err=replyRaw[].err
            continue

          let replyParseAttempt = replyRaw[].parseStreamResponse
          if replyParseAttempt.isOk:
            let reply = replyParseAttempt[]
            lastIds[reply.stream] = reply.id

            if reply.rawContents.arr.len >= 2 and reply.rawContents.arr[0].str == "data":
              let recordTs = getNowUtc()
              info "Got order update", ou=reply, recordTs
              db.insertRawOuEvent(reply.id, today, reply.ouReply, reply.rawJson, reply.receiveTimestamp, recordTs)
              inc numProcessed

              if numProcessed mod kEventsProcessedHeartbeat == 0:
                info "Total events processed", numProcessed
          else:
            warn "Reply parse failed", err=replyParseAttempt.error.msg
        else:
          warn "Error receiving", err=replyRaw.error.msg #, cmd=makeReadMdStreamsCommand(lastIds, simulation=isSimuluation())

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
