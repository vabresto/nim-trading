## # Overview
## This is a simple momentum strategy, mostly just a tech demo.
## The strategy:
## - waits for 3 consecutive minute bars of monotonically increasing low prices
## - sends a limit order to buy 100 shares (at a slightly discounted price compared to the most recent high price we saw over the past minute)
## - if we don't get any fills after 15 minutes (arbitrary), reset to the waiting state
## - if we do get fills, try to exit (no trailing stop implemented yet, so we'll just go for a fixed price increase for now). First try an
##  exit at an optimistic price, and if we don't exit after a few minutes, try again at a pessimistic price
## - if we have a position at the end of the day, send an MOC order to end flat

import std/options
import std/sets
import std/tables
import std/times

import chronicles

import ny/core/md/md_types
import ny/core/types/md/bar_details
import ny/core/types/nbbo
import ny/core/types/price
import ny/core/types/strategy_base
import ny/core/types/timestamp


const kNumRequiredBarIncreases = 3
const kCentsEnterDiscount = 5

logScope:
  topics = "strategy strat:dummy"

type
  StateKind = enum
    WaitingForMomentum
    WaitingForFill
    ExitingPositionOptimistic
    ExitingPositionPessimistic
    EodClose
    EodDone

  DummyStrategyState* = object of StrategyBase
    state: StateKind = WaitingForMomentum
    sentEodTimer: bool = false
    numConsecIncreases: int = 0
    numRetries: int = 0
    lastNbbo: Option[Nbbo]
    lastBar: Option[BarDetails]


func initDummyStrategy*(strategyId: string, orderIdBase: string): DummyStrategyState =
  result.initStrategyBase(strategyId, orderIdBase)


func closeAllOpenOrders(state: var DummyStrategyState): seq[OutputEvent] {.raises: [].} =
  for id, order in state.openOrders:
    if not order.done:
      result &= OutputEvent(kind: OrderCancel, idToCancel: id)
      {.noSideEffect.}:
        debug "Sending order cancel event", id


func tryEnterPosition(state: var DummyStrategyState, price: Price): seq[OutputEvent] {.raises: [].} =
  result &= @[
    OutputEvent(kind: OrderSend, clientOrderId: state.makeOrderId, side: Buy, quantity: 100, price: price, orderKind: Limit, tif: Day),
    OutputEvent(kind: Timer, timer: TimerEvent(timestamp: state.curTime + initDuration(seconds=120), tags: ["RESET-STATE"].toHashSet, name: "Waiting for fill expired; restart"))
  ]


func getIdealExitPrice(self: var DummyStrategyState): Price = 
  (self.positionVwap * 1.005).parsePrice # try to take 0.5% in profit


func getPessimisticExitPrice(self: var DummyStrategyState): Price = 
  if self.lastNbbo.isSome:
    self.lastNbbo.get.askPrice - Price(dollars: 0, cents: 1)
  else:
    Price(dollars: 0, cents: 0)


func tryExitPosition(self: var DummyStrategyState, price: Price): seq[OutputEvent] {.raises: [].} =
  if self.pendingOrders.len == 0 and self.numOpenOrders == 0:
    result &= @[
      OutputEvent(kind: OrderSend, clientOrderId: self.makeOrderId, side: Sell, quantity: self.position, price: price, orderKind: Limit, tif: Day),
      OutputEvent(kind: Timer, timer: TimerEvent(timestamp: self.curTime + initDuration(seconds=120), tags: ["RESET-STATE"].toHashSet, name: "Waiting for exit expired; try again")),
    ]
  else:
    result &= @[
      OutputEvent(kind: Timer, timer: TimerEvent(timestamp: self.curTime + initDuration(milliseconds=10), tags: ["CLOSE", "RESET-STATE"].toHashSet, name: "Trying to exit but had open orders; try again")),
    ]


func marketExitPosition(self: var DummyStrategyState): seq[OutputEvent] {.raises: [].} =
  if self.pendingOrders.len == 0 and self.numOpenOrders == 0:
    result &= @[
      OutputEvent(kind: OrderSend, clientOrderId: self.makeOrderId, side: Sell, quantity: self.position, orderKind: Market, tif: ClosingAuction),
    ]
  else:
    result &= @[
      OutputEvent(kind: Timer, timer: TimerEvent(timestamp: self.curTime + initDuration(milliseconds=10), tags: ["CLOSE", "RESET-STATE"].toHashSet, name: "Trying to market exit but had open orders; try again")),
    ]


func goToState(self: var DummyStrategyState, state: StateKind): seq[OutputEvent] {.raises: [].} =
  case state
  of WaitingForMomentum:
    if self.state == ExitingPositionOptimistic or self.state == ExitingPositionPessimistic:
      {.noSideEffect.}:
        info "Fully exited position, going to WaitingForMomentum", pending=self.pendingOrders, opened=self.openOrders
    self.state = WaitingForMomentum
    self.numConsecIncreases = 0
  
  of WaitingForFill:
    {.noSideEffect.}:
      info "Strategy got 3rd consec increase", stratPnl=self.stratPnl, pending=self.pendingOrders, opened=self.openOrders
    self.numConsecIncreases = 0
    self.state = WaitingForFill
  
  of ExitingPositionOptimistic:
    self.state = ExitingPositionOptimistic

  of ExitingPositionPessimistic:
    if self.state != ExitingPositionOptimistic:
      {.noSideEffect.}:
        warn "Going to pessimistic exit but not in optimistic exit state", curState=self.state, pending=self.pendingOrders, opened=self.openOrders
    self.state = ExitingPositionPessimistic
  
  of EodClose:
    {.noSideEffect.}:
      info "Going to EOD close state", curState=self.state, position=self.position, posVwap=self.positionVwap, posMktValue=self.calcPositionMktPrice(), stratPnl=self.stratPnl, fees=self.calculateTotalFees, pending=self.pendingOrders, opened=self.openOrders
    self.state = EodClose
  of EodDone:
    discard


func executeDummyStrategy*(state: var DummyStrategyState, update: InputEvent): seq[OutputEvent] {.raises: [].} =
  logScope:
    curTime = state.curTime

  if not state.sentEodTimer:
    state.sentEodTimer = true
    result &= @[
      OutputEvent(kind: Timer, timer: TimerEvent(
        # Note: doesn't handle DST or early closes
        # Note: can't send MOC orders after 3:55 apparently
        timestamp: (state.curTime.toDateTime.format("yyyy-MM-dd") & "T19:54:45.000000000Z").parseTimestamp,
        tags: ["EOD-CLOSE"].toHashSet,
        name: "Closing out position to end the day flat")),
    ]

  # Consider using fusion pattern matching, and split on (State, EventKind)
  # Need to figure out why we sometimes have two orders out/fill for 200 shares

  case update.kind
  of Timer:
    {.noSideEffect.}:
      info "Got timer", timer=update.timer

    if state.state == EodDone:
      return

    if "EOD-CLOSE" in update.timer.tags and state.state != EodClose:
      result &= state.closeAllOpenOrders()
      result &= state.goToState(EodClose)

      if state.position > 0:
        result &= state.marketExitPosition()
      return

    if "RESET-STATE" in update.timer.tags:
      {.noSideEffect.}:
        info "Got reset state message from timer", curState=state.state, position=state.position, posVwap=state.positionVwap, posMktValue=state.calcPositionMktPrice(), stratPnl=state.stratPnl, fees=state.calculateTotalFees, pending=state.pendingOrders, opened=state.openOrders

      result &= state.closeAllOpenOrders()
      case state.state
      of ExitingPositionOptimistic, ExitingPositionPessimistic:
        if state.position > 0:
          if state.state == ExitingPositionOptimistic:
            result &= state.goToState(ExitingPositionPessimistic)
            result &= state.tryExitPosition(state.getPessimisticExitPrice)
            return
          else:
            result &= state.goToState(ExitingPositionOptimistic)
            result &= state.tryExitPosition(state.getIdealExitPrice)
            return
        else:
          result &= state.goToState(WaitingForMomentum)
      of WaitingForMomentum, WaitingForFill, EodClose, EodDone:
        discard


  of MarketData:
    if update.md.kind == Quote:
      state.lastNbbo = some Nbbo(
        askPrice: update.md.askPrice,
        bidPrice: update.md.bidPrice,
        askSize: update.md.askSize,
        bidSize: update.md.bidSize,
        timestamp: update.md.timestamp,
      )

    case state.state
    of WaitingForMomentum:
      if update.md.kind == BarMinute:
        let newBar = update.md.bar
        if state.lastBar.isSome and newBar.lowPrice >= state.lastBar.get.lowPrice:
          inc state.numConsecIncreases
        state.lastBar = some newBar

        if state.numConsecIncreases > kNumRequiredBarIncreases:
          state.numConsecIncreases = 0
          result &= state.goToState(WaitingForFill)
          result &= state.tryEnterPosition(newBar.highPrice - Price(dollars: 0, cents: kCentsEnterDiscount))
          return

    of ExitingPositionOptimistic, ExitingPositionPessimistic, WaitingForFill, EodClose, EodDone:
      discard


  of OrderUpdate:
    case update.ou.kind
    of New:
      state.numRetries = 0
    of FilledFull:
      if state.state != EodDone and state.state != EodClose:
        if state.position > 0:
          result &= state.goToState(ExitingPositionOptimistic)
          result &= state.tryExitPosition(state.getIdealExitPrice)
        else:
          # Just exited position, restart the cycle
          result &= state.goToState(WaitingForMomentum)
        return
    else:
      discard


  of CommandFailed:
    case update.cmd.kind
    of OrderSendFailed:
      {.noSideEffect.}:
        warn "Order send failed", cmd=update.cmd
      # Fallback or retry logic for failed order send
      try:
        let retryOrder = state.pendingOrders[update.cmd.clientOrderId]
        if state.numRetries < 3:
          inc state.numRetries
          result.add OutputEvent(kind: OrderSend, clientOrderId: state.makeOrderId(),
                                  side: retryOrder.side, quantity: retryOrder.size,
                                  price: retryOrder.price, orderKind: retryOrder.kind, tif: retryOrder.tif)
        else:
          {.noSideEffect.}:
            warn "Max order send retries reached, not retrying", orderId=update.cmd.clientOrderId, pending=state.pendingOrders, opened=state.openOrders
          result &= state.goToState(WaitingForMomentum)
          state.numRetries = 0
      except KeyError:
        {.noSideEffect.}:
          error "Unable to find failed order in pending orders list", clientId=update.cmd.clientOrderId, pending=state.pendingOrders, opened=state.openOrders
        result &= state.goToState(WaitingForMomentum)
        return

    of OrderCancelFailed:
      {.noSideEffect.}:
        warn "Order cancel failed", orderId=update.cmd.idToCancel, pending=state.pendingOrders, opened=state.openOrders
      # Retry logic for failed order cancel
      # This example does not implement a retry count check for cancel failures
      # but it's recommended to include such a mechanism to avoid potential infinite loops
      if state.numRetries < 3:
        inc state.numRetries
        result.add OutputEvent(kind: OrderCancel, idToCancel: update.cmd.idToCancel)
      else:
        {.noSideEffect.}:
          warn "Max order cancel retries reached, not retrying", orderId=update.cmd.clientOrderId, pending=state.pendingOrders, opened=state.openOrders
        result &= state.goToState(WaitingForMomentum)
        state.numRetries = 0
