## This is the market data connector
## It subscribes to Alpaca's market data api, and passes the messages to a redis stream

import std/asyncdispatch
import std/options
import std/times

import jsony
import nim_redis
import ws

import apps/mdconn/ws_conn


proc main() {.async.} =
  let client = newRedisClient("localhost", pass=some "foobarabc123")
  var ws = await initWebsocket("test")

  await ws.subscribeFakeData(@["FAKEPACA"])

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
        echo "Write not ok, err: ", writeResult.error.msg
  ws.close()

waitFor main()
