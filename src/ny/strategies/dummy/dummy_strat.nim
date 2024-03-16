## This is a simple momentum strategy., mostly just a tech demo
## We wait for 3 consecutive minute bars of monotonically increasing prices (low and high?)
## Then we send a limit order to buy 100 shares (what price do we use?)
## If we don't get any fills after 15 minutes (arbitrary), reset to the waiting state
## If we do get fills, try to exit (no trailing stop implemented yet, so we'll just go for a fixed price increase for now)
## Maybe consider having a close position at end of day state

import std/options
import std/strutils
import std/tables
import std/times

import chronicles

import ny/core/types/timestamp
import ny/core/types/order
import ny/core/types/price
import ny/core/types/strategy_base
import ny/core/md/md_types
import ny/core/types/md/bar_details

const kNumRequiredBarIncreases = 3
const kCentsEnterDiscount = 15

logScope:
  topics = "strategy strat:dummy"

type
  StateKind = enum
    WaitingForMomentum
    WaitingForFill
    ExitingPosition

  DummyStrategyState* = object of StrategyBase
    state: StateKind = WaitingForMomentum
    curTime: Timestamp
    
    numConsecIncreases: int = 0
    lastBar: Option[BarDetails]

    orderIdBase: string = ""
    numOrdersSent: int = 0
    numOrdersClosed: int = 0
    stratCumSharesFilled: int = 0

    pendingOrders: Table[ClientOrderId, SysOrder]
    openOrders: Table[OrderId, SysOrder]


func initDummyStrategy*(): DummyStrategyState =
  {.noSideEffect.}:
    let dateStr = getNowUtc().getDateStr()
  DummyStrategyState(
    orderIdBase: dateStr,
    pendingOrders: initTable[ClientOrderId, SysOrder](),
    openOrders: initTable[OrderId, SysOrder](),
  )


func makeOrderId(state: var DummyStrategyState): ClientOrderId =
  inc state.numOrdersSent
  (state.orderIdBase & ":dummy:o-" & $state.numOrdersSent).ClientOrderId


func removeOrder(state: var DummyStrategyState, update: InputEvent) =
  {.noSideEffect.}:
    info "Closing order", id=update.ou.orderId
  
  if update.ou.orderId in state.openOrders:
    state.openOrders.del update.ou.orderId
    inc state.numOrdersClosed        
  else:
    {.noSideEffect.}:
      error "Trying to close missing order!", cur=state.openOrders[update.ou.orderId], event=update


func executeDummyStrategy*(state: var DummyStrategyState, update: InputEvent): seq[OutputEvent] {.raises: [].} =
  {.noSideEffect.}:
    debug "Strategy got event", update, ts=update.timestamp, state

  state.curTime = update.timestamp

  case update.kind
  of Timer:
    {.noSideEffect.}:
      error "Got timer", timer=update.timer

    if "[RESET-STATE]" in update.timer.name:
      {.noSideEffect.}:
        info "Got reset state message from timer", curState=state.state
    state.state = WaitingForMomentum
    state.numConsecIncreases = 0
    for id in state.openOrders.keys:
      result &= OutputEvent(kind: OrderCancel, idToCancel: id)
      {.noSideEffect.}:
        debug "Sending order cancel event", id


  of MarketData:
    if update.kind == MarketData and update.md.kind == BarMinute:
      {.noSideEffect.}:
        info "Strategy got bar", update, state=state.state

    case state.state
    of WaitingForMomentum:
      if update.kind == MarketData and update.md.kind == BarMinute:
        let newBar = update.md.bar
        if state.lastBar.isSome and newBar.lowPrice >= state.lastBar.get.lowPrice:
          inc state.numConsecIncreases
        state.lastBar = some newBar

        if state.numConsecIncreases > kNumRequiredBarIncreases:
          {.noSideEffect.}:
            warn "Strategy got 3rd consec increase", update
          state.numConsecIncreases = 0
          state.state = WaitingForFill

          let clientOrderId = state.makeOrderId
          let order = SysOrder(
            id: "---PENDING---".OrderId,
            clientOrderId: clientOrderId,
            side: Buy,
            kind: Limit,
            tif: Day,
            size: 100,
            # price: newBar.openPrice - Price(dollars: 0, cents: kCentsEnterDiscount),
            price: newBar.highPrice, # for debug
          )
          state.pendingOrders[clientOrderId] = order
          return @[
            OutputEvent(kind: OrderSend, clientOrderId: clientOrderId, side: order.side, quantity: order.size, price: order.price),
            OutputEvent(kind: Timer, timer: TimerEvent(timestamp: state.curTime + initDuration(seconds=120), name: "[RESET-STATE] Waiting for fill expired; restart"))
          ]

    of WaitingForFill:
      discard
    of ExitingPosition:
      discard

  of OrderUpdate:
    {.noSideEffect.}:
      error "Strategy got order update event", update, ts=update.timestamp
    
    case update.ou.kind
    of New:
      if update.ou.clientOrderId notin state.pendingOrders:
        {.noSideEffect.}:
          error "Got order update for order we don't know about!", update=update.ou
      else:
        state.pendingOrders.del update.ou.clientOrderId

      if update.ou.orderId in state.openOrders:
        {.noSideEffect.}:
          error "Got new order event for existing order!", cur=state.openOrders[update.ou.orderId], `new`=update.ou

      state.openOrders[update.ou.orderId] = SysOrder(
        id: update.ou.orderId,
        clientOrderId: update.ou.clientOrderId,
        side: update.ou.side,
        kind: Limit,
        tif: Day,
        size: update.ou.size,
        price: update.ou.price,
      )
    of FilledPartial:
      state.stratCumSharesFilled += update.ou.fillAmt
      try:
        state.openOrders[update.ou.orderId].cumSharesFilled += update.ou.fillAmt
      except KeyError:
        {.noSideEffect.}:
          error "Failed to update fill amount!", event=update, state
    of FilledFull:
      state.stratCumSharesFilled += update.ou.fillAmt
      state.removeOrder(update)
    of Cancelled:
      state.removeOrder(update)
    of Ack, CancelPending:
      {.noSideEffect.}:
          error "Got unhandled order event!", event=update
