import std/asyncdispatch
import std/net
import std/options
import std/os
import std/selectors
import std/times

import chronicles except toJson
# import db_connector/db_postgres
import jsony
import nim_redis
import ws

import ny/apps/ou_ws/ou_ws_conn
import ny/core/db/mddb
import ny/core/env/envs
import ny/core/md/utils
import ny/core/utils/sim_utils
import ny/core/utils/time_utils


logScope:
  topics = "ny-ou-ws"


const kEventsProcessedHeartbeat = 5


proc main() {.raises: [].} =
  var redisInitialized = false
  # var dbInitialized = false
  var wsInitialized = false

  var redis: RedisClient
  # var db: DbConn
  var ws: WebSocket

  var numProcessed = 0

  while true:
    try:
      info "Starting connections ..."
      # info "Starting market data db ..."
      # db = getMdDb(loadOrQuit("MD_PG_HOST"), loadOrQuit("MD_PG_USER"), loadOrQuit("MD_PG_PASS"), loadOrQuit("MD_PG_NAME"))
      # dbInitialized = true
      # info "Market data db connected"

      let today = getNowUtc().getDateStr()

      info "Starting redis ..."
      redis = newRedisClient(loadOrQuit("MD_REDIS_HOST"), pass=some loadOrQuit("MD_REDIS_PASS"))
      redisInitialized = true
      info "Redis connected"

      info "Starting trade updates websocket ..."
      ws = waitFor initWebsocket("wss://paper-api.alpaca.markets/stream", loadOrQuit("ALPACA_API_KEY"), loadOrQuit("ALPACA_API_SECRET"))
      wsInitialized = true
      info "Trade updates websocket connected"

      info "Running main loop ..."
      while true:
        # If we're on to the next day, reload the program to get the new config
        if getNowUtc().getDateStr() != today:
          break

        let reply = waitFor ws.receiveTradeUpdateReply(true)
        if reply.isSome:
          info "Got reply", reply=reply.get

          let symbol: string = block:
            if reply.get.ou.symbol != "":
              reply.get.ou.symbol
            else:
              warn "Failed to get symbol"
              continue
          
          let streamName = makeOuStreamName(today, symbol)
          info "Writing to stream", streamName
          let writeResult = redis.cmd(@["XADD", streamName, "*", "data", reply.get.ou.toJson(), "receive_timestamp", reply.get.receiveTs.dbFmt()])
          if not writeResult.isOk:
            error "Write not ok", msg=writeResult.error.msg
          else:
            inc numProcessed

          if numProcessed mod kEventsProcessedHeartbeat == 0:
            info "Total events processed", numProcessed

    # Log any uncaught errors
    except OSError, ValueError, IOSelectorsException:
      error "Unhandled exception", msg=getCurrentExceptionMsg()
    except Exception:
      error "Unhandled generic exception", msg=getCurrentExceptionMsg()

    # Release resources
    finally:
      # Close websocket
      if wsInitialized:
        try:
          ws.close()
        except Exception:
          error "Exception occurred while closing websocket!", msg=getCurrentExceptionMsg()
        except:
          wsInitialized = false

      # Close redis
      if redisInitialized:
        try:
          redis.close()
        except SslError, LibraryError:
          error "Exception occurred while closing redis!", msg=getCurrentExceptionMsg()
        except Exception:
          error "Generic exception occurred while closing redis!", msg=getCurrentExceptionMsg()
        finally:
          redisInitialized = false

      # # Close db
      # if dbInitialized:
      #   try:
      #     db.close()
      #   finally:
      #     dbInitialized = false

      sleep(1_000)


when isMainModule:
  main()
