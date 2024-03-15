import std/options
import std/tables

import chronicles
import threading/channels

import ny/apps/runner/timer_types
import ny/apps/runner/types


var gChannels = initTable[string, tuple[ic: Chan[ResponseMessage], oc: Chan[RequestMessage]]]()
var gTimerChan = none[Chan[TimerChanMsg]]()


proc initChannelsForSymbol*(symbol: string) =
  gChannels[symbol] = (ic: newChan[ResponseMessage](), oc: newChan[RequestMessage]())


proc getChannelsForSymbol*(symbol: string): tuple[ic: Chan[ResponseMessage], oc: Chan[RequestMessage]] =
  if symbol notin gChannels:
    initChannelsForSymbol(symbol)
  
  return gChannels[symbol]


proc getTimerChannel*(): Chan[TimerChanMsg] =
  if gTimerChan.isNone:
    info "Timer channel requested but none exists, creating a new one"
    gTimerChan = some newChan[TimerChanMsg]()
  gTimerChan.get
