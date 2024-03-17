import std/json
import std/net
import std/options
import std/os
import std/strutils

import chronicles except toJson
import db_connector/db_postgres
import jsony

import ny/core/md/alpaca/types
import ny/core/md/alpaca/ou_types
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


proc insertRawOuEvent*(db: DbConn, id: string, date: string, ou: AlpacaOuWsReply, rawJson: JsonNode, receiveTimestamp: Timestamp, recordingTimestamp: Timestamp) =
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

    rawJson,
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

