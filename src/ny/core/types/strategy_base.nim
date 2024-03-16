import ny/core/md/md_types
import ny/core/types/price
import ny/core/types/side
import ny/core/types/tif
import ny/core/types/timestamp
import ny/core/types/order

type
  StrategyBase* = object of RootObj

  InputEventKind* = enum
    Timer
    MarketData
    OrderUpdate

  OutputEventKind* = enum
    Timer
    OrderSend
    OrderCancel

  TimerEvent* = object
    timestamp*: Timestamp
    name*: string

  SysOrderUpdateKind* = enum
    Ack
    New
    FilledPartial
    FilledFull
    Cancelled
    CancelPending

  SysOrderUpdateEvent* = object
    orderId*: OrderId
    clientOrderId*: ClientOrderId
    timestamp*: Timestamp
    case kind*: SysOrderUpdateKind
    of FilledPartial, FilledFull:
      fillAmt*: int
    of Ack, New:
      side*: SysSideKind
      size*: int
      tif*: TifKind
      price*: Price
    of Cancelled, CancelPending:
      discard

  InputEvent* = object
    case kind*: InputEventKind
    of Timer:
      timer*: TimerEvent
    of MarketData:
      md*: MarketDataUpdate
    of OrderUpdate:
      ou*: SysOrderUpdateEvent

  OutputEvent* = object
    case kind*: OutputEventKind
    of Timer:
      timer*: TimerEvent
    of OrderSend:
      # For now, only support sending day limit and market orders
      clientOrderId*: ClientOrderId
      side*: SysSideKind
      quantity*: int
      price*: Price
    of OrderCancel:
      idToCancel*: OrderId # exchange id


func timestamp*(rsp: InputEvent): Timestamp =
  case rsp.kind
  of Timer:
    rsp.timer.timestamp
  of MarketData:
    rsp.md.timestamp
  of OrderUpdate:
    rsp.ou.timestamp
