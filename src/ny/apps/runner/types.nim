import ny/core/md/alpaca/types
import ny/core/trading/enums/side
import ny/core/md/md_types
import ny/core/types/timestamp

type
  MarketIoEffect* = object

  ResponseMessageKind* = enum
    Timer
    MarketData
    OrderUpdate

  TimerEvent* = object
    # at*: float # epoch float
    at*: Timestamp

  # MarketDataEvent* = object
  #   symbol*: string
  
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
    timestamp*: Timestamp
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
      # md*: AlpacaMdWsReply
      md*: MarketDataUpdate
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


func timestamp*(rsp: ResponseMessage): Timestamp =
  case rsp.kind
  of Timer:
    rsp.timer.at
  of MarketData:
    rsp.md.timestamp
  of OrderUpdate:
    rsp.ou.timestamp
