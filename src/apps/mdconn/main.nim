## This is the market data connector
## It subscribes to Alpaca's market data api, and passes the messages to a redis stream

import std/asyncdispatch
import std/options
import std/times

import chronicles except toJson
import jsony
import nim_redis
import ws

import apps/mdconn/ws_conn
import config/connections
import config/market_data


proc loadOrQuit(env: string): string =
  let opt = getOptEnv(env)
  if opt.isNone:
    error "Failed to load required env var, terminating", env
    quit 1
  opt.get


proc main() {.async.} =
  let redisHost = loadOrQuit("MD_REDIS_HOST")

  let mdFeed = getConfiguredMdFeed()
  let mdSymbols = getConfiguedMdSymbols()

  let client = newRedisClient(redisHost, pass=getOptEnv("MD_REDIS_PASS"))
  var ws = await initWebsocket(mdFeed)

  await ws.subscribeFakeData(mdSymbols)

  while true:
    let replies = await ws.receiveMdWsReply()
    let today = now().getDateStr()

    for reply in replies:
      let symbol = block:
        let symbol = reply.getSymbol()
        if symbol.isNone:
          continue
        symbol.get
      
      let streamName = "md:" & today & ":" & symbol
      let writeResult = client.cmd(@["XADD", streamName, "*", "data", reply.toJson()])
      if not writeResult.isOk:
        error "Write not ok", msg=writeResult.error.msg
  ws.close()

waitFor main()
