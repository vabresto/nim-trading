import ny/core/types/strategy_base

type
  OutputEventMsg* = object
    symbol*: string
    event*: OutputEvent

  TimerChanMsg* = object
    symbol*: string
    timer*: TimerEvent
