import std/math
import std/sets
import std/tables

import chronicles

import ny/core/md/md_types
import ny/core/types/nbbo
import ny/core/types/order
import ny/core/types/order_kind
import ny/core/types/price
import ny/core/types/side
import ny/core/types/tif
import ny/core/types/timestamp
import ny/core/utils/sim_utils


type
  StrategyBase* = object of RootObj
    strategyId: string

    curTime: Timestamp
    curEventNum: int = 0
    nbbo: Nbbo

    position: int = 0
    positionVwap: float = 0

    orderIdBase: string = ""
    numOrdersSent: int = 0
    numOrdersClosed: int = 0
    
    stratTotalSharesBought: int = 0
    stratTotalSharesSold: int = 0
    stratTotalNotionalBought: Price
    stratTotalNotionalSold: Price
    stratPnl: Price

    pendingOrders: Table[ClientOrderId, SysOrder]
    openOrders: Table[OrderId, SysOrder]

  InputEventKind* = enum
    Timer
    MarketData
    OrderUpdate
    CommandFailed

  OutputEventKind* = enum
    Timer
    OrderSend
    OrderCancel

  TimerEvent* = object
    timestamp*: Timestamp
    name*: string
    tags*: HashSet[string]

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
      fillPrice*: Price
    of Ack, New:
      side*: SysSideKind
      size*: int
      tif*: TifKind
      price*: Price
    of Cancelled, CancelPending:
      discard

  FailedCommandKind* = enum
    OrderSendFailed
    OrderCancelFailed

  FailedCommand* = object
    timestamp*: Timestamp
    # TODO: Would be good to return the fail reason given from alpaca so we can handle each differently
    case kind*: FailedCommandKind
    of OrderSendFailed:
      clientOrderId*: ClientOrderId
    of OrderCancelFailed:
      idToCancel*: OrderId # exchange id

  InputEvent* = object
    case kind*: InputEventKind
    of Timer:
      timer*: TimerEvent
    of MarketData:
      md*: MarketDataUpdate
    of OrderUpdate:
      ou*: SysOrderUpdateEvent
    of CommandFailed:
      cmd*: FailedCommand

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
      orderKind*: OrderKind
      tif*: TifKind
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
  of CommandFailed:
    rsp.cmd.timestamp


func `<`*(a, b: TimerEvent): bool = a.timestamp < b.timestamp


#
# Strategy Base
#


func initStrategyBase*(strategyId: string, orderIdBase: string): StrategyBase =
  StrategyBase(
    strategyId: strategyId,
    orderIdBase: orderIdBase,
    pendingOrders: initTable[ClientOrderId, SysOrder](),
    openOrders: initTable[OrderId, SysOrder](),
  )

func initStrategyBase*(base: var StrategyBase, strategyId: string, orderIdBase: string) =
  # Really annoying, but apparently this is the recommended way to do base class init in nim
  base = initStrategyBase(strategyId, orderIdBase)

func curTime*(base: StrategyBase): lent Timestamp = base.curTime
func curEventNum*(base: StrategyBase): int = base.curEventNum
func position*(base: StrategyBase): int = base.position
func positionVwap*(base: StrategyBase): float = base.positionVwap

func numOrdersSent*(base: StrategyBase): int = base.numOrdersSent
func numOrdersClosed*(base: StrategyBase): int = base.numOrdersClosed
func stratTotalSharesBought*(base: StrategyBase): int = base.stratTotalSharesBought
func stratTotalSharesSold*(base: StrategyBase): int = base.stratTotalSharesSold
func stratTotalNotionalBought*(base: StrategyBase): Price = base.stratTotalNotionalBought
func stratTotalNotionalSold*(base: StrategyBase): Price = base.stratTotalNotionalSold
func stratPnl*(base: StrategyBase): Price = base.stratPnl

func pendingOrders*(base: StrategyBase): lent Table[ClientOrderId, SysOrder] = base.pendingOrders
func openOrders*(base: StrategyBase): lent Table[OrderId, SysOrder] = base.openOrders
func calcPositionMktPrice*(base: StrategyBase): Price =
  if base.position == 0:
    Price(dollars: 0, cents: 0)
  elif base.position > 0:
    base.nbbo.bidPrice * base.position
  else:
    base.nbbo.askPrice * base.position

func makeOrderId*(state: var StrategyBase): ClientOrderId =
  inc state.numOrdersSent
  (state.orderIdBase & "dummy:o-" & $state.numOrdersSent).ClientOrderId


func calcRegFee*(notionalSold: Price): Price =
  ((ceil(notionalSold.inCents.float * (8 / 1_000_000))) / 100).parsePrice


func calcTafFee*(sharesSold: int): Price =
  (sharesSold / 1_000_000 * 166).parsePrice

func calculateTotalFees*(state: StrategyBase): tuple[regFee: Price, tafFee: Price] =
  # https://alpaca.markets/blog/reg-taf-fees/
  let regFee = state.stratTotalNotionalSold.calcRegFee
  let tafFee = state.stratTotalSharesSold.calcTafFee
  (regFee, tafFee)


func calcOpenSellInterest*(self: StrategyBase): int =
  for _, order in self.openOrders:
    if order.side == Sell:
      result += order.openInterest
  for _, order in self.pendingOrders:
    if order.side == Sell:
      result += order.openInterest


func numOpenOrders*(self: StrategyBase): int =
  for (_, order) in self.openOrders.pairs:
    if not order.done:
      inc result


func markOrderDone(state: var StrategyBase, update: InputEvent) =
  if update.kind != OrderUpdate:
    return

  {.noSideEffect.}:
    trace "Closing order", id=update.ou.orderId
  
  try:
    state.openOrders[update.ou.orderId].done = true
    inc state.numOrdersClosed
  except KeyError:
    {.noSideEffect.}:
      error "Trying to close missing order!", cur=state.openOrders[update.ou.orderId], event=update


func pruneDoneOrders*(state: var StrategyBase) =
  var pendingOrdersToPrune = newSeq[ClientOrderId]()
  for (id, order) in state.pendingOrders.mpairs:
    if order.done:
      pendingOrdersToPrune.add id

  for id in pendingOrdersToPrune:
    state.pendingOrders.del id

  var openOrdersToPrune = newSeq[OrderId]()
  for (id, order) in state.openOrders.mpairs:
    if order.done:
      openOrdersToPrune.add id

  for id in openOrdersToPrune:
    state.openOrders.del id


func handleFill(state: var StrategyBase, update: InputEvent) =
  if update.kind != OrderUpdate:
    return
  if update.ou.kind != FilledPartial and update.ou.kind != FilledFull:
    return

  let fillAmt = update.ou.fillAmt
  let fillPrice = update.ou.fillPrice
  let eventPrice = fillPrice * fillAmt

  try:
    var order = state.openOrders[update.ou.orderId]
    case order.side
    of Buy:
      state.positionVwap = ((state.positionVwap * state.position.float) + (eventPrice.inCents / 100)) / (state.position + fillAmt).float

      state.stratTotalSharesBought += fillAmt
      state.stratTotalNotionalBought += eventPrice
      state.position += fillAmt
      state.stratPnl -= eventPrice
    of Sell:
      state.stratTotalSharesSold += fillAmt
      state.stratTotalNotionalSold += eventPrice
      state.position -= fillAmt
      state.stratPnl += eventPrice
      # For sells, if we end up at 0, we can reset our vwap
      if state.position == 0:
        state.positionVwap = 0.float

    order.cumSharesFilled += fillAmt
  except KeyError:
    {.noSideEffect.}:
      error "Failed to update fill amount!", event=update, state

proc handleInputEvent*(state: var StrategyBase, update: InputEvent) =
  inc state.curEventNum
  state.curTime = update.timestamp

  case update.kind
  of Timer:
    discard
  of MarketData:
    case update.md.kind
    of Quote:
      state.nbbo = Nbbo(
        askPrice: update.md.askPrice,
        askSize: update.md.askSize,
        bidPrice: update.md.bidPrice,
        bidSize: update.md.bidSize,
      )
    of BarMinute, Status:
      discard
  of OrderUpdate:
    case update.ou.kind
    of Ack:
      info "Got ack", event=update

    of New:
      if update.ou.clientOrderId notin state.pendingOrders:
        error "Got order update for order we don't know about!", update=update.ou
      else:
        state.pendingOrders.del update.ou.clientOrderId

      if update.ou.orderId in state.openOrders:
        error "Got new order event for existing order!", cur=state.openOrders[update.ou.orderId], `new`=update.ou

      state.openOrders[update.ou.orderId] = SysOrder(
        id: update.ou.orderId,
        clientOrderId: update.ou.clientOrderId,
        side: update.ou.side,
        kind: Limit, # TODO: This is wrong, and should be parsed
        tif: update.ou.tif,
        size: update.ou.size,
        price: update.ou.price,
      )

    of FilledPartial:
      info "Got partial fill", event=update, position=state.position, posVwap=state.positionVwap, posMktValue=state.calcPositionMktPrice(), stratPnl=state.stratPnl
      state.handleFill(update)

    of FilledFull:
      info "Got full fill", event=update, position=state.position, posVwap=state.positionVwap, posMktValue=state.calcPositionMktPrice(), stratPnl=state.stratPnl
      state.handleFill(update)
      state.markOrderDone(update)

    of Cancelled:
      info "Got cancel", event=update, position=state.position, posVwap=state.positionVwap, posMktValue=state.calcPositionMktPrice(), stratPnl=state.stratPnl
      state.markOrderDone(update)

    of CancelPending:
      error "Got unhandled order event!", event=update
  
  of CommandFailed:
    case update.cmd.kind
    of OrderSendFailed:
      try:
        state.pendingOrders[update.cmd.clientOrderId].done = true
      except KeyError:
        error "Failed to mark pending order as done when send failed", clientOrderId=update.cmd.clientOrderId

    of OrderCancelFailed:
      # Nothing to do at this point, the order is still open since we failed to cancel it
      discard


proc handleOutputEvent*(state: var StrategyBase, update: OutputEvent) = 
  case update.kind
  of Timer, OrderCancel:
    discard
  of OrderSend:
    let order = SysOrder(
      id: ("PENDING:" & update.clientOrderId.string).OrderId,
      clientOrderId: update.clientOrderId,
      side: update.side,
      kind: update.orderKind,
      tif: update.tif,
      size: update.quantity,
      price: update.price,
    )
    info "Sending new order", order

    if isSimuluation():
      if order.side == Sell and state.position - state.calcOpenSellInterest() - order.size < 0:
        error "Attempting to short sell", order
        quit 213

    state.pendingOrders[update.clientOrderId] = order
