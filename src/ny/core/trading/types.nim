import std/json

import jsony


type
  SideKind* = enum
    Buy
    Sell
  
  OrderKind* = enum
    Market
    Limit
    # Stop
    # StopLimit
    # StopTrailing

  TifKind* = enum
    Day
    Gtc
    OpeningAuction
    ClosingAuction
    Ioc
    Fok

  Order* = object
    symbol*: string
    side*: SideKind
    kind*: OrderKind
    tif*: TifKind

    size*: string = ""
    notional*: string = ""

    limitPrice*: string = ""
    # stopPrice*: string = ""
    # trailPrice*: string = ""
    # trailPercent*: string = ""
    extendedHours*: bool = false
    clientOrderId*: string = ""
    # Several fields missing here

  OrderCreateResponse* = object
    id*: string
    clientOrderId*: string
    raw*: JsonNode


func makeMarketOrder*(symbol: string, side: SideKind, quantity: float, clientOrderId: string): Order =
  ## Fractional quantities require Market + Day
  Order(
    symbol: symbol,
    size: $quantity,
    side: side,
    kind: Market,
    tif: Day,
    extendedHours: false,
    clientOrderId: clientOrderId,
  )


func makeMarketOrder*(symbol: string, side: SideKind, notional: int, clientOrderId: string): Order =
  ## Notional-based orders require Market + Day
  Order(
    symbol: symbol,
    notional: $notional,
    side: side,
    kind: Market,
    tif: Day,
    extendedHours: false,
    clientOrderId: clientOrderId,
  )


func makeMarketOnOpenOrder*(symbol: string, side: SideKind, quantity: int, clientOrderId: string): Order =
  Order(
    symbol: symbol,
    size: $quantity,
    side: side,
    kind: Market,
    tif: OpeningAuction,
    extendedHours: false,
    clientOrderId: clientOrderId,
  )


func makeMarketOnCloseOrder*(symbol: string, side: SideKind, quantity: int, clientOrderId: string): Order =
  Order(
    symbol: symbol,
    size: $quantity,
    side: side,
    kind: Market,
    tif: ClosingAuction,
    extendedHours: false,
    clientOrderId: clientOrderId,
  )


func makeImmediateOrKillOrder*(symbol: string, side: SideKind, quantity: int, clientOrderId: string): Order =
  ## IOC without price is Market
  Order(
    symbol: symbol,
    size: $quantity,
    side: side,
    kind: Market,
    tif: Ioc,
    extendedHours: false,
    clientOrderId: clientOrderId,
  )


func makeImmediateOrKillOrder*(symbol: string, side: SideKind, quantity: int, price: string, clientOrderId: string): Order =
  ## IOC without price is Market
  Order(
    symbol: symbol,
    size: $quantity,
    side: side,
    kind: Limit,
    tif: Ioc,
    limitPrice: price,
    extendedHours: false,
    clientOrderId: clientOrderId,
  )


func makeFillOrKillOrder*(symbol: string, side: SideKind, kind: OrderKind, quantity: int, price: string, clientOrderId: string): Order =
  Order(
    symbol: symbol,
    size: $quantity,
    side: side,
    kind: kind,
    tif: Fok,
    limitPrice: price,
    extendedHours: false,
    clientOrderId: clientOrderId,
  )


func makeLimitOrder*(symbol: string, side: SideKind, tif: TifKind, quantity: int, price: string, clientOrderId: string, extendedHours: bool = false): Order =
  Order(
    symbol: symbol,
    size: $quantity,
    side: side,
    kind: Limit,
    tif: tif,
    limitPrice: price,
    extendedHours: extendedHours,
    clientOrderId: clientOrderId,
  )


proc dumpHook*(s: var string, v: SideKind) =
  case v
  of Buy:
    s.add "buy"
  of Sell:
    s.add "sell"


proc dumpHook*(s: var string, v: OrderKind) =
  case v
  of Market:
    s.add "market"
  of Limit:
    s.add "limit"
  # of Stop:
  #   s.add "stop"
  # of StopLimit:
  #   s.add "stop_limit"
  # of StopTrailing:
  #   s.add "trailing_stop"


proc dumpHook*(s: var string, v: TifKind) =
  case v
  of Day:
    s.add "day"
  of Gtc:
    s.add "gtc"
  of OpeningAuction:
    s.add "opg"
  of ClosingAuction:
    s.add "cls"
  of Ioc:
    s.add "ioc"
  of Fok:
    s.add "fok"


proc dumpHook*(s: var string, v: Order) =
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

  
