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
import ny/core/md/md_types
import ny/apps/runner/types
import ny/core/types/timestamp

type
  Simulator* = object
    db*: DbConn

    curTime: float
    timers: HeapQueue[TimerEvent]
    scheduledOrderUpdates: HeapQueue[OrderUpdateEvent]

    timerItr: iterator(sim: var Simulator): Option[TimerEvent]{.closure, gcsafe.}
    mdItr: iterator(): Option[MarketDataUpdate]{.closure, gcsafe.}
    ouItr: iterator(sim: var Simulator): Option[OrderUpdateEvent]{.closure, gcsafe.}

  Nbbo* = object
    askPrice*: float
    bidPrice*: float
    askSize*: int
    bidSize*: int
    timestamp*: Timestamp
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
    while true:
      let res = if sim.scheduledOrderUpdates.len > 0:
        some sim.scheduledOrderUpdates.pop()
      else:
        none[OrderUpdateEvent]()
      yield res
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

proc getNextMarketDataEvent(sim: Simulator): Option[MarketDataUpdate] =
  if not finished(sim.mdItr):
    sim.mdItr()
  else:
    none[MarketDataUpdate]()

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
        if timeEv.at < mdEv.timestamp:
          yield ResponseMessage(kind: Timer, timer: nextTimerEvent.get)
          nextTimerEvent = sim.getNextTimerEvent()
        else:
          yield ResponseMessage(kind: MarketData, md: nextMdEvent.get)
          nextMdEvent = sim.getNextMarketDataEvent()
      
      of (None(), Some(@mdEv), Some(@ouEv)):
        if ouEv.timestamp < mdEv.timestamp:
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
        let next = min([timeEv.at, ouEv.timestamp, mdEv.timestamp])
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

  var curTime: Timestamp
  var strategyState = 0
  for ev in eventItr(sim):
    # info "Got event", ev

    echo "CUR TIME: ", curTime

    # @next:
    # D wrap md events in a non-alpaca object
    # D add a timestamp field to all response msg events (and move away from string type for it)
    # - move most of the below logic to the matching engine
    # - implement the actual matching engine logic
    # - might be ready to start implementing dummy strategies at that point?

    case ev.kind
    of MarketData:
      case ev.md.kind
      of Quote:
        nbbo = some Nbbo(
          askPrice: ev.md.askPrice,
          bidPrice: ev.md.bidPrice,
          askSize: ev.md.askSize,
          bidSize: ev.md.bidSize,
          timestamp: ev.md.timestamp,
        )
        curTime = ev.md.timestamp
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
        # Send new; for now, we'll reuse timestamp to make life easier
        sim.scheduledOrderUpdates.push OrderUpdateEvent(
          orderId: "",
          clientOrderId: cmd.clientOrderId,
          timestamp: curTime,
          kind: New,
        )
        # First order we fill, second we let strategy cancel
        if cmd.clientOrderId == "order-1":
          sim.scheduledOrderUpdates.push OrderUpdateEvent(
            orderId: "",
            clientOrderId: cmd.clientOrderId,
            timestamp: "2024-03-15T03:15:48.300000000Z".parseTimestamp,
            kind: FilledPartial,
            fillAmt: 1,
          )
      of OrderCancel:
        sim.scheduledOrderUpdates.push OrderUpdateEvent(
          orderId: cmd.idToCancel,
          clientOrderId: "",
          timestamp: "2024-03-15T03:15:49.300000000Z".parseTimestamp,
          kind: Cancelled,
        )
