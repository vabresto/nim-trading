import std/options
import std/rlocks
import std/tables

import chronicles
import threading/channels

import ny/apps/runner/live/timer_types
import ny/core/types/strategy_base

var gChanLock: RLock
var gChannels {.guard: gChanLock.} = initTable[string, tuple[ic: Chan[InputEvent], oc: Chan[OutputEvent]]]()
var gTimerLock: RLock
var gTimerChan {.guard: gTimerLock.} = none[Chan[TimerChanMsg]]()

logScope:
  topics = "sys sys:live live-chans"

gChanLock.initRLock()
gTimerLock.initRLock()

proc initChannelsForSymbol*(symbol: string) =
  withRLock(gChanLock):
    {.gcsafe.}:
      gChannels[symbol] = (ic: newChan[InputEvent](), oc: newChan[OutputEvent]())


proc getChannelsForSymbol*(symbol: string): tuple[ic: Chan[InputEvent], oc: Chan[OutputEvent]] {.gcsafe.} =
  withRLock(gChanLock):
    {.gcsafe.}:
      if symbol notin gChannels:
        initChannelsForSymbol(symbol)
      
      return gChannels[symbol]


proc getTimerChannel*(): Chan[TimerChanMsg] =
  withRLock(gTimerLock):
    if gTimerChan.isNone:
      info "Timer channel requested but none exists, creating a new one"
      gTimerChan = some newChan[TimerChanMsg]()
    return gTimerChan.get
