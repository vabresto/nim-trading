## This is the market data connector
## It subscribes to Alpaca's market data api, and passes the messages to a redis stream

import std/asyncdispatch

import ws

import apps/mdconn/ws_conn


proc main() {.async.} =
  var ws = await initWebsocket()
  
  echo "In main loop"
  
  await ws.subscribeFakeData()

  echo "Sent subscribe"

  while true:
    echo await ws.receiveMdWsReply()
  ws.close()

waitFor main()
