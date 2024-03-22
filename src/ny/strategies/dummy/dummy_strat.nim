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

import ny/core/md/md_types
import ny/core/types/md/bar_details
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
    lastBar: Option[BarDetails]


func initDummyStrategy*(orderIdBase: string): DummyStrategyState =
  result.initStrategyBase(orderIdBase)


func closeAllOpenOrders(state: var DummyStrategyState): seq[OutputEvent] {.raises: [].} =
  for id in state.openOrders.keys:
    result &= OutputEvent(kind: OrderCancel, idToCancel: id)
    {.noSideEffect.}:
      debug "Sending order cancel event", id


func tryEnterPosition(state: var DummyStrategyState, price: Price): seq[OutputEvent] {.raises: [].} =
  result &= @[
    OutputEvent(kind: OrderSend, clientOrderId: state.makeOrderId, side: Buy, quantity: 100, price: price, orderKind: Limit, tif: Day),
    OutputEvent(kind: Timer, timer: TimerEvent(timestamp: state.curTime + initDuration(seconds=120), name: "[RESET-STATE] Waiting for fill expired; restart"))
  ]


func getIdealExitPrice(self: var DummyStrategyState): Price = 
  (self.positionVwap * 1.005).parsePrice # try to take 0.5% in profit


func getPessimisticExitPrice(self: var DummyStrategyState): Price = 
  Price(dollars: 0, cents: 0)


func tryExitPosition(self: var DummyStrategyState, price: Price): seq[OutputEvent] {.raises: [].} =
  if self.pendingOrders.len == 0 and self.numOpenOrders == 0:
    result &= @[
      OutputEvent(kind: OrderSend, clientOrderId: self.makeOrderId, side: Sell, quantity: self.position, price: price, orderKind: Limit, tif: Day),
      OutputEvent(kind: Timer, timer: TimerEvent(timestamp: self.curTime + initDuration(seconds=120), name: "[RESET-STATE] Waiting for exit expired; try again")),
    ]
  else:
    result &= self.closeAllOpenOrders()
    result &= @[
      OutputEvent(kind: Timer, timer: TimerEvent(timestamp: self.curTime + initDuration(milliseconds=10), name: "[RESET-STATE][CLOSE] Trying to exit but had open orders; try again")),
    ]


func marketExitPosition(self: var DummyStrategyState): seq[OutputEvent] {.raises: [].} =
  if self.pendingOrders.len == 0 and self.numOpenOrders == 0:
    result &= @[
      OutputEvent(kind: OrderSend, clientOrderId: self.makeOrderId, side: Sell, quantity: self.position, orderKind: Market, tif: ClosingAuction),
    ]
  else:
    result &= self.closeAllOpenOrders()
    result &= @[
      OutputEvent(kind: Timer, timer: TimerEvent(timestamp: self.curTime + initDuration(milliseconds=10), name: "[RESET-STATE][CLOSE] Trying to market exit but had open orders; try again")),
    ]


func goToState(self: var DummyStrategyState, state: StateKind): seq[OutputEvent] {.raises: [].} =
  case state
  of WaitingForMomentum:
    if self.state == ExitingPositionOptimistic or self.state == ExitingPositionPessimistic:
      {.noSideEffect.}:
        info "Fully exited position, going to WaitingForMomentum"
    self.state = WaitingForMomentum
    self.numConsecIncreases = 0
  
  of WaitingForFill:
    {.noSideEffect.}:
      info "Strategy got 3rd consec increase", stratPnl=self.stratPnl
    self.numConsecIncreases = 0
    self.state = WaitingForFill
  
  of ExitingPositionOptimistic:
    self.state = ExitingPositionOptimistic

  of ExitingPositionPessimistic:
    if self.state != ExitingPositionOptimistic:
      {.noSideEffect.}:
        warn "Going to pessimistic exit but not in optimistic exit state", curState=self.state
    self.state = ExitingPositionPessimistic
  
  of EodClose:
    {.noSideEffect.}:
      info "Got EOD close message from timer", curState=self.state, position=self.position, posVwap=self.positionVwap, posMktValue=self.calcPositionMktPrice(), stratPnl=self.stratPnl, fees=self.calculateTotalFees

    # result &= self.closeAllOpenOrders()

    # # If we had any fills, go to exit, otherwise, back to wait for momentum
    # if self.position > 0 and self.pendingOrders.len == 0 and self.numOpenOrders == 0:
    #   result &= self.marketExitPosition()
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
        name: "[EOD-CLOSE] Closing out position to end the day flat")),
    ]

  case update.kind
  of Timer:
    {.noSideEffect.}:
      debug "Got timer", timer=update.timer

    if "[EOD-CLOSE]" in update.timer.name:
      result &= state.goToState(EodClose)

    if state.state == EodDone:
      return

    if "[RESET-STATE]" in update.timer.name:
      {.noSideEffect.}:
        info "Got reset state message from timer", curState=state.state, position=state.position, posVwap=state.positionVwap, posMktValue=state.calcPositionMktPrice(), stratPnl=state.stratPnl, fees=state.calculateTotalFees

      result &= state.closeAllOpenOrders()
      case state.state
      of WaitingForMomentum, EodDone:
        discard
      of ExitingPositionOptimistic, ExitingPositionPessimistic:
        if state.position > 0:
          if (state.state == ExitingPositionOptimistic or state.state == ExitingPositionPessimistic) and "[CLOSE]" notin update.timer.name:
            result &= state.goToState(ExitingPositionPessimistic)
            result &= state.tryExitPosition(state.getPessimisticExitPrice())
            return
          else:
            result &= state.goToState(ExitingPositionOptimistic)
            result &= state.tryExitPosition(state.getIdealExitPrice)
            return
        else:
          result &= state.goToState(WaitingForMomentum)
      of WaitingForFill:
        discard
      of EodClose:
        if state.position == 0:
          result &= state.goToState(EodDone)
        result &= state.marketExitPosition()


  of MarketData:
    # if update.kind == MarketData and update.md.kind == BarMinute:
    #   {.noSideEffect.}:
    #     info "Strategy got bar", update, state=state.state, curPrice=state.calcPositionMktPrice()

    case state.state
    of WaitingForMomentum:
      if update.kind == MarketData and update.md.kind == BarMinute:
        let newBar = update.md.bar
        if state.lastBar.isSome and newBar.lowPrice >= state.lastBar.get.lowPrice:
          inc state.numConsecIncreases
        state.lastBar = some newBar

        if state.numConsecIncreases > kNumRequiredBarIncreases:
          result &= state.goToState(WaitingForFill)
          result &= state.tryEnterPosition(newBar.highPrice - Price(dollars: 0, cents: kCentsEnterDiscount))
          return

    # of ExitingPositionOptimistic, ExitingPositionPessimistic:
    #   if state.position <= 0:
    #     result &= state.goToState(WaitingForMomentum)

    #   # Have some position
    #   result &= state.tryExitPosition(state.getIdealExitPrice)
    #   return

    # of EodClose:
    #   result &= state.tryExitPosition(state.getIdealExitPrice)
    #   return

    of ExitingPositionOptimistic, ExitingPositionPessimistic, EodClose, WaitingForFill, EodDone:
      discard


  of OrderUpdate:
    case update.ou.kind
    of FilledFull:
      if state.state != EodDone and state.state != EodClose:
        result &= state.goToState(ExitingPositionOptimistic)
        result &= state.tryExitPosition(state.getIdealExitPrice)
        return
    else:
      discard
