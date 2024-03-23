## Implements a timer module to get a callback at a specified point in time
## Note: In simulation mode, we need to ensure that events are chronologically ordered,
## but we don't want to/can't wait for the actual requested time.

import std/heapqueue
import std/rlocks

import chronicles
import threading/channels

import ny/apps/runner/live/chan_types
import ny/apps/runner/live/chans
import ny/core/types/strategy_base
import ny/core/types/timestamp

logScope:
  topics = "sys sys:live live-timer"

type
  QueuedTimerEvent* = object
    symbol: string
    event: TimerEvent

func `<`(a, b: QueuedTimerEvent): bool = a.event < b.event

var timerThread: Thread[void]
var timerThreadLock: RLock
var timerThreadCreated {.guard: timerThreadLock.} = false


proc timerThreadEx() {.thread, raises: [].} =
  var timers = initHeapQueue[QueuedTimerEvent]()
  var chan = getTimerChannel()

  while true:
    var msg: TimerChanMsg
    # TODO: Use a pthread_cond here instead
    if chan.tryRecv(msg):
      trace "Creating timer", timer=msg.timer
      timers.push(QueuedTimerEvent(symbol: msg.symbol, event: msg.timer))

    let nowTs = getNowUtc()
    while timers.len > 0 and timers[0].event.timestamp <= nowTs:
      let queued = timers.pop
      try:
        let ic = getChannelForSymbol(queued.symbol)
        trace "Sending timer", timer=queued.event
        ic.send(InputEvent(kind: Timer, timer: queued.event))
      except KeyError:
        error "Key error", msg=getCurrentExceptionMsg()


proc createTimerThread*() =
  withRLock(timerThreadLock):
    if not timerThreadCreated:
      info "Creating timer thread ..."
      createThread(timerThread, timerThreadEx)
      timerThreadCreated = true
