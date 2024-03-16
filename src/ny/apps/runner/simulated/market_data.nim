import std/options
import std/times

import db_connector/db_postgres
import jsony

import ny/apps/md_ws/parsing
import ny/core/md/alpaca/parsing
import ny/core/md/alpaca/types
import ny/core/md/md_types
import ny/core/types/price
import ny/core/types/timestamp
import ny/core/types/md/bar_details


proc createMarketDataIterator*(db: DbConn, symbol: string, date: DateTime): auto =
  (iterator(): Option[MarketDataUpdate] =
    for row in db.fastRows(sql("""
    SELECT
      id, raw_data
    FROM ny.raw_market_data
    WHERE true
    AND date = ?
    AND symbol = ?
    ORDER BY id
    """), date.format("YYYY'-'MM'-'dd"), symbol):
      let alpacaMd = row[1].fromJson(AlpacaMdWsReply)

      case alpacaMd.kind
      of Quote:
        yield some MarketDataUpdate(
          timestamp: alpacaMd.quote.timestamp.parseTimestamp,
          kind: Quote,
          askPrice: alpacaMd.quote.askPrice.parsePrice,
          askSize: alpacaMd.quote.askSize,
          bidPrice: alpacaMd.quote.bidPrice.parsePrice,
          bidSize: alpacaMd.quote.bidSize,
        )
      of BarMinute:
        yield some MarketDataUpdate(
          timestamp: alpacaMd.bar.timestamp.parseTimestamp,
          kind: BarMinute,
          bar: BarDetails(
            openPrice: alpacaMd.bar.openPrice.parsePrice,
            highPrice: alpacaMd.bar.highPrice.parsePrice,
            lowPrice: alpacaMd.bar.lowPrice.parsePrice,
            closePrice: alpacaMd.bar.closePrice.parsePrice,
            volume: alpacaMd.bar.volume,
            timestamp: alpacaMd.bar.timestamp.parseTimestamp,
          ),
        )
      of TradingStatus:
        yield some MarketDataUpdate(
          timestamp: alpacaMd.tradingStatus.timestamp.parseTimestamp,
          kind: Status,
          status: alpacaMd.tradingStatus.statusCode.parseAlpacaMdTradingStatus,
        )
      else:
        continue

    return none[MarketDataUpdate]()
  )
