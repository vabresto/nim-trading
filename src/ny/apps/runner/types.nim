import ny/core/md/alpaca/types

type
  MarketIoEffect* = object

  MessageKind* = enum
    Timer
    MarketData
    OrderUpdate

  TimerEvent* = object
    # at*: float # epoch float
    at*: string

  MarketDataEvent* = object
    symbol*: string
  
  OrderUpdateEvent* = object
    symbol*: string
    orderId*: string
    clientOrderId*: string

  ResponseMessage* = object
    case kind*: MessageKind
    of Timer:
      timer*: TimerEvent
    of MarketData:
      # md*: MarketDataEvent
      md*: AlpacaMdWsReply
    of OrderUpdate:
      ou*: OrderUpdateEvent

  RequestMessage* = object
    case kind*: MessageKind
    of Timer:
      timer*: TimerEvent
    of MarketData, OrderUpdate:
      discard
