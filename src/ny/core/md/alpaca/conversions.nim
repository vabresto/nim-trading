import std/json
import std/strutils

import questionable/results as qr
import results

import ny/core/md/alpaca/types
import ny/core/md/md_types
import ny/core/types/timestamp
import ny/core/types/price
import ny/core/types/md/bar_details
import ny/core/md/alpaca/ou_types
import ny/core/types/strategy_base
import ny/core/types/order
import ny/core/types/side
import ny/core/types/tif

proc parseMarketDataUpdate*(alpaca: AlpacaMdWsReply): ?!MarketDataUpdate =
  case alpaca.kind
  of Quote:
    return success MarketDataUpdate(
      timestamp: alpaca.quote.timestamp.parseTimestamp,
      kind: Quote,
      askPrice: alpaca.quote.askPrice.parsePrice,
      askSize: alpaca.quote.askSize,
      bidPrice: alpaca.quote.bidPrice.parsePrice,
      bidSize: alpaca.quote.bidSize,
    )
  of BarMinute:
    return success MarketDataUpdate(
      timestamp: alpaca.bar.timestamp.parseTimestamp,
      kind: BarMinute,
      bar: BarDetails(
        openPrice: alpaca.bar.openPrice.parsePrice,
        highPrice: alpaca.bar.highPrice.parsePrice,
        lowPrice: alpaca.bar.lowPrice.parsePrice,
        closePrice: alpaca.bar.closePrice.parsePrice,
        volume: alpaca.bar.volume,
        timestamp: alpaca.bar.timestamp.parseTimestamp,
      ),
    )
  of TradingStatus:
    return success MarketDataUpdate(
      timestamp: alpaca.tradingStatus.timestamp.parseTimestamp,
      kind: Status,
      status: alpaca.tradingStatus.statusCode.parseMarketDataStatusUpdateKind,
    )
  else:
    return failure "Unable to convert alpaca message: " & $alpaca

proc parseSysOrderUpdateEvent*(alpaca: AlpacaOuWsReply): ?!SysOrderUpdateEvent =
  # https://docs.alpaca.markets/docs/websocket-streaming#common-events
  try:
    case alpaca.data.event
    of "new", "pending_new":
      var res = SysOrderUpdateEvent(
        kind: (if alpaca.data.event == "new": SysOrderUpdateKind.New else: SysOrderUpdateKind.Ack),
      )
      res.orderId = alpaca.data.order.id.OrderId
      res.clientOrderId = alpaca.data.order.clientOrderId.ClientOrderId
      res.timestamp = alpaca.raw["data"]["timestamp"].getStr.parseTimestamp
      res.side = ?alpaca.data.order.side.parseSide
      res.size = alpaca.data.order.size.parseInt
      res.tif = ?alpaca.data.order.tif.parseTif
      res.price = alpaca.data.order.limitPrice.parsePrice
      return success res
    of "fill", "partial_fill":
      var res = SysOrderUpdateEvent(
        kind: (if alpaca.data.event == "fill": SysOrderUpdateKind.FilledFull else: SysOrderUpdateKind.FilledPartial),
      )
      res.orderId = alpaca.data.order.id.OrderId
      res.clientOrderId = alpaca.data.order.clientOrderId.ClientOrderId
      res.timestamp = alpaca.raw["data"]["timestamp"].getStr.parseTimestamp

      res.fillAmt = alpaca.raw["data"]["qty"].getStr.parseInt
      res.fillPrice = alpaca.raw["data"]["price"].getStr.parsePrice

      return success res
    of "canceled", "pending_cancel", "done_for_day":
      var res = SysOrderUpdateEvent(
        kind: (if alpaca.data.event == "pending_cancel": SysOrderUpdateKind.CancelPending else: SysOrderUpdateKind.Cancelled),
      )
      res.orderId = alpaca.data.order.id.OrderId
      res.clientOrderId = alpaca.data.order.clientOrderId.ClientOrderId
      res.timestamp = alpaca.raw["data"]["timestamp"].getStr.parseTimestamp

      return success res
    of "expired", "replaced", "rejected", "stopped", "pending_replace", "calculated", "suspended",
       "order_replace_rejected", "order_cancel_rejected":
      return failure "Got order update message type with no conversion: " & $alpaca
  except ValueError:
    return failure "Error parsing known order typed data: " & $alpaca
