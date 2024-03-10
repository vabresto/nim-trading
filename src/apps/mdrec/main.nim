## This is a market data recorder
## It subscribes to a redis stream, and forwards the data into a db

import std/net
import std/options
import std/tables
import std/times

import chronicles except toJson
import db_connector/db_postgres
import jsony
import nim_redis

import config/connections
import config/market_data
import core/md/alpaca/types


type
  StreamResponse = object
    stream: string
    id: string
    contents: RedisValue


const kEventsProcessedHeartbeat = 5


proc getDb*(host: string, user: string, pass: string, db: string): DbConn =
  open(host, user, pass, db)


proc loadOrQuit(env: string): string =
  let opt = getOptEnv(env)
  if opt.isNone:
    error "Failed to load required env var, terminating", env
    quit 1
  opt.get


proc parseStreamResponse(val: RedisValue): ?!StreamResponse {.raises: [].} =
  var resp = StreamResponse()
  try:
    resp.stream = val.arr[0].arr[0].str
    resp.id = val.arr[0].arr[1].arr[0].arr[0].str
    resp.contents = val.arr[0].arr[1].arr[0].arr[1]
    return success resp
  except ValueError:
    return failure "Error parsing as a stream response: " & $val


func makeStreamName(date: string, symbol: string): string =
  "md:" & date & ":" & symbol


proc makeReadCommand(streams: Table[string, string]): seq[string] =
  result.add "XREAD"
  result.add "BLOCK"
  result.add "0"
  result.add "STREAMS"

  for (stream, id) in streams.pairs:
    result.add stream

  for (stream, id) in streams.pairs:
    result.add id


proc insertRawMdEvent*(db: DbConn, id: string, date: string, event: AlpacaMdWsReply) =
  let timestamp = block:
    if event.getTimestamp.isNone:
      return
    else:
      event.getTimestamp.get.string

  let symbol = block:
    if event.getSymbol.isNone:
      return
    else:
      event.getSymbol.get.string

  db.exec(sql"""
  INSERT INTO ny.raw_market_data
    (id, date, timestamp, symbol, type, data)
  VALUES
    (?, ?, ?, ?, ?, ?);
  """,
    id,
    date,
    timestamp,
    symbol,
    event.kind,
    event.toJson()
  )


proc main() =
  let redisHost = loadOrQuit("MD_REDIS_HOST")
  let redis = newRedisClient(redisHost, pass=getOptEnv("MD_REDIS_PASS"))

  var currentDate = ""
  var lastIds = initTable[string, string]()
  let mdSymbols = getConfiguedMdSymbols()

  let db = open(loadOrQuit("MD_PG_HOST"), loadOrQuit("MD_PG_USER"), loadOrQuit("MD_PG_PASS"), loadOrQuit("MD_PG_NAME"))

  var numProcessed = 0

  while true:
    # We key by date; more efficient would be to only update this overnight, but whatever
    # This means we can just leave it running for multiple days in a row
    let today = now().getDateStr()
    if currentDate != today:
      currentDate = today
      for symbol in mdSymbols:
        lastIds[makeStreamName(today, symbol)] = "$"
    redis.send(makeReadCommand(lastIds))

    let replyRaw = redis.receive()
    if replyRaw.isOk:
      let replyParseAttempt = replyRaw[].parseStreamResponse
      if replyParseAttempt.isOk:
        let reply = replyParseAttempt[]
        lastIds[reply.stream] = reply.id

        if reply.contents.arr.len >= 2 and reply.contents.arr[0].str == "data":
          let msg = reply.contents.arr[1].str.fromJson(AlpacaMdWsReply)
          db.insertRawMdEvent(reply.id, today, msg)
          inc numProcessed

          if numProcessed mod kEventsProcessedHeartbeat == 0:
            info "Total events processed", numProcessed


when isMainModule:
  main()
