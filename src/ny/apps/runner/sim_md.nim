import std/options
import std/times

import db_connector/db_postgres
import jsony

import ny/apps/md_ws/parsing
import ny/core/md/alpaca/types


proc createMarketDataIterator*(db: DbConn, symbol: string, date: DateTime): auto =
  (iterator(): Option[AlpacaMdWsReply] =
    for row in db.fastRows(sql("""
    SELECT
      id, raw_data
    FROM ny.raw_market_data
    WHERE true
    AND date = ?
    AND symbol = ?
    ORDER BY id
    """), date.format("YYYY'-'MM'-'dd"), symbol):
      yield some row[1].fromJson(AlpacaMdWsReply)
    return none[AlpacaMdWsReply]()
  )
