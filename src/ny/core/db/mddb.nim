import std/json
import std/net
import std/options
import std/os
import std/strutils
import std/times

import chronicles except toJson
import db_connector/db_postgres
import jsony

import ny/core/md/alpaca/types
import ny/core/md/alpaca/ou_types
import ny/core/types/price
import ny/core/types/timestamp


proc getMdDb*(host: string, user: string, pass: string, db: string): DbConn =
  let db = open(host, user, pass, db)

  const sqlCreateCommands = readFile(currentSourcePath().parentDir() & "/create.sql")
  for cmd in sqlCreateCommands.split(";"):
    if cmd.strip != "":
      db.exec(sql(cmd.strip))

  db


proc getConfiguredMdFeed*(db: DbConn, date: string): string =
  for row in db.rows(sql("""
      SELECT
        DISTINCT feed
      FROM ny.md_subscriptions
      WHERE date = ?;
      """), date):
    return row[0]
  error "No market data feed configured! Using fallback dummy data feed: 'test'", date
  return "test"


proc getConfiguredMdSymbols*(db: DbConn, date: string, feed: string): seq[string] =
  for row in db.rows(sql("""
        SELECT
          symbol
        FROM ny.md_subscriptions
        WHERE date = ?
        AND feed = ?;
      """), date, feed):
    result.add row[0]

  info "Market data configuration", date, feed, symbols=result
  if result.len > 0:
    return result
  
  error "No market data symbols configured!", date, feed
  if feed == "test":
    # Undocumented feature: feed=test + symbol=FAKEPACA produces fake websocket market data
    result = @["FAKEPACA"]
    warn "Falling back to fake data configs!", date, feed, symbols=result
    return result
  return @[]


proc insertRawMdEvent*(db: DbConn, id: string, date: string, event: AlpacaMdWsReply, rawJson: JsonNode, receiveTimestamp: Timestamp, recordingTimestamp: Timestamp) =
  let timestamp = block:
    if event.getTimestamp.isNone:
      error "No timestamp", event
      return
    else:
      event.getTimestamp.get

  let symbol = block:
    if event.getSymbol.isNone:
      error "No symbol", event
      return
    else:
      event.getSymbol.get

  db.exec(sql"""
  INSERT INTO ny.raw_market_data
    (date, symbol, id, event_timestamp, receive_timestamp, recording_timestamp, type, raw_data)
  VALUES
    (?, ?, ?, ?, ?, ?, ?, ?)
  ON CONFLICT (date, symbol, id) DO NOTHING;
  """,
    date,
    symbol,
    id,

    timestamp,
    receiveTimestamp,
    recordingTimestamp,

    event.kind,
    rawJson,
  )

  db.exec(sql"""
  INSERT INTO ny.parsed_market_data
    (date, symbol, id, type, parsed_data)
  VALUES
    (?, ?, ?, ?, ?)
  ON CONFLICT (date, symbol, id) DO NOTHING;
  """,
    date,
    symbol,
    id,

    event.kind,
    event.toJson(),
  )


proc insertRawOuEvent*(db: DbConn, id: string, date: string, ou: AlpacaOuWsReply, receiveTimestamp: Timestamp, recordingTimestamp: Timestamp) =
  db.exec(sql"""
  INSERT INTO ny.raw_order_updates
    (
      date, symbol, id,
      order_id, client_order_id,
      event_timestamp, receive_timestamp, recording_timestamp,
      event_type, side, size, price,
      order_type, tif,
      raw_data
      )
  VALUES
    (
      ?, ?, ?,
      ?, ?,
      ?, ?, ?,
      ?, ?, ?, ?,
      ?, ?,
      ?
    )
  ON CONFLICT (date, symbol, id) DO NOTHING;
  """,
    date,
    ou.symbol,
    id,

    ou.data.order.id,
    ou.data.order.clientOrderId,
    
    ou.data.timestamp,
    receiveTimestamp,
    recordingTimestamp,

    ou.data.event,
    ou.data.order.side,
    ou.data.order.size,
    ou.data.order.limitPrice,

    ou.data.order.kind,
    ou.data.order.tif,

    ou.raw,
  )

  db.exec(sql"""
  INSERT INTO ny.parsed_order_updates
    (
      date, symbol, id,
      order_id, client_order_id,
      event_type, side, size, price,
      order_type, tif,
      parsed_data
      )
  VALUES
    (
      ?, ?, ?,
      ?, ?,
      ?, ?, ?, ?,
      ?, ?,
      ?
    )
  ON CONFLICT (date, symbol, id) DO NOTHING;
  """,
    date,
    ou.symbol,
    id,

    ou.data.order.id,
    ou.data.order.clientOrderId,

    ou.data.event,
    ou.data.order.side,
    ou.data.order.size,
    ou.data.order.limitPrice,

    ou.data.order.kind,
    ou.data.order.tif,

    ou.data.toJson(),
  )


type
  FillHistoryEvent* = object
    date*: string
    symbol*: string
    eventTimestamp*: Timestamp
    eventType*: string
    clientOrderId*: string
    side*: string
    eventFillQty*: int
    eventFillPrice*: Price
    orderTotalFillQty*: int
    positionQty*: int


proc getFillHistory*(db: DbConn, date: string, strategy: string, symbol: string): seq[FillHistoryEvent] =
  var fills = newSeq[FillHistoryEvent]()
  for row in db.rows(sql("""
      SELECT
        date,
        symbol,
        event_timestamp,
        event_type,
        client_order_id,
        side,
        raw_data -> 'data' ->> 'qty' as event_fill_qty,
        raw_data -> 'data' ->> 'price' as event_fill_price,
        raw_data -> 'data' -> 'order' ->> 'filled_qty' as order_total_fill_qty,
        raw_data -> 'data' ->> 'position_qty' as position_qty
      FROM ny.raw_order_updates
      WHERE date = ?
      AND symbol = ?
      AND event_type in ('partial_fill', 'fill')
      ORDER BY event_timestamp
      """), date, symbol):
    fills.add FillHistoryEvent(
      date: row[0],
      symbol: row[1],
      eventTimestamp: row[2].parseDbTimestamp,
      eventType: row[3],
      clientOrderId: row[4],
      side: row[5],
      eventFillQty: row[6].parseInt,
      eventFillPrice: row[7].parsePrice,
      orderTotalFillQty: row[8].parseInt,
      positionQty: row[9].parseInt,
    )
  return fills


type
  DailyLatencyStat* = object
    date*: string
    numEvents*: int64

    avgNetworkTime*: Duration
    avgInternalTime*: Duration
    avgTotalTime*: Duration

    p50NetworkTime*: Duration
    p75NetworkTime*: Duration
    p99NetworkTime*: Duration

    p50InternalTime*: Duration
    p75InternalTime*: Duration
    p99InternalTime*: Duration

    p50TotalTime*: Duration
    p75TotalTime*: Duration
    p99TotalTime*: Duration


proc getDailyLatencyStats*(db: DbConn): seq[DailyLatencyStat] =
  const nanosMultiplier = 1_000_000_000.float

  var stats = newSeq[DailyLatencyStat]()
  for row in db.rows(sql("""
      SELECT
        date,
        num_events,
        avg_network_time_sec,
        avg_internal_time_sec,
        avg_total_time_sec,
        p50_network_time_sec,
        p75_network_time_sec,
        p99_network_time_sec,
        p50_internal_time_sec,
        p75_internal_time_sec,
        p99_internal_time_sec,
        p50_total_time_sec,
        p75_total_time_sec,
        p99_total_time_sec
      FROM ny.latency_stats_daily
      ORDER BY date DESC
      """)):
    stats.add DailyLatencyStat(
      date: row[0],
      numEvents: row[1].parseBiggestInt,
      avgNetworkTime: initDuration(nanoseconds=(row[2].parseFloat * nanosMultiplier).int64),
      avgInternalTime: initDuration(nanoseconds=(row[3].parseFloat * nanosMultiplier).int64),
      avgTotalTime: initDuration(nanoseconds=(row[4].parseFloat * nanosMultiplier).int64),
      p50NetworkTime: initDuration(nanoseconds=(row[5].parseFloat * nanosMultiplier).int64),
      p75NetworkTime: initDuration(nanoseconds=(row[6].parseFloat * nanosMultiplier).int64),
      p99NetworkTime: initDuration(nanoseconds=(row[7].parseFloat * nanosMultiplier).int64),
      p50InternalTime: initDuration(nanoseconds=(row[8].parseFloat * nanosMultiplier).int64),
      p75InternalTime: initDuration(nanoseconds=(row[9].parseFloat * nanosMultiplier).int64),
      p99InternalTime: initDuration(nanoseconds=(row[10].parseFloat * nanosMultiplier).int64),
      p50TotalTime: initDuration(nanoseconds=(row[11].parseFloat * nanosMultiplier).int64),
      p75TotalTime: initDuration(nanoseconds=(row[12].parseFloat * nanosMultiplier).int64),
      p99TotalTime: initDuration(nanoseconds=(row[13].parseFloat * nanosMultiplier).int64),
    )
  stats
