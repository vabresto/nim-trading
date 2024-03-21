import std/json
import std/hashes

import jsony

import ny/core/trading/enums/order_kind
import ny/core/trading/enums/side
import ny/core/trading/enums/tif
import ny/core/types/price

export order_kind
export side
export tif
export price


type
  AlpacaOrder* = object
    id*: string = "" # set by the remote
    symbol*: string
    side*: AlpacaSideKind
    kind*: AlpacaOrderKind
    tif*: AlpacaTifKind

    size*: string = ""
    notional*: string = ""

    limitPrice*: string = ""
    # stopPrice*: string = ""
    # trailPrice*: string = ""
    # trailPercent*: string = ""
    extendedHours*: bool = false
    clientOrderId*: string = ""
    # Several fields missing here
    cumSharesFilled*: int = 0

  AlpacaOrderRef* = ref AlpacaOrder

  OrderCreateResponse* = object
    id*: string
    clientOrderId*: string
    raw*: JsonNode

  # WsOrderUpdateData* = object
  #   event*: string
  #   timestamp*: string
  #   order*: AlpacaOrder

  # WsOrderUpdate* = object
  #   stream*: string
  #   data*: WsOrderUpdateData

  #   # Added after the fact
  #   symbol*: string
  #   raw*: JsonNode


func `$`*(order: AlpacaOrderRef): string = $(order[])
func hash*(order: AlpacaOrderRef): Hash = hash(order[])


func makeMarketOrder*(symbol: string, side: AlpacaSideKind, quantity: float, clientOrderId: string): AlpacaOrder =
  ## Fractional quantities require Market + Day
  AlpacaOrder(
    symbol: symbol,
    size: $quantity,
    side: side,
    kind: Market,
    tif: Day,
    extendedHours: false,
    clientOrderId: clientOrderId,
  )


func makeMarketOrder*(symbol: string, side: AlpacaSideKind, notional: int, clientOrderId: string): AlpacaOrder =
  ## Notional-based orders require Market + Day
  AlpacaOrder(
    symbol: symbol,
    notional: $notional,
    side: side,
    kind: Market,
    tif: Day,
    extendedHours: false,
    clientOrderId: clientOrderId,
  )


func makeMarketOnOpenOrder*(symbol: string, side: AlpacaSideKind, quantity: int, clientOrderId: string): AlpacaOrder =
  AlpacaOrder(
    symbol: symbol,
    size: $quantity,
    side: side,
    kind: Market,
    tif: OpeningAuction,
    extendedHours: false,
    clientOrderId: clientOrderId,
  )


func makeMarketOnCloseOrder*(symbol: string, side: AlpacaSideKind, quantity: int, clientOrderId: string): AlpacaOrder =
  AlpacaOrder(
    symbol: symbol,
    size: $quantity,
    side: side,
    kind: Market,
    tif: ClosingAuction,
    extendedHours: false,
    clientOrderId: clientOrderId,
  )


func makeImmediateOrKillOrder*(symbol: string, side: AlpacaSideKind, quantity: int, clientOrderId: string): AlpacaOrder =
  ## IOC without price is Market
  AlpacaOrder(
    symbol: symbol,
    size: $quantity,
    side: side,
    kind: Market,
    tif: Ioc,
    extendedHours: false,
    clientOrderId: clientOrderId,
  )


func makeImmediateOrKillOrder*(symbol: string, side: AlpacaSideKind, quantity: int, price: string, clientOrderId: string): AlpacaOrder =
  ## IOC without price is Market
  AlpacaOrder(
    symbol: symbol,
    size: $quantity,
    side: side,
    kind: Limit,
    tif: Ioc,
    limitPrice: price,
    extendedHours: false,
    clientOrderId: clientOrderId,
  )


func makeFillOrKillOrder*(symbol: string, side: AlpacaSideKind, kind: AlpacaOrderKind, quantity: int, price: string, clientOrderId: string): AlpacaOrder =
  AlpacaOrder(
    symbol: symbol,
    size: $quantity,
    side: side,
    kind: kind,
    tif: Fok,
    limitPrice: price,
    extendedHours: false,
    clientOrderId: clientOrderId,
  )


func makeLimitOrder*(symbol: string, side: AlpacaSideKind, tif: AlpacaTifKind, quantity: int, price: string, clientOrderId: string, extendedHours: bool = false): AlpacaOrder =
  AlpacaOrder(
    symbol: symbol,
    size: $quantity,
    side: side,
    kind: Limit,
    tif: tif,
    limitPrice: price,
    extendedHours: extendedHours,
    clientOrderId: clientOrderId,
  )


proc dumpHook*(s: var string, v: AlpacaOrder) =
  s.add "{\"symbol\":"
  dumpHook(s, v.symbol)

  s.add ",\"side\":\""
  dumpHook(s, v.side)
  s.add "\",\"type\":\""
  dumpHook(s, v.kind)
  s.add "\",\"time_in_force\":\""
  dumpHook(s, v.tif)
  s.add "\","

  if v.size != "":
    s.add "\"qty\":"
    dumpHook(s, v.size)
  elif v.notional != "":
    s.add "\"notional\":"
    dumpHook(s, v.notional)

  if v.limitPrice != "":
    s.add ",\"limit_price\":"
    dumpHook(s, v.limitPrice)
  
  # if v.stopPrice != "":
  #   s.add ",\"stop_price\":"
  #   dumpHook(s, v.stopPrice)

  if v.extendedHours:
    s.add ",\"extended_hours\":"
    dumpHook(s, v.extendedHours)

  s.add ",\"client_order_id\":"
  dumpHook(s, v.clientOrderId)
  s.add "}"  


proc renameHook*(v: var AlpacaOrder, fieldName: var string) =
  echo "Probably should not be using this hook"
  if fieldName == "time_in_force":
    fieldName = "tif"
  elif fieldName == "order_type":
    fieldName = "kind"
  elif fieldName == "qty":
    fieldName = "size"
