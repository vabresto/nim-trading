## # Overview
## 
## This module implements the channels used by the system:
## - the (single) output channel from all strategies out to the market
## - the (single) management channel from all strategies to the callback timer
## - the per-symbol input channels of responses from the market/timer, that need to be processed by the strategy

import std/rlocks
import std/tables

import chronicles
import threading/channels

import ny/apps/runner/live/chan_types
import ny/core/types/strategy_base

var gChanLock: RLock
var gChannels {.guard: gChanLock.} = initTable[string, Chan[InputEvent]]()
var gTimerChan = newChan[TimerChanMsg]()
var gOutChan = newChan[OutputEventMsg]()


logScope:
  topics = "sys sys:live live-chans"


gChanLock.initRLock()


proc getTheOutputChannel*(): Chan[OutputEventMsg] {.gcsafe.} =
  gOutChan


proc getTimerChannel*(): Chan[TimerChanMsg] =
  gTimerChan


proc initChannelForSymbol*(symbol: string) =
  withRLock(gChanLock):
    {.gcsafe.}:
      gChannels[symbol] = newChan[InputEvent]()


proc getChannelForSymbol*(symbol: string): Chan[InputEvent] {.gcsafe.} =
  withRLock(gChanLock):
    {.gcsafe.}:
      if symbol notin gChannels:
        initChannelForSymbol(symbol)
      
      return gChannels[symbol]
