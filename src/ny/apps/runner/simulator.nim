import std/heapqueue
import std/options
import std/times

import chronicles
import db_connector/db_postgres
import fusion/matching

import ny/apps/runner/sim_md
import ny/core/db/mddb
import ny/core/env/envs
import ny/core/md/alpaca/types
import ny/apps/runner/strategy
import ny/apps/runner/types

type
  Simulator* = object
    db*: DbConn

    curTime: float
    timers: HeapQueue[TimerEvent]
    scheduledOrderUpdates: HeapQueue[OrderUpdateEvent]

    timerItr: iterator(sim: var Simulator): Option[TimerEvent]{.closure, gcsafe.}
    mdItr: iterator(): Option[AlpacaMdWsReply]{.closure, gcsafe.}
    ouItr: iterator(sim: var Simulator): Option[OrderUpdateEvent]{.closure, gcsafe.}

  Nbbo* = object
    askPrice*: float
    bidPrice*: float
    askSize*: int
    bidSize*: int
    timestamp*: string
    # quote condition, tape could also be relevant
    

proc `<`(a, b: OrderUpdateEvent): bool = a.timestamp < b.timestamp

proc createEmptyTimerIterator(): auto =
  (iterator(sim: var Simulator): Option[TimerEvent] {.closure, gcsafe.} =
    while true:
      let res = if sim.timers.len > 0:
        some sim.timers.pop()
      else:
        none[TimerEvent]()
      yield res
    error "End of timer iterator?"
  )

proc createEmptyOrderUpdateIterator(): auto =
  (iterator(sim: var Simulator): Option[OrderUpdateEvent] {.closure, gcsafe.} =
    # var returnedTheFill = false
    while true:
      let res = if sim.scheduledOrderUpdates.len > 0:
        some sim.scheduledOrderUpdates.pop()
      else:
        none[OrderUpdateEvent]()
      yield res

      # For now to test, just hard code returning a fill
      # if not returnedTheFill:
      #   returnedTheFill = true
      #   let res = some OrderUpdateEvent(
      #     orderId: "external-id",
      #     clientOrderId: "order-1",
      #     timestamp: "2024-03-15T03:15:48.300000000Z",
      #     kind: FilledFull,
      #     fillAmt: 1,
      #   )
      #   yield res
      # else:
      #   return none[OrderUpdateEvent]()
    error "End of order update iterator?"
  )

proc initSimulator*(): Simulator =
  let date = dateTime(2024, mMar, 15)
  let db = getMdDb(loadOrQuit("MD_PG_HOST"), loadOrQuit("MD_PG_USER"), loadOrQuit("MD_PG_PASS"), loadOrQuit("MD_PG_NAME"))

  Simulator(
    db: db,
    curTime: 0.float,
    timers: initHeapQueue[TimerEvent](),
    timerItr: createEmptyTimerIterator(),
    mdItr: createMarketDataIterator(db, "FAKEPACA", date),
    ouItr: createEmptyOrderUpdateIterator(),
  )


proc getNextTimerEvent(sim: var Simulator): Option[TimerEvent] =
  sim.timerItr(sim)

proc getNextMarketDataEvent(sim: Simulator): Option[AlpacaMdWsReply] =
  if not finished(sim.mdItr):
    sim.mdItr()
  else:
    none[AlpacaMdWsReply]()

proc getNextOrderUpdateEvent(sim: var Simulator): Option[OrderUpdateEvent] =
  sim.ouItr(sim)

proc addTimer*(sim: var Simulator, timer: TimerEvent) =
  # info "Pushing timer"
  sim.timers.push timer


{.experimental: "caseStmtMacros".}
proc createEventIterator*(): auto =
  (iterator(sim: var Simulator): ResponseMessage =
    var nextTimerEvent = sim.getNextTimerEvent()
    var nextMdEvent = sim.getNextMarketDataEvent()
    var nextOuEvent = sim.getNextOrderUpdateEvent()

    var doneLooping = false

    info "Starting event loop ..."

    while true:
      if doneLooping:
        break

      if nextTimerEvent.isNone:
        nextTimerEvent = sim.getNextTimerEvent()
      if nextOuEvent.isNone:
        nextOuEvent = sim.getNextOrderUpdateEvent()

      let discriminator = (nextTimerEvent, nextMdEvent, nextOuEvent)
      # info "Looking", discriminator

      # info "Simulator", sim, discriminator

      case discriminator:

      # 
      # All null
      # 
      of (None(), None(), None()):
        info "Done iterating events"
        doneLooping = true
        continue

      # 
      # Single non-null
      # 
      of (Some(@timeEv), None(), None()):
        # info "Returning timer event by elimination"
        yield ResponseMessage(kind: Timer, timer: nextTimerEvent.get)
        nextTimerEvent = sim.getNextTimerEvent()
      of (None(), Some(@mdEv), None()):
        # info "Returning market data event by elimination"
        yield ResponseMessage(kind: MarketData, md: nextMdEvent.get)
        nextMdEvent = sim.getNextMarketDataEvent()
      of (None(), None(), Some(@ouEv)):
        # info "Returning order update event by elimination"
        yield ResponseMessage(kind: OrderUpdate, ou: nextOuEvent.get)
        nextOuEvent = sim.getNextOrderUpdateEvent()
      
      # 
      # Two non-nulls
      # 
      of (Some(@timeEv), Some(@mdEv), None()):
        if mdEv.getTimestamp.isNone or timeEv.at < mdEv.getTimestamp.get:
          yield ResponseMessage(kind: Timer, timer: nextTimerEvent.get)
          nextTimerEvent = sim.getNextTimerEvent()
        else:
          yield ResponseMessage(kind: MarketData, md: nextMdEvent.get)
          nextMdEvent = sim.getNextMarketDataEvent()
      
      of (None(), Some(@mdEv), Some(@ouEv)):
        if mdEv.getTimestamp.isNone or ouEv.timestamp < mdEv.getTimestamp.get:
          yield ResponseMessage(kind: OrderUpdate, ou: nextOuEvent.get)
          nextOuEvent = sim.getNextOrderUpdateEvent()
        else:
          yield ResponseMessage(kind: MarketData, md: nextMdEvent.get)
          nextMdEvent = sim.getNextMarketDataEvent()

      of (Some(@timeEv), None(), Some(@ouEv)):
        if timeEv.at < ouEv.timestamp:
          yield ResponseMessage(kind: Timer, timer: nextTimerEvent.get)
          nextTimerEvent = sim.getNextTimerEvent()
        else:
          yield ResponseMessage(kind: OrderUpdate, ou: nextOuEvent.get)
          nextOuEvent = sim.getNextOrderUpdateEvent()

      # 
      # All non-null
      # 
      of (Some(@timeEv), Some(@mdEv), Some(@ouEv)):
        # Kinda arbitrary, but don't want to deal with the none
        # Really should refactor this so the type is non-optional
        if mdEv.getTimestamp.isNone:
          yield ResponseMessage(kind: MarketData, md: nextMdEvent.get)
          nextMdEvent = sim.getNextMarketDataEvent()

        let next = min([timeEv.at, ouEv.timestamp, mdEv.getTimestamp.get.string])
        if next == timeEv.at:
          yield ResponseMessage(kind: Timer, timer: nextTimerEvent.get)
          nextTimerEvent = sim.getNextTimerEvent()
        elif next == ouEv.timestamp:
          yield ResponseMessage(kind: OrderUpdate, ou: nextOuEvent.get)
          nextOuEvent = sim.getNextOrderUpdateEvent()
        else:
          yield ResponseMessage(kind: MarketData, md: nextMdEvent.get)
          nextMdEvent = sim.getNextMarketDataEvent()
        discard
      discard

    discard
  )


proc simulate*(sim: var Simulator) =
  info "Creating event iterator ..."
  let eventItr = createEventIterator()
  info "Running sim ..."

  var nbbo = none[Nbbo]()

  var strategyState = 0
  for ev in eventItr(sim):
    # info "Got event", ev

    case ev.kind
    of MarketData:
      case ev.md.kind
      of Quote:
        nbbo = some Nbbo(
          askPrice: ev.md.quote.askPrice,
          bidPrice: ev.md.quote.bidPrice,
          askSize: ev.md.quote.askSize,
          bidSize: ev.md.quote.bidSize,
          timestamp: ev.md.quote.timestamp,
        )
        # info "Got quote", nbbo
      else:
        discard
    of Timer, OrderUpdate:
      discard

    let cmds = strategyState.executeStrategy(ev)
    # info "Got replies", cmds
    for cmd in cmds:
      case cmd.kind
      of Timer:
        sim.addTimer(cmd.timer)
      of OrderSend:
        # warn "Strategy sent order send command; not implemented yet", cmd
        sim.scheduledOrderUpdates.push OrderUpdateEvent(
          orderId: "",
          clientOrderId: cmd.clientOrderId,
          timestamp: "2024-03-15T03:15:48.300000000Z",
          kind: FilledPartial,
          fillAmt: 1,
        )
      of OrderCancel:
        warn "Strategy sent order cancel command; not implemented yet", cmd
