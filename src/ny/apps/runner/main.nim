import std/os
import std/times

import chronicles
import db_connector/db_postgres
import threading/channels

import ny/apps/runner/live/chans
import ny/apps/runner/live/runner as live_runner
import ny/apps/runner/live/timer # used
import ny/apps/runner/live/timer_types
import ny/apps/runner/simulated/market_data
import ny/apps/runner/simulated/runner as sim_runner
import ny/core/db/mddb
import ny/core/env/envs
import ny/core/types/strategy_base


proc main(simulated: bool) =
  info "Running ..."
  try:
    if simulated:
      info "Starting SIMULATED runner ..."
      var sim = initSimulator()
      sim.simulate()
    else:
      info "Starting LIVE runner ..."
      let symbol = "AMD"

      createTimerThread()

      var runThread: Thread[RunnerThreadArgs]
      createThread(runThread, runner, RunnerThreadArgs(symbol: symbol))

      sleep(1000)
      info "Sending message"
      let (ic, oc) = getChannelsForSymbol(symbol)
      let tc = getTimerChannel()
      ic.send(InputEvent(kind: Timer))

      var resp: OutputEvent
      oc.recv(resp)
      info "Main got", resp

      if resp.kind == Timer:
        tc.send(TimerChanMsg(kind: CreateTimer, create: RequestTimer(timer: resp.timer)))
      
      sleep(1000)

      let db = getMdDb(loadOrQuit("MD_PG_HOST"), loadOrQuit("MD_PG_USER"), loadOrQuit("MD_PG_PASS"), loadOrQuit("MD_PG_NAME"))
      let mdItr = createMarketDataIterator(db, "FAKEPACA", dateTime(2024, mMar, 15))
      for row in mdItr():
        info "Got md", row
  
  except DbError:
    error "Failed to connect to db to start simulation", msg=getCurrentExceptionMsg()
  except Exception:
    error "Simulator raised generic exception", msg=getCurrentExceptionMsg()


when isMainModule:
  main(true)
