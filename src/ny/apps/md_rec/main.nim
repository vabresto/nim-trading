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
import ny/core/heartbeat/server

import ny/core/services/postgres
import ny/core/services/redis
import ny/core/services/streams

logScope:
  topics = "ny-md-rec"

const kEventsProcessedHeartbeat = 5_000

proc main() {.raises: [].} =
  let cliArgs = parseCliArgs()
  if cliArgs.heartbeat:
    startHeartbeatServerThread()
  else:
    info "Heartbeat not enabled"

  var numProcessed = 0

  while true:
    try:
      info "Starting connections ..."
      withDb(db):
        withRedis(redis):
          processStreams(cliArgs, db, redis, makeMdStreamName, today, lastIds, streamEventsProcessed):
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

    except Exception:
      error "Generic uncaught exception", msg=getCurrentExceptionMsg()

    sleep(1_000)


when isMainModule:
  main()
