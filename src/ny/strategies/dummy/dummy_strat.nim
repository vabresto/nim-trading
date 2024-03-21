## This is a simple momentum strategy., mostly just a tech demo
## We wait for 3 consecutive minute bars of monotonically increasing prices (low and high?)
## Then we send a limit order to buy 100 shares (what price do we use?)
## If we don't get any fills after 15 minutes (arbitrary), reset to the waiting state
## If we do get fills, try to exit (no trailing stop implemented yet, so we'll just go for a fixed price increase for now)
## Maybe consider having a close position at end of day state

import std/math
import std/options
import std/strutils
import std/tables
import std/times

import chronicles

import ny/core/md/md_types
import ny/core/types/md/bar_details
import ny/core/types/order
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
    ExitingPosition
    EodClose

  DummyStrategyState* = object of StrategyBase
    state: StateKind = WaitingForMomentum
    curTime: Timestamp

    sentEodTimer: bool = false
    
    numConsecIncreases: int = 0
    lastBar: Option[BarDetails]

    # placeholder for now to sort of simulate end of day
    curEventNum: int = 0
    noMdLoopNum: int = 0

    position: int = 0
    positionCost: Price
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


func initDummyStrategy*(orderIdBase: string): DummyStrategyState =
  DummyStrategyState(
    orderIdBase: orderIdBase,
    pendingOrders: initTable[ClientOrderId, SysOrder](),
    openOrders: initTable[OrderId, SysOrder](),
  )


func makeOrderId(state: var DummyStrategyState): ClientOrderId =
  inc state.numOrdersSent
  (state.orderIdBase & "dummy:o-" & $state.numOrdersSent).ClientOrderId


func calculateTotalFees*(state: var DummyStrategyState): tuple[regFee: Price, tafFee: Price] =
  # https://alpaca.markets/blog/reg-taf-fees/
  let regFee = ceil(state.stratTotalNotionalSold.inCents.float * (8 / 1_000_000))
  let tafFee = state.stratTotalSharesSold / 1_000_000 * 166
  ((regFee/100).parsePrice, tafFee.parsePrice)


func removeOrder(state: var DummyStrategyState, update: InputEvent) =
  {.noSideEffect.}:
    trace "Closing order", id=update.ou.orderId
  
  if update.ou.orderId in state.openOrders:
    state.openOrders.del update.ou.orderId
    inc state.numOrdersClosed        
  else:
    {.noSideEffect.}:
      error "Trying to close missing order!", cur=state.openOrders[update.ou.orderId], event=update


func handleFill(state: var DummyStrategyState, update: InputEvent) =
  let fillAmt = update.ou.fillAmt
  let fillPrice = update.ou.fillPrice
  let eventPrice = fillPrice * fillAmt

  try:
    var order = state.openOrders[update.ou.orderId]
    case order.side
    of Buy:
      state.stratTotalSharesBought += fillAmt
      state.stratTotalNotionalBought += eventPrice
      state.position += fillAmt
      state.stratPnl -= eventPrice
      # For buys, we update the average price we bought at
      # Note that this logic doesn't work if we can intermix buys and sells
      state.positionCost += eventPrice
      state.positionVwap = ((state.positionCost.dollars * 100 + state.positionCost.cents) / state.position) / 100
    of Sell:
      state.stratTotalSharesSold += fillAmt
      state.stratTotalNotionalSold += eventPrice
      state.position -= fillAmt
      state.stratPnl += eventPrice
      # For sells, if we end up at 0, we can reset our vwap
      if state.position == 0:
        state.positionVwap = 0.float
        state.positionCost = Price(dollars: 0, cents: 0)
    order.cumSharesFilled += fillAmt
  except KeyError:
    {.noSideEffect.}:
      error "Failed to update fill amount!", event=update, state


func executeDummyStrategy*(state: var DummyStrategyState, update: InputEvent): seq[OutputEvent] {.raises: [].} =
  {.noSideEffect.}:
    debug "Strategy got event", update, ts=update.timestamp, state

  inc state.curEventNum
  state.curTime = update.timestamp

  if not state.sentEodTimer:
    state.sentEodTimer = true
    result &= @[
      OutputEvent(kind: Timer, timer: TimerEvent(
        # Note: doesn't handle DST or early closes
        # Note: can't send MOC orders after 3:55 apparently
        timestamp: (state.curTime.toDateTime.format("yyyy-MM-dd") & "T19:54:45.000000000Z").parseTimestamp,
        name: "[EOD-CLOSE] Closing out position to end the day flat")),
    ]

  # This is not ideal, but it gives us a way to stop the strategy, especially in sim mode
  # We don't send enough events to trigger the stop normally either, so this seems acceptable but not ideal
  if update.kind != MarketData:
    inc state.noMdLoopNum
  else:
    state.noMdLoopNum = 0
  if state.noMdLoopNum > 10:
    # TODO: Once implemented, send a market order to sell out the rest of the position here
    {.noSideEffect.}:
      info "Hit max events; closing out", eventNum=state.curEventNum
    return

  logScope:
    curTime = state.curTime

  case update.kind
  of Timer:
    {.noSideEffect.}:
      debug "Got timer", timer=update.timer

    if "[EOD-CLOSE]" in update.timer.name:
      state.state = EodClose
      {.noSideEffect.}:
        info "Got EOD close message from timer", curState=state.state, position=state.position, posValue=state.positionCost, stratPnl=state.stratPnl, fees=state.calculateTotalFees

      for id in state.openOrders.keys:
        result &= OutputEvent(kind: OrderCancel, idToCancel: id)
        {.noSideEffect.}:
          debug "Sending order cancel event", id

      # If we had any fills, go to exit, otherwise, back to wait for momentum
      if state.position > 0:
        let clientOrderId = state.makeOrderId
        let order = SysOrder(
          id: "---PENDING---".OrderId,
          clientOrderId: clientOrderId,
          side: Sell,
          kind: Market,
          tif: ClosingAuction,
          size: state.position,
        )
        state.pendingOrders[clientOrderId] = order
        result &= @[
          OutputEvent(kind: OrderSend, clientOrderId: clientOrderId, side: order.side, quantity: order.size, price: order.price, orderKind: Market, tif: ClosingAuction),
        ]

    if state.state == EodClose:
      return

    if "[RESET-STATE]" in update.timer.name:
      {.noSideEffect.}:
        info "Got reset state message from timer", curState=state.state, position=state.position, posValue=state.positionCost, stratPnl=state.stratPnl, fees=state.calculateTotalFees

      for id in state.openOrders.keys:
        result &= OutputEvent(kind: OrderCancel, idToCancel: id)
        {.noSideEffect.}:
          debug "Sending order cancel event", id

      # If we had any fills, go to exit, otherwise, back to wait for momentum
      if state.position > 0:
        state.state = ExitingPosition
        let clientOrderId = state.makeOrderId
        let price = (state.positionVwap * 1.005).parsePrice # try to take 0.5% in profit
        {.noSideEffect.}:
          debug "Trying to exit at price", price
        let order = SysOrder(
          id: "---PENDING---".OrderId,
          clientOrderId: clientOrderId,
          side: Sell,
          kind: Limit,
          tif: Day,
          size: state.position,
          price: price,
        )
        state.pendingOrders[clientOrderId] = order
        result &= @[
          OutputEvent(kind: OrderSend, clientOrderId: clientOrderId, side: order.side, quantity: order.size, price: order.price, orderKind: Limit, tif: Day),
          OutputEvent(kind: Timer, timer: TimerEvent(timestamp: state.curTime + initDuration(seconds=120), name: "[RESET-STATE] Waiting for exit expired; try again")),
        ]
      else:
        state.state = WaitingForMomentum
        state.numConsecIncreases = 0

  of MarketData:
    if update.kind == MarketData and update.md.kind == BarMinute:
      {.noSideEffect.}:
        trace "Strategy got bar", update, state=state.state

    case state.state
    of WaitingForMomentum:
      if update.kind == MarketData and update.md.kind == BarMinute:
        let newBar = update.md.bar
        if state.lastBar.isSome and newBar.lowPrice >= state.lastBar.get.lowPrice:
          inc state.numConsecIncreases
        state.lastBar = some newBar

        if state.numConsecIncreases > kNumRequiredBarIncreases:
          {.noSideEffect.}:
            info "Strategy got 3rd consec increase", update, stratPnl=state.stratPnl
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
            price: newBar.highPrice - Price(dollars: 0, cents: kCentsEnterDiscount),
            # price: newBar.highPrice, # for debug
          )
          state.pendingOrders[clientOrderId] = order
          result &= @[
            OutputEvent(kind: OrderSend, clientOrderId: clientOrderId, side: order.side, quantity: order.size, price: order.price, orderKind: Limit, tif: Day),
            OutputEvent(kind: Timer, timer: TimerEvent(timestamp: state.curTime + initDuration(seconds=120), name: "[RESET-STATE] Waiting for fill expired; restart"))
          ]
          return

    of WaitingForFill, EodClose:
      discard
    of ExitingPosition:
      if state.position <= 0:
        state.state = WaitingForMomentum
        state.numConsecIncreases = 0
        {.noSideEffect.}:
          info "Fully exited position, going to WaitingForMomentum"
          return
      
      # Have some position
      if state.pendingOrders.len == 0 and state.openOrders.len == 0:
        # No open orders, let's send an order to fully close out our position
        let clientOrderId = state.makeOrderId
        let price = (state.positionVwap * 1.005).parsePrice # try to take 0.5% in profit
        {.noSideEffect.}:
          debug "Trying to exit at price", price
        let order = SysOrder(
          id: "---PENDING---".OrderId,
          clientOrderId: clientOrderId,
          side: Sell,
          kind: Limit,
          tif: Day,
          size: state.position,
          price: price,
        )
        state.pendingOrders[clientOrderId] = order
        result &= @[
            OutputEvent(kind: OrderSend, clientOrderId: clientOrderId, side: order.side, quantity: order.size, price: order.price, orderKind: Limit, tif: Day),
            OutputEvent(kind: Timer, timer: TimerEvent(timestamp: state.curTime + initDuration(seconds=120), name: "[RESET-STATE] Waiting for fill expired; restart")),
          ]
        return


  of OrderUpdate:
    {.noSideEffect.}:
      trace "Strategy got order update event", update, ts=update.timestamp
    
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
      {.noSideEffect.}:
        info "Got partial fill", event=update, position=state.position, posValue=state.positionCost, stratPnl=state.stratPnl
      state.handleFill(update)
    of FilledFull:
      {.noSideEffect.}:
        info "Got full fill", event=update, position=state.position, posValue=state.positionCost, stratPnl=state.stratPnl
      state.handleFill(update)
      state.removeOrder(update)
    of Cancelled:
      state.removeOrder(update)
    of Ack:
      {.noSideEffect.}:
        info "Got ack", event=update
    of CancelPending:
      {.noSideEffect.}:
          error "Got unhandled order event!", event=update
