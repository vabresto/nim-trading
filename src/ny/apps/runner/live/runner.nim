import std/net
import std/options
import std/json

import chronicles
import threading/channels

import ny/apps/runner/live/chan_types
import ny/apps/runner/live/chans
import ny/core/types/strategy_base
import ny/strategies/dummy/dummy_strat
import ny/core/types/timestamp
import ny/core/inspector/client


logScope:
  topics = "sys sys:live live-runner"


type
  RunnerThreadArgs* = object
    symbol*: string
    monitorAddress*: Option[string]
    monitorPort*: Option[Port]


proc runner*(args: RunnerThreadArgs) {.thread, nimcall, raises: [].} =
  dynamicLogScope(symbol=args.symbol):
    let monSock = getMonitorSocket(args.monitorAddress, args.monitorPort)
    let oc = getTheOutputChannel()
    let ic = block:
      try:
        {.gcsafe.}:
          getChannelForSymbol(args.symbol)
      except KeyError:
        error "Failed to initialize runner; quitting", args
        return

    let dateStr = getNowUtc().getDateStr()
    var strategy = initDummyStrategy("dummy", dateStr & ":" & args.symbol & ":")

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

      if resps.len > 0 and monSock.isSome:
        try:
          initPushMessage(base = strategy, strategy = %*strategy, symbol = args.symbol).pushStrategyState(monSock.get)
        except OSError, SslError:
          error "Failed to push strategy state update message to monitoring socket"
