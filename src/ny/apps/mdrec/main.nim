## This is a market data recorder
## It subscribes to a redis stream, and forwards the data into a db

import std/net
import std/os
import std/tables
import std/times

import chronicles except toJson
import db_connector/db_postgres
import jsony
import nim_redis

import ny/core/db/mddb
import ny/core/env/envs
import ny/core/md/alpaca/types
import ny/core/md/utils


type
  StreamResponse = object
    stream: string
    id: string
    contents: RedisValue


const kEventsProcessedHeartbeat = 5


proc parseStreamResponse(val: RedisValue): ?!StreamResponse {.raises: [].} =
  var resp = StreamResponse()
  try:
    resp.stream = val.arr[0].arr[0].str
    resp.id = val.arr[0].arr[1].arr[0].arr[0].str
    resp.contents = val.arr[0].arr[1].arr[0].arr[1]
    return success resp
  except ValueError:
    return failure "Error parsing as a stream response: " & $val


proc main() =
  var redisInitialized = false
  var dbInitialized = false

  var redis: RedisClient
  var db: DbConn

  var numProcessed = 0

  while true:
    try:
      let redisHost = loadOrQuit("MD_REDIS_HOST")
      redis = newRedisClient(redisHost, pass=getOptEnv("MD_REDIS_PASS"))
      redisInitialized = true

      var lastIds = initTable[string, string]()
      var currentDate = ""

      db = getMdDb(loadOrQuit("MD_PG_HOST"), loadOrQuit("MD_PG_USER"), loadOrQuit("MD_PG_PASS"), loadOrQuit("MD_PG_NAME"))
      dbInitialized = true

      let today = now().getDateStr()
      let mdFeed = db.getConfiguredMdFeed(today)
      let mdSymbols = db.getConfiguredMdSymbols(today, mdFeed)
      for symbol in mdSymbols:
        lastIds[makeStreamName(today, symbol)] = "$"

      while true:
        # We key by date; more efficient would be to only update this overnight, but whatever
        # This means we can just leave it running for multiple days in a row
        if now().getDateStr() != today:
          break
          
        redis.send(makeReadMdStreamsCommand(lastIds))

        let replyRaw = redis.receive()
        if replyRaw.isOk:
          let replyParseAttempt = replyRaw[].parseStreamResponse
          if replyParseAttempt.isOk:
            let reply = replyParseAttempt[]
            lastIds[reply.stream] = reply.id

            if reply.contents.arr.len >= 2 and reply.contents.arr[0].str == "data":
              let msg = reply.contents.arr[1].str.fromJson(AlpacaMdWsReply)
              db.insertRawMdEvent(reply.id, today, msg)
              inc numProcessed

              if numProcessed mod kEventsProcessedHeartbeat == 0:
                info "Total events processed", numProcessed

    except OSError:
      error "OSError", msg=getCurrentExceptionMsg()

    except DbError:
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
