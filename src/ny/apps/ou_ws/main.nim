## # Overview
## 
## The [order update websocket (ny-ou-ws)](src/ny/apps/ou_ws/main.nim) is similar to the [market data ws](#md-ws) except
## it connects to the Alpaca order updates websocket instead of the market data websocket. There are more meaningful
## differences here as the order update websocket returns binary frames and has a slightly different protocol response
## structure.

import std/asyncdispatch
import std/json
import std/net
import std/options
import std/os
import std/selectors
import std/times

import chronicles except toJson
import nim_redis
import ws

import ny/apps/ou_ws/ou_ws_conn
import ny/core/env/envs
import ny/core/md/utils
import ny/core/types/timestamp
import ny/core/md/alpaca/ou_types
import ny/core/utils/rec_parseopt

import ny/core/services/redis


logScope:
  topics = "ny-ou-ws"


const kEventsProcessedHeartbeat = 100


proc main() {.raises: [].} =
  discard parseCliArgs()

  var ws: WebSocket
  var wsInitialized = false

  var numProcessed = 0

  while true:
    try:
      info "Starting connections ..."
      withRedis(redis):
        let today = getNowUtc().toDateTime().getDateStr()

        info "Starting trade updates websocket ..."
        ws = waitFor initWebsocket("wss://paper-api.alpaca.markets/stream", loadOrQuit("ALPACA_API_KEY"), loadOrQuit("ALPACA_API_SECRET"))
        wsInitialized = true
        info "Trade updates websocket connected"

        info "Running main loop ..."
        while true:
          # If we're on to the next day, reload the program to get the new config
          if getNowUtc().toDateTime().getDateStr() != today:
            break

          let reply = waitFor ws.receiveTradeUpdateReply(true)
          if reply.isSome:

            trace "Got reply", reply=reply.get

            let streamName = makeOuStreamName(today, reply.get.ou.symbol)
            info "Writing to stream", streamName
            let writeResult = redis.cmd(@[
              "XADD", streamName, "*",
              "ou_raw_data", $(reply.get.ou.raw),
              "ou_receive_timestamp", $reply.get.receiveTs,
            ])
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

      sleep(1_000)


when isMainModule:
  main()
