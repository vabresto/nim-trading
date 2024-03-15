# import std/times

import ny/apps/runner/types


type
  RequestTimer* = object
    timer*: TimerEvent

  RespondTimer* = object
    timer*: TimerEvent

  TimerChanMsgKind* = enum
    CreateTimer
    DoneTimer

  TimerChanMsg* = object
    case kind*: TimerChanMsgKind
    of CreateTimer:
      create*: RequestTimer
    of DoneTimer:
      done*: RespondTimer
  

proc `<`*(a, b: TimerEvent): bool = a.at < b.at
