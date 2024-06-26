## # Overview
## 
## The [order update recorder (ny-ou-rec)](src/ny/apps/ou_rec/main.nim) is similar to the [market data recorder](#md-rec)
## except it records order updates instead of market data.

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
import ny/core/streams/ou_streams

import ny/core/services/postgres
import ny/core/services/redis
import ny/core/services/streams

logScope:
  topics = "ny-ou-rec"


const kEventsProcessedHeartbeat: int = 100


proc main() {.raises: [].} =
  let cliArgs = parseCliArgs()

  var numProcessed = 0

  while true:
    try:
      info "Starting connections ..."
      withDb(db):
        withRedis(redis):
          processStreams(cliArgs, db, redis, makeOuStreamName, today, lastIds, streamEventsProcessed):
            let replyRaw = redis.receive()
            if replyRaw.isOk:
              if replyRaw[].kind == Error:
                error "Got error reply from stream", err=replyRaw[].err
                continue

              let replyParseAttempt = replyRaw[].parseOuStreamResponse
              if replyParseAttempt.isOk:
                let reply = replyParseAttempt[]

                trace "Got reply", reply

                lastIds[reply.stream] = reply.id
                inc streamEventsProcessed[reply.stream]

                let recordTs = getNowUtc()
                info "Got order update", ou=reply, recordTs
                db.insertRawOuEvent(reply.id, today, reply.ouReply, reply.receiveTimestamp, recordTs)
                inc numProcessed

                if numProcessed mod kEventsProcessedHeartbeat == 0:
                  info "Total events processed", numProcessed
              else:
                warn "Reply parse failed", err=replyParseAttempt.error.msg
            else:
              warn "Error receiving", err=replyRaw.error.msg

    except OSError:
      error "OSError", msg=getCurrentExceptionMsg()

    except Exception:
      error "Generic uncaught exception", msg=getCurrentExceptionMsg()

    sleep(1_000)


when isMainModule:
  main()
