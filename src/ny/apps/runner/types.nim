import ny/core/md/alpaca/types
import ny/core/trading/enums/side

type
  MarketIoEffect* = object

  ResponseMessageKind* = enum
    Timer
    MarketData
    OrderUpdate

  TimerEvent* = object
    # at*: float # epoch float
    at*: string

  MarketDataEvent* = object
    symbol*: string
  
  OrderUpdateKind* = enum
    Ack
    New
    FilledPartial
    FilledFull
    Cancelled
    CancelPending

  OrderUpdateEvent* = object
    orderId*: string
    clientOrderId*: string
    timestamp*: string
    case kind*: OrderUpdateKind
    of FilledPartial, FilledFull:
      fillAmt*: int
    of Ack, New, Cancelled, CancelPending:
      discard

  ResponseMessage* = object
    case kind*: ResponseMessageKind
    of Timer:
      timer*: TimerEvent
    of MarketData:
      # md*: MarketDataEvent
      md*: AlpacaMdWsReply
    of OrderUpdate:
      ou*: OrderUpdateEvent

  RequestMessageKind* = enum
    Timer
    OrderSend
    OrderCancel

  RequestMessage* = object
    case kind*: RequestMessageKind
    of Timer:
      timer*: TimerEvent
    of OrderSend:
      # For now, only support sending day limit and market orders
      clientOrderId*: string
      side*: SideKind
      quantity*: int
      price*: string
    of OrderCancel:
      idToCancel*: string
