import chronicles
import threading/channels
import std/isolation

import ny/apps/runner/live/chans
import ny/core/types/strategy_base
import ny/strategies/dummy/dummy_strat
import ny/core/types/timestamp
import ny/core/types/strategy_base


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

    let dateStr = getNowUtc().getDateStr()
    var strategy = initDummyStrategy(dateStr & ":" & args.symbol & ":")

    while true:
      let msg: InputEvent = ic.recv()
  
      trace "Got message", msg

      strategy.handleInputEvent(msg)
      var resps = strategy.executeDummyStrategy(msg)
      strategy.pruneDoneOrders()
      for resp in resps:
        try:
          trace "Strategy replied", msg, resp
          strategy.handleOutputEvent(resp)
          oc.send(isolate(resp))
        except Exception:
          error "Failed to send request!", resp
