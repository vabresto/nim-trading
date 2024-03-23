import chronicles
import threading/channels

import ny/apps/runner/live/chan_types
import ny/apps/runner/live/chans
import ny/core/types/strategy_base
import ny/strategies/dummy/dummy_strat
import ny/core/types/timestamp


logScope:
  topics = "sys sys:live live-runner"


type
  RunnerThreadArgs* = object
    symbol*: string


proc runner*(args: RunnerThreadArgs) {.thread, nimcall, raises: [].} =
  dynamicLogScope(symbol=args.symbol):
    let oc = getTheOutputChannel()
    let ic = block:
      try:
        {.gcsafe.}:
          getChannelForSymbol(args.symbol)
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
          oc.send(OutputEventMsg(symbol: args.symbol, event: resp))
        except Exception:
          error "Failed to send request!", resp
