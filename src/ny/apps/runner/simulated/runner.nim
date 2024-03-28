import std/heapqueue
import std/json
import std/net
import std/options
import std/times

import chronicles
import db_connector/db_postgres
import fusion/matching

import ny/apps/runner/simulated/market_data
import ny/apps/runner/simulated/matching_engine
import ny/core/db/mddb
import ny/core/env/envs
import ny/core/md/alpaca/types
import ny/core/md/md_types
import ny/core/types/strategy_base
import ny/core/types/timestamp
import ny/strategies/dummy/dummy_strat
import ny/core/inspector/client

logScope:
  topics = "sys sys:sim sim-runner"


type
  Simulator* = object
    db*: DbConn

    date: string
    symbol: string

    curTime: float
    timers: HeapQueue[TimerEvent]
    scheduledOrderUpdates: HeapQueue[SysOrderUpdateEvent]

    timerItr: iterator(sim: var Simulator): Option[TimerEvent]{.closure, gcsafe.}
    mdItr: iterator(): Option[MarketDataUpdate]{.closure, gcsafe.}
    ouItr: iterator(sim: var Simulator): Option[SysOrderUpdateEvent]{.closure, gcsafe.}

    monitorSocket: Option[Socket]


proc `<`(a, b: SysOrderUpdateEvent): bool = a.timestamp < b.timestamp


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
  (iterator(sim: var Simulator): Option[SysOrderUpdateEvent] {.closure, gcsafe.} =
    while true:
      let res = if sim.scheduledOrderUpdates.len > 0:
        some sim.scheduledOrderUpdates.pop()
      else:
        none[SysOrderUpdateEvent]()
      yield res
    error "End of order update iterator?"
  )


proc initSimulator*(date: Datetime, symbol: string, monitorAddress: Option[string], monitorPort: Option[Port]): Simulator =
  let db = getMdDb(loadOrQuit("MD_PG_HOST"), loadOrQuit("MD_PG_USER"), loadOrQuit("MD_PG_PASS"), loadOrQuit("MD_PG_NAME"))

  Simulator(
    db: db,
    date: date.format("yyyy-MM-dd"),
    symbol: symbol,
    curTime: 0.float,
    timers: initHeapQueue[TimerEvent](),
    timerItr: createEmptyTimerIterator(),
    mdItr: createMarketDataIterator(db, symbol, date),
    ouItr: createEmptyOrderUpdateIterator(),
    monitorSocket: getMonitorSocket(monitorAddress, monitorPort),
  )


proc getNextTimerEvent(sim: var Simulator): Option[TimerEvent] =
  sim.timerItr(sim)


proc getNextMarketDataEvent(sim: Simulator): Option[MarketDataUpdate] =
  if not finished(sim.mdItr):
    sim.mdItr()
  else:
    none[MarketDataUpdate]()


proc getNextOrderUpdateEvent(sim: var Simulator): Option[SysOrderUpdateEvent] =
  sim.ouItr(sim)


proc addTimer*(sim: var Simulator, timer: TimerEvent) =
  sim.timers.push timer


proc createEventIterator*(): auto =
  (iterator(sim: var Simulator): InputEvent =
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
        timestamps.add nextTimerEvent.get.timestamp
      if nextMdEvent.isSome:
        timestamps.add nextMdEvent.get.timestamp
      if nextOuEvent.isSome:
        timestamps.add nextOuEvent.get.timestamp

      let nextEvTimestamp = min(timestamps)
      if nextTimerEvent.isSome and nextTimerEvent.get.timestamp == nextEvTimestamp:
        yield InputEvent(kind: Timer, timer: nextTimerEvent.get)
        nextTimerEvent = sim.getNextTimerEvent()

      if nextMdEvent.isSome and nextMdEvent.get.timestamp == nextEvTimestamp:
        yield InputEvent(kind: MarketData, md: nextMdEvent.get)
        nextMdEvent = sim.getNextMarketDataEvent()

      if nextOuEvent.isSome and nextOuEvent.get.timestamp == nextEvTimestamp:
        yield InputEvent(kind: OrderUpdate, ou: nextOuEvent.get)
        nextOuEvent = sim.getNextOrderUpdateEvent()
    
    info "Done event loop"
    if sim.monitorSocket.isSome:
      sim.monitorSocket.get.close()
      info "Closed monitoring socket"
  )


proc simulate*(sim: var Simulator) =
  info "Creating event iterator ..."
  let eventItr = createEventIterator()
  
  info "Init state ..."
  var matchingEngine = initSimMatchingEngine()
  var strategy = initDummyStrategy("dummy", "sim:")

  info "Running sim ..."
  for msg in eventItr(sim):

    if sim.curTime > msg.timestamp.toTime.toUnixFloat:
      warn "Simulator got event in the past ?!", simTime=sim.curTime, evtTime=msg.timestamp, msg
      continue
    sim.curTime = msg.timestamp.toTime.toUnixFloat

    case msg.kind
    of MarketData:
      case msg.md.kind
      of Quote, BarMinute:
        let resps = matchingEngine.onMarketDataEvent(msg.md)
        for resp in resps:
          case resp.kind
          of Timer:
            sim.addTimer(resp.timer)
          of OrderUpdate:
            sim.scheduledOrderUpdates.push resp.ou
          of MarketData:
            error "Got market data event from matchingEngine.onMarketDataEvent ?!", event=resp
          of CommandFailed:
            error "Requested command failed from matchingEngine.onMarketDataEvent", event=resp
      else:
        debug "Got filtered market data event", msg
        discard
    of Timer:
      matchingEngine.curTime = msg.timer.timestamp
    of OrderUpdate:
      warn "No action taken for order update"
      discard
    of CommandFailed:
      warn "No action taken for command failed"
      discard

    strategy.handleInputEvent(msg)
    let cmds = strategy.executeDummyStrategy(msg)
    strategy.pruneDoneOrders()
    for cmd in cmds:
      info "Strategy sent command", cmd
      strategy.handleOutputEvent(cmd)
      let resps = matchingEngine.onRequest(cmd)
      for resp in resps:
        case resp.kind
        of Timer:
          sim.addTimer(resp.timer)
        of OrderUpdate:
          sim.scheduledOrderUpdates.push resp.ou
        of MarketData:
          error "Got market data event from matchingEngine.onRequest ?!", event=resp
        of CommandFailed:
          error "Requested command failed from matchingEngine.onRequest", event=resp

    if cmds.len > 0 and sim.monitorSocket.isSome:
      initPushMessage(base = strategy, strategy = %*strategy, date = sim.date, symbol = sim.symbol).pushStrategyState(sim.monitorSocket.get)
