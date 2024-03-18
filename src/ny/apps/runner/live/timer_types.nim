import ny/core/types/strategy_base
# import ny/core/types/timestamp


type
  RequestTimer* = object
    timer*: TimerEvent

  RespondTimer* = object
    timer*: TimerEvent

  TimerChanMsgKind* = enum
    CreateTimer
    # DoneTimer

  TimerChanMsg* = object
    symbol*: string
    case kind*: TimerChanMsgKind
    of CreateTimer:
      create*: RequestTimer
    # of DoneTimer:
    #   done*: RespondTimer
  