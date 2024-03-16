import std/heapqueue
import std/options
import std/times

import chronicles
import db_connector/db_postgres
import fusion/matching

import ny/apps/runner/simulated/market_data
import ny/core/db/mddb
import ny/core/env/envs
import ny/core/md/alpaca/types
import ny/core/md/md_types
import ny/apps/runner/types
import ny/core/types/timestamp
import ny/apps/runner/simulated/matching_engine
import ny/apps/runner/types
import ny/strategies/dummy/dummy_strat

type
  Simulator* = object
    db*: DbConn

    curTime: float
    timers: HeapQueue[TimerEvent]
    scheduledOrderUpdates: HeapQueue[OrderUpdateEvent]

    timerItr: iterator(sim: var Simulator): Option[TimerEvent]{.closure, gcsafe.}
    mdItr: iterator(): Option[MarketDataUpdate]{.closure, gcsafe.}
    ouItr: iterator(sim: var Simulator): Option[OrderUpdateEvent]{.closure, gcsafe.}


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
  sim.timers.push timer


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
      if nextMdEvent.isNone:
        nextMdEvent = sim.getNextMarketDataEvent()
      if nextOuEvent.isNone:
        nextOuEvent = sim.getNextOrderUpdateEvent()

      if nextTimerEvent.isNone and nextMdEvent.isNone and nextOuEvent.isNone:
        info "Done iterating events"
        doneLooping = true
        continue

      var timestamps = newSeq[Timestamp]()
      if nextTimerEvent.isSome:
        timestamps.add nextTimerEvent.get.at
      if nextMdEvent.isSome:
        timestamps.add nextMdEvent.get.timestamp
      if nextOuEvent.isSome:
        timestamps.add nextOuEvent.get.timestamp

      let nextEvTimestamp = min(timestamps)
      if nextTimerEvent.isSome and nextTimerEvent.get.at == nextEvTimestamp:
        yield ResponseMessage(kind: Timer, timer: nextTimerEvent.get)
        nextTimerEvent = sim.getNextTimerEvent()

      if nextMdEvent.isSome and nextMdEvent.get.timestamp == nextEvTimestamp:
        yield ResponseMessage(kind: MarketData, md: nextMdEvent.get)
        nextMdEvent = sim.getNextMarketDataEvent()

      if nextOuEvent.isSome and nextOuEvent.get.timestamp == nextEvTimestamp:
        yield ResponseMessage(kind: OrderUpdate, ou: nextOuEvent.get)
        nextOuEvent = sim.getNextOrderUpdateEvent()
    info "Done event loop"
  )


proc simulate*(sim: var Simulator) =
  info "Creating event iterator ..."
  let eventItr = createEventIterator()
  
  info "Init state ..."
  var matchingEngine = initSimMatchingEngine()
  var strategyState = initDummyStrategy()

  info "Running sim ..."
  for ev in eventItr(sim):

    # @next:
    # D wrap md events in a non-alpaca object
    # D add a timestamp field to all response msg events (and move away from string type for it)
    # D move most of the below logic to the matching engine
    # - create internal type wrappers for common data types
    # - implement the actual matching engine logic
    # - might be ready to start implementing dummy strategies at that point?

    case ev.kind
    of MarketData:
      case ev.md.kind
      of Quote:
        let resps = matchingEngine.onMarketDataEvent(ev.md)
        for resp in resps:
          sim.scheduledOrderUpdates.push resp
      else:
        discard
    of Timer, OrderUpdate:
      discard

    let cmds = strategyState.executeDummyStrategy(ev)

    for cmd in cmds:
      let resps = matchingEngine.onRequest(cmd)
      for resp in resps:
        sim.scheduledOrderUpdates.push resp
