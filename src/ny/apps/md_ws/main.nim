## This is the market data connector
## It subscribes to Alpaca's market data api, and passes the messages to a redis stream

import std/asyncdispatch
import std/enumerate
import std/net
import std/options
import std/os
import std/selectors
import std/times

import chronicles except toJson
import db_connector/db_postgres
import nim_redis
import ws

import ny/apps/md_ws/md_ws_conn
import ny/core/db/mddb
import ny/core/env/envs
import ny/core/md/utils
import ny/core/types/timestamp
import ny/core/utils/rec_parseopt

import ny/core/services/postgres
import ny/core/services/redis
import ny/core/services/cli_args


logScope:
  topics = "ny-md-ws"


const kEventsProcessedHeartbeat = 5_000


proc main() {.raises: [].} =
  let cliArgs = parseCliArgs()

  var ws: WebSocket
  var wsInitialized = false

  var numProcessed = 0

  while true:
    try:
      info "Starting connections ..."
      withDb(db):
        withRedis(redis):
          withCliArgs(cliArgs, db, today, mdSymbols, mdFeed):

            info "Starting market data websocket ..."
            ws = waitFor initWebsocket(mdFeed, loadOrQuit("ALPACA_API_KEY"), loadOrQuit("ALPACA_API_SECRET"), mdSymbols)
            wsInitialized = true

            info "Running main loop ..."
            while true:
              # If we're on to the next day, reload the program to get the new config
              if getNowUtc().toDateTime().getDateStr() != today:
                break

              let replyBlock = waitFor ws.skimMdWsReply()
              for idx, reply in enumerate(replyBlock.rawMd):
                let streamName = makeMdStreamName(today, reply.symbol)
                let writeResult = redis.cmd(@[
                  "XADD", streamName, "*",
                  "md_raw_data", $(replyBlock.rawMd[idx]),
                  "md_receive_timestamp", $replyBlock.receiveTs,
                ])

                if not writeResult.isOk:
                  error "Write not ok", msg=writeResult.error.msg
                else:
                  inc numProcessed

                if numProcessed mod kEventsProcessedHeartbeat == 0:
                  info "Total events processed", numProcessed

    # Log any uncaught errors
    except WebSocketClosedError:
      error "Websocket closed exception", msg=getCurrentExceptionMsg()
    except WebSocketError:
      error "Websocket generic exception", msg=getCurrentExceptionMsg()
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
        finally:
          wsInitialized = false

      sleep(1_000)


when isMainModule:
  main()
