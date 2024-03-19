import std/os

import chronicles
import threading/channels
import std/isolation

import ny/apps/runner/live/chans
import ny/core/types/strategy_base
import ny/strategies/dummy/dummy_strat


logScope:
  topics = "sys sys:live live-runner"


type
  RunnerThreadArgs* = object
    symbol*: string


proc runner*(args: RunnerThreadArgs) {.thread, nimcall, raises: [].} =
  dynamicLogScope(symbol=args.symbol):
    let (ic, oc) = block:
      try:
        {.gcsafe.}:
          getChannelsForSymbol(args.symbol)
      except KeyError:
        error "Failed to initialize runner; quitting", args
        return

    var state = initDummyStrategy()

    while true:
      let msg = block:
        var msg: InputEvent
        if not ic.tryRecv(msg):
          # Add a sleep so we don't max out the cores
          # Obviously slows down trading but not practically an issue for this project
          sleep(1)
          continue
        msg
      
      trace "Got message", msg

      var req = state.executeDummyStrategy(msg)
      for item in req:
        try:
          trace "Strategy replied", msg, resp=item
          oc.send(isolate(item))
        except Exception:
          error "Failed to send request!", req
