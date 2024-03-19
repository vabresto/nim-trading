import std/json

import jsony

import ny/core/md/alpaca/types
export types
import ny/core/md/md_types


proc parseAlpacaMdTradingStatus*(statusCode: string): MarketDataStatusUpdateKind =
  # https://docs.alpaca.markets/docs/real-time-stock-pricing-data#status-codes
  case statusCode
  of "2", "H":
    Halt
  of "3", "T":
    Resume
  else:
    Other


proc renameHook*(v: var AlpacaMdWsReply, fieldName: var string) =
  if fieldName == "T":
    fieldName = "kind"


proc renameHook*(v: var TradeDetails, fieldName: var string) =
  if fieldName == "T":
    fieldName = "kind"
  elif fieldName == "S":
    fieldName = "symbol"
  elif fieldName == "i":
    fieldName = "tradeId"
  elif fieldName == "x":
    fieldName = "exchange"
  elif fieldName == "p":
    fieldName = "price"
  elif fieldName == "s":
    fieldName = "size"
  elif fieldName == "c":
    fieldName = "tradeConditions"
  elif fieldName == "t":
    fieldName = "timestamp"
  elif fieldName == "z":
    fieldName = "tape"
  elif fieldName == "vz":
    fieldName = "vwap"


proc renameHook*(v: var QuoteDetails, fieldName: var string) =
  if fieldName == "T":
    fieldName = "kind"
  elif fieldName == "S":
    fieldName = "symbol"
  elif fieldName == "ax":
    fieldName = "askExchange"
  elif fieldName == "ap":
    fieldName = "askPrice"
  elif fieldName == "as":
    fieldName = "askSize"
  elif fieldName == "bx":
    fieldName = "bidExchange"
  elif fieldName == "bp":
    fieldName = "bidPrice"
  elif fieldName == "bs":
    fieldName = "bidSize"
  elif fieldName == "t":
    fieldName = "timestamp"
  elif fieldName == "z":
    fieldName = "tape"


proc renameHook*(v: var AlpacaBarDetails, fieldName: var string) =
  if fieldName == "T":
    fieldName = "kind"
  elif fieldName == "S":
    fieldName = "symbol"
  elif fieldName == "o":
    fieldName = "openPrice"
  elif fieldName == "h":
    fieldName = "highPrice"
  elif fieldName == "l":
    fieldName = "lowPrice"
  elif fieldName == "c":
    fieldName = "closePrice"
  elif fieldName == "v":
    fieldName = "volume"
  elif fieldName == "t":
    fieldName = "timestamp"


proc renameHook*(v: var TradeCorrectionDetails, fieldName: var string) =
  if fieldName == "T":
    fieldName = "kind"
  elif fieldName == "S":
    fieldName = "symbol"
  elif fieldName == "x":
    fieldName = "exchange"
  elif fieldName == "oi":
    fieldName = "origTradeId"
  elif fieldName == "op":
    fieldName = "origTradePrice"
  elif fieldName == "os":
    fieldName = "origTradeSize"
  elif fieldName == "oc":
    fieldName = "origTradeConditions"
  elif fieldName == "ci":
    fieldName = "corrTradeId"
  elif fieldName == "cp":
    fieldName = "corrTradePrice"
  elif fieldName == "cs":
    fieldName = "corrTradeSize"
  elif fieldName == "cc":
    fieldName = "corrTradeConditions"
  elif fieldName == "t":
    fieldName = "timestamp"
  elif fieldName == "z":
    fieldName = "tape"
  

proc renameHook*(v: var TradeCancelDetails, fieldName: var string) =
  if fieldName == "T":
    fieldName = "kind"
  elif fieldName == "S":
    fieldName = "symbol"
  elif fieldName == "i":
    fieldName = "tradeId"
  elif fieldName == "x":
    fieldName = "tradeExchange"
  elif fieldName == "p":
    fieldName = "tradePrice"
  elif fieldName == "s":
    fieldName = "tradeSize"
  elif fieldName == "a":
    fieldName = "action"
  elif fieldName == "t":
    fieldName = "timestamp"
  elif fieldName == "z":
    fieldName = "tape"


proc renameHook*(v: var PriceBandDetails, fieldName: var string) =
  if fieldName == "T":
    fieldName = "kind"
  elif fieldName == "S":
    fieldName = "symbol"
  elif fieldName == "u":
    fieldName = "upPrice"
  elif fieldName == "d":
    fieldName = "downPrice"
  elif fieldName == "i":
    fieldName = "indicator"
  elif fieldName == "t":
    fieldName = "timestamp"
  elif fieldName == "z":
    fieldName = "tape"


proc renameHook*(v: var TradingStatusDetails, fieldName: var string) =
  if fieldName == "T":
    fieldName = "kind"
  elif fieldName == "S":
    fieldName = "symbol"
  elif fieldName == "sc":
    fieldName = "statusCode"
  elif fieldName == "sm":
    fieldName = "statusMsg"
  elif fieldName == "rc":
    fieldName = "reasonCode"
  elif fieldName == "rm":
    fieldName = "reasonMsg"
  elif fieldName == "t":
    fieldName = "timestamp"
  elif fieldName == "z":
    fieldName = "tape"


proc enumHook*(v: string, res: var AlpacaMdWsReplyKind) =
  case v:
  of "error", "AuthErr": res = AuthErr
  of "success", "ConnectOk": res = ConnectOk
  of "subscription", "Subscription": res = Subscription
  of "t", "Trade": res = Trade
  of "q", "Quote": res = Quote
  of "b", "BarMinute": res = BarMinute
  of "d", "BarDay": res = BarDay
  of "u", "BarUpdated": res = BarUpdated
  of "c", "TradeCorrection": res = TradeCorrection
  of "x", "TradeCancel": res = TradeCancel
  of "l", "PriceBands": res = PriceBands
  of "s", "TradingStatus": res = TradingStatus
  else: res = AuthErr


proc parseHook*(s: string, i: var int, v: var AlpacaMdWsReply) =
  var entry: JsonNode
  parseHook(s, i, entry)

  let kind = block:
    var kind: AlpacaMdWsReplyKind
    if "T" in entry:
      enumHook(entry["T"].getStr, kind)
    elif "kind" in entry:
      enumHook(entry["kind"].getStr, kind)
    else:
      raise newException(KeyError, "Could not find discriminator fields T or kind!")
    kind

  if "msg" in entry and kind != AuthErr:
    if entry["msg"].getStr == "connected":
      v = AlpacaMdWsReply(kind: ConnectOk)
      return
    elif entry["msg"].getStr == "authenticated":
      v = AlpacaMdWsReply(kind: AuthOk)
      return
    else:
      v = AlpacaMdWsReply(kind: AuthErr, error: AlpacaMdWebsocketErrorDetails(code: 700, msg: "Failed to properly parse: " & s))
      return

  case kind
  of ConnectOk, AuthOk:
    # Shouldn't happen, maybe add logging
    discard
  of AuthErr:
    v = AlpacaMdWsReply(kind: kind, error: ($entry).fromJson(AlpacaMdWebsocketErrorDetails))
    return
  of Subscription:
    v = AlpacaMdWsReply(kind: kind, subscription: ($entry).fromJson(SubscriptionDetails))
    return
  of Trade:
    # required in order to round trip
    if "trade" in entry:
      entry = entry["trade"]
    v = AlpacaMdWsReply(kind: kind, trade: ($entry).fromJson(TradeDetails))
    return
  of Quote:
    # required in order to round trip
    if "quote" in entry:
      entry = entry["quote"]
    v = AlpacaMdWsReply(kind: kind, quote: ($entry).fromJson(QuoteDetails))
    return
  of BarMinute, BarDay, BarUpdated:
    # required in order to round trip
    if "bar" in entry:
      entry = entry["bar"]
    v = AlpacaMdWsReply(kind: kind, bar: ($entry).fromJson(AlpacaBarDetails))
    return
  of TradeCorrection:
    # required in order to round trip
    if "tradeCorrection" in entry:
      entry = entry["tradeCorrection"]
    v = AlpacaMdWsReply(kind: kind, tradeCorrection: ($entry).fromJson(TradeCorrectionDetails))
    return
  of TradeCancel:
    # required in order to round trip
    if "tradeCancel" in entry:
      entry = entry["tradeCancel"]
    v = AlpacaMdWsReply(kind: kind, tradeCancel: ($entry).fromJson(TradeCancelDetails))
    return
  of PriceBands:
    # required in order to round trip
    if "priceBands" in entry:
      entry = entry["priceBands"]
    v = AlpacaMdWsReply(kind: kind, priceBands: ($entry).fromJson(PriceBandDetails))
    return
  of TradingStatus:
    # required in order to round trip
    if "tradingStatus" in entry:
      entry = entry["tradingStatus"]
    v = AlpacaMdWsReply(kind: kind, tradingStatus: ($entry).fromJson(TradingStatusDetails))
    return
