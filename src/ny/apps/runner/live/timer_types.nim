import ny/core/types/strategy_base


type
  RequestTimer* = object
    timer*: TimerEvent

  RespondTimer* = object
    timer*: TimerEvent

  TimerChanMsgKind* = enum
    CreateTimer

  TimerChanMsg* = object
    symbol*: string
    case kind*: TimerChanMsgKind
    of CreateTimer:
      create*: RequestTimer
  