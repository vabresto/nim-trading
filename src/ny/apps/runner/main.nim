import std/os
import std/times

import chronicles
import db_connector/db_postgres
import threading/channels

import ny/apps/runner/chans
import ny/apps/runner/sim_md
import ny/apps/runner/strategy
import ny/apps/runner/timer
import ny/apps/runner/timer_types
import ny/apps/runner/types
import ny/core/db/mddb
import ny/core/env/envs
import ny/apps/runner/simulator
import ny/core/md/alpaca/types


proc main() =
  let symbol = "AMD"

  # createTimerThread()

  # var runThread: Thread[RunnerThreadArgs]
  # createThread(runThread, runner, RunnerThreadArgs(symbol: symbol))

  # sleep(1000)
  # info "Sending message"
  # let (ic, oc) = getChannelsForSymbol(symbol)
  # let tc = getTimerChannel()
  # ic.send(ResponseMessage(kind: Timer))

  # var resp: RequestMessage
  # oc.recv(resp)
  # info "Main got", resp

  # if resp.kind == Timer:
  #   tc.send(TimerChanMsg(kind: CreateTimer, create: RequestTimer(timer: resp.timer)))
  
  # sleep(1000)

  # let db = getMdDb(loadOrQuit("MD_PG_HOST"), loadOrQuit("MD_PG_USER"), loadOrQuit("MD_PG_PASS"), loadOrQuit("MD_PG_NAME"))
  # let mdItr = createMarketDataIterator(db, "FAKEPACA", dateTime(2024, mMar, 15))
  # for row in mdItr():
  #   info "Got md", row

  try:
    info "Starting sim ..."
    var sim = initSimulator()
    info "Creating event iterator ..."
    let eventItr = createEventIterator()
    info "Running sim ..."

    var state = 0
    for ev in eventItr(sim):
      info "Got event", ev
      let cmds = state.executeStrategy(ev)
      info "Got replies", cmds
      for cmd in cmds:
        case cmd.kind
        of Timer:
          sim.addTimer(cmd.timer)
        of MarketData, OrderUpdate:
          discard
  
  except DbError:
    error "Failed to connect to db to start simulation", msg=getCurrentExceptionMsg()
  except Exception:
    error "Simulator raised generic exception", msg=getCurrentExceptionMsg()


when isMainModule:
  main()
