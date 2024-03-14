## This is the market data connector
## It subscribes to Alpaca's market data api, and passes the messages to a redis stream

import std/asyncdispatch
import std/net
import std/options
import std/os
import std/selectors
import std/times

import chronicles except toJson
import db_connector/db_postgres
import jsony
import nim_redis
import ws

import ny/apps/md_ws/md_ws_conn
import ny/core/db/mddb
import ny/core/env/envs
import ny/core/md/utils
import ny/core/utils/time_utils


logScope:
  topics = "ny-md-ws"


const kEventsProcessedHeartbeat = 5_000


proc main() {.raises: [].} =
  var redisInitialized = false
  var dbInitialized = false
  var wsInitialized = false

  var dbEverConnected = false

  var redis: RedisClient
  var db: DbConn
  var ws: WebSocket

  var numProcessed = 0

  while true:
    try:
      info "Starting connections ..."
      info "Starting market data db ..."
      db = getMdDb(loadOrQuit("MD_PG_HOST"), loadOrQuit("MD_PG_USER"), loadOrQuit("MD_PG_PASS"), loadOrQuit("MD_PG_NAME"))
      dbInitialized = true
      dbEverConnected = true
      info "Market data db connected"

      let today = getNowUtc().getDateStr()
      let mdFeed = db.getConfiguredMdFeed(today)
      let mdSymbols = db.getConfiguredMdSymbols(today, mdFeed)
      if mdSymbols.len == 0:
        error "No market data symbols requested; terminating", feed=mdFeed, symbols=mdSymbols
        quit 1

      info "Starting redis ..."
      redis = newRedisClient(loadOrQuit("MD_REDIS_HOST"), pass=some loadOrQuit("MD_REDIS_PASS"))
      redisInitialized = true
      info "Redis connected"

      info "Starting market data websocket ..."
      ws = waitFor initWebsocket(mdFeed, loadOrQuit("ALPACA_API_KEY"), loadOrQuit("ALPACA_API_SECRET"))
      wsInitialized = true
      info "Market data websocket connected"

      info "Connected; subscribing to data"

      waitFor ws.subscribeData(mdSymbols)

      info "Running main loop ..."
      while true:
        # If we're on to the next day, reload the program to get the new config
        if getNowUtc().getDateStr() != today:
          break

        let (replies, receiveTs) = waitFor ws.receiveMdWsReply()

        for reply in replies:
          let symbol = block:
            let symbol = reply.getSymbol()
            if symbol.isNone:
              continue
            symbol.get
          
          let streamName = makeMdStreamName(today, symbol)
          let writeResult = redis.cmd(@["XADD", streamName, "*", "data", reply.toJson(), "receive_timestamp", receiveTs.dbFmt()])
          if not writeResult.isOk:
            error "Write not ok", msg=writeResult.error.msg
          else:
            inc numProcessed

          if numProcessed mod kEventsProcessedHeartbeat == 0:
            info "Total events processed", numProcessed

    # Log any uncaught errors
    except OSError, ValueError, IOSelectorsException:
      error "Unhandled exception", msg=getCurrentExceptionMsg()
    except DbError:
      if not dbEverConnected:
        warn "DbError", msg=getCurrentExceptionMsg()  
      else:
        error "DbError", msg=getCurrentExceptionMsg()
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

      # Close db
      if dbInitialized:
        try:
          db.close()
        finally:
          dbInitialized = false

      sleep(1_000)


when isMainModule:
  main()
