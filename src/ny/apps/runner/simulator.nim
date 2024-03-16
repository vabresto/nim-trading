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

import ny/apps/runner/types

type
  Simulator* = object
    db*: DbConn

    curTime: float
    timers: HeapQueue[TimerEvent]

    timerItr: iterator(sim: var Simulator): Option[TimerEvent]{.closure, gcsafe.}
    mdItr: iterator(): Option[AlpacaMdWsReply]{.closure, gcsafe.}
    ouItr: iterator(): Option[OrderUpdateEvent]{.closure, gcsafe.}
    

proc createEmptyTimerIterator(): auto =
  (iterator(sim: var Simulator): Option[TimerEvent] {.closure, gcsafe.} =
    # info "Sim", sim
    while true:
      # info "Popping timer"
      let res = if sim.timers.len > 0:
        some sim.timers.pop()
      else:
        none[TimerEvent]()
      yield res
    error "End of timer iterator?"
  )

proc createEmptyOrderUpdateIterator(): auto =
  (iterator(): Option[OrderUpdateEvent] {.closure, gcsafe.} =
    none[OrderUpdateEvent]()
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

proc getNextOrderUpdateEvent(sim: Simulator): Option[OrderUpdateEvent] =
  if not finished(sim.ouItr):
    sim.ouItr()
  else:
    none[OrderUpdateEvent]()


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
          # info "Returning timer event by elimination (1)"
          yield ResponseMessage(kind: Timer, timer: nextTimerEvent.get)
          nextTimerEvent = sim.getNextTimerEvent()
        else:
          # info "Returning market data event by elimination"
          yield ResponseMessage(kind: MarketData, md: nextMdEvent.get)
          nextMdEvent = sim.getNextMarketDataEvent()
      
      # of (None(), Some(@mdEv), None()):
      #   info "Returning market data event by elimination"
      #   # yield nextMdEvent.get
      #   nextMdEvent = sim.getNextMarketDataEvent()
      # of (None(), None(), Some(@ouEv)):
      #   info "Returning order update event by elimination"
      #   # yield nextOuEvent.get
      #   nextOuEvent = sim.getNextOrderUpdateEvent()


      # 
      # All non-null
      # 
      of (Some(@timeEv), Some(@mdEv), Some(@ouEv)):
        discard
      discard

    discard
  )
