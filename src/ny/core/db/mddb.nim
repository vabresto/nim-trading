import std/net
import std/options
import std/os
import std/strutils

import chronicles except toJson
import db_connector/db_postgres
import jsony

import ny/core/md/alpaca/types


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


proc insertRawMdEvent*(db: DbConn, id: string, date: string, event: AlpacaMdWsReply) =
  let timestamp = block:
    if event.getTimestamp.isNone:
      return
    else:
      event.getTimestamp.get

  let symbol = block:
    if event.getSymbol.isNone:
      return
    else:
      event.getSymbol.get

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
