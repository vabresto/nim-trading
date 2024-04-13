import std/net
import std/options
import std/os
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
  ## This function is the thread that runs the actual trading strategy. It handles the IO for the
  ## strategy (which itself runs as a pure/side-effect-free function).

  dynamicLogScope(symbol=args.symbol):
    let monSock = block:
      var retriesLeft = 5
      var monSock = getMonitorSocket(args.monitorAddress, args.monitorPort)
      while retriesLeft > 0:
        dec retriesLeft
        if monSock.isSome:
          break
        if retriesLeft <= 0:
          break
        if monSock.isNone and args.monitorAddress.isSome and args.monitorPort.isSome:
          # Retry
          info "Retrying to connect to monitoring socket ...", retriesLeft
        sleep(5_000)
        monSock = getMonitorSocket(args.monitorAddress, args.monitorPort)
      monSock
    let oc = getTheOutputChannel()
    let ic = block:
      try:
        {.gcsafe.}:
          getChannelForSymbol(args.symbol)
      except KeyError:
        error "Failed to initialize runner; quitting", args, err=getCurrentExceptionMsg()
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
          error "Failed to send request!", resp, err=getCurrentExceptionMsg()

      if resps.len > 0 and monSock.isSome:
        try:
          initPushMessage(base = strategy, strategy = %*strategy, date = dateStr, symbol = args.symbol).pushStrategyState(monSock.get)
        except OSError, SslError:
          error "Failed to push strategy state update message to monitoring socket", err=getCurrentExceptionMsg()
