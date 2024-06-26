## # Overview
## 
## The inspector modules are similar to the heartbeat modules, but used to communicate information about the
## strategy that is currently running. This can be extended to feed other data to the monitor system as well.
## 
## 
## This is implemented by the strategies. In contrast with the heartbeats, the inspector stats are pushed by
## the strategies, instead of pulled by the monitor service.
## 
## 
## Format:
## { base: {}, strategy: {} }
## 
## 
## Base has all of the strategy base attributes (common attributes), and strategy has all of the strategy specific attributes (ex. strategy state)

import std/json
import std/net
import std/options

import chronicles except toJson
import jsony

import ny/core/types/strategy_base
import ny/core/types/timestamp
import ny/core/utils/sim_utils
import ny/core/inspector/shared


type
  PushMessage* = object
    base: StrategyBase
    strategy: JsonNode
    date: string
    symbol: string
    isSim: bool
    timestamp: Timestamp


proc getMonitorSocket*(monitorAddress: Option[string], monitorPort: Option[Port] = some kMonitorServerPort): Option[Socket] {.raises: [].} =
  try:
    if monitorAddress.isSome and monitorPort.isSome:
      var monSock = newSocket()
      monSock.connect(monitorAddress.get, monitorPort.get)
      info "Connected to monitoring socket"
      some monSock
    else:
      debug "No monitoring socket requested; non created", monitorAddress, monitorPort
      none[Socket]()
  except OSError, SslError:
    error "Failed to create monitor socket", err=getCurrentExceptionMsg()
    none[Socket]()


proc initPushMessage*(base: StrategyBase, date: string, strategy: JsonNode, symbol: string): PushMessage =
  PushMessage(base: base, strategy: strategy, date: date, symbol: symbol, isSim: isSimuluation(), timestamp: getNowUtc())


proc pushStrategyState*(msg: PushMessage, socket: Socket) =
  socket.send(msg.toJson() & "\n", maxRetries=3)
