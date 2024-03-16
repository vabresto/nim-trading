import chronicles
import threading/channels
import std/isolation

import ny/apps/runner/live/chans
import ny/apps/runner/types
# import ny/apps/runner/strategy
import ny/strategies/dummy/dummy_strat

type
  RunnerThreadArgs* = object
    symbol*: string


proc runner*(args: RunnerThreadArgs) {.thread, nimcall, raises: [], forbids: [MarketIoEffect].} =
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
      var msg: ResponseMessage
      if not ic.tryRecv(msg):
        continue
      msg
    
    info "Got message", msg

    var req = state.executeDummyStrategy(msg)
    for item in req:
      try:
        oc.send(isolate(item))
      except Exception:
        error "Failed to send request!", req
