## Implements a timer module to get a callback at a specified point in time
## Note: In simulation mode, we need to ensure that events are chronologically ordered,
## but we don't want to/can't wait for the actual requested time.

import std/heapqueue

import chronicles
import threading/channels

import ny/apps/runner/live/chans
import ny/apps/runner/live/timer_types
import ny/core/types/strategy_base
import ny/core/types/timestamp

type
  QueuedTimerEvent* = object
    symbol: string
    event: TimerEvent

func `<`(a, b: QueuedTimerEvent): bool = a.event < b.event

var timerThread: Thread[void]
var timerThreadCreated = false


proc timerThreadEx() {.thread, raises: [].} =
  var timers = initHeapQueue[QueuedTimerEvent]()
  var chan = getTimerChannel()

  while true:
    var msg: TimerChanMsg
    if chan.tryRecv(msg):
      case msg.kind
      of CreateTimer:
        info "Creating timer", timer=msg.create.timer
        timers.push(QueuedTimerEvent(symbol: msg.symbol, event: msg.create.timer))
      # of DoneTimer:
      #   # I think this case isn't needed and can be removed entirely
      #   # The runner thread will periodically push timer events to this channel
      #   # then this timmer thread will enqueue them in the heap, and when it is
      #   # time, will forward the event directly to the strategy's input channel
      #   # In other words, this timer thread is read-only from the timer channel
      #   discard

    let nowTs = getNowUtc()
    while timers.len > 0 and timers[0].event.timestamp <= nowTs:
      let queued = timers.pop
      try:
        let (ic, _) = getChannelsForSymbol(queued.symbol)
        ic.send(InputEvent(kind: Timer, timer: queued.event))
      except KeyError:
        error "Key error", msg=getCurrentExceptionMsg()


proc createTimerThread*() =
  if not timerThreadCreated:
    info "Creating timer thread ..."
    createThread(timerThread, timerThreadEx)
    timerThreadCreated = true
