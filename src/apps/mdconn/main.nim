## This is the market data connector
## It subscribes to Alpaca's market data api, and passes the messages to a redis stream

import std/asyncdispatch
import std/net
import std/options
import std/selectors
import std/times

import chronicles except toJson
import jsony
import nim_redis
import ws

import apps/mdconn/ws_conn
import config/connections
import config/market_data


const kEventsProcessedHeartbeat = 5


proc loadOrQuit(env: string): string =
  let opt = getOptEnv(env)
  if opt.isNone:
    error "Failed to load required env var, terminating", env
    quit 1
  opt.get


proc main() {.raises: [].} =
  let redisHost = loadOrQuit("MD_REDIS_HOST")

  let mdFeed = getConfiguredMdFeed()
  let mdSymbols = getConfiguedMdSymbols()

  var redis: RedisClient
  var ws: WebSocket

  var numProcessed = 0

  while true:
    try:
      info "Starting connections ..."
      redis = newRedisClient(redisHost, pass=getOptEnv("MD_REDIS_PASS"))
      ws = waitFor initWebsocket(mdFeed)

      info "Connected; subscribing to data"

      waitFor ws.subscribeData(mdSymbols)

      info "Running main loop ..."

      while true:
        let replies = waitFor ws.receiveMdWsReply()
        let today = now().getDateStr()

        for reply in replies:
          let symbol = block:
            let symbol = reply.getSymbol()
            if symbol.isNone:
              continue
            symbol.get
          
          let streamName = "md:" & today & ":" & symbol
          let writeResult = redis.cmd(@["XADD", streamName, "*", "data", reply.toJson()])
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
      try:
        ws.close()
      except Exception:
        error "Exception occurred while closing websocket!", msg=getCurrentExceptionMsg()

      # Close redis
      try:
        redis.close()
      except SslError, LibraryError:
        error "Exception occurred while closing redis!", msg=getCurrentExceptionMsg()
      except Exception:
        error "Generic exception occurred while closing redis!", msg=getCurrentExceptionMsg()


when isMainModule:
  main()
