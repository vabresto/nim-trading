## Implements a timer module to get a callback at a specified point in time
## Note: In simulation mode, we need to ensure that events are chronologically ordered,
## but we don't want to/can't wait for the actual requested time.

import std/heapqueue
import std/rlocks

import chronicles
import threading/channels

import ny/apps/runner/live/chans
import ny/apps/runner/live/timer_types
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
    if chan.tryRecv(msg):
      case msg.kind
      of CreateTimer:
        trace "Creating timer", timer=msg.create.timer
        timers.push(QueuedTimerEvent(symbol: msg.symbol, event: msg.create.timer))

    let nowTs = getNowUtc()
    while timers.len > 0 and timers[0].event.timestamp <= nowTs:
      let queued = timers.pop
      try:
        let (ic, _) = getChannelsForSymbol(queued.symbol)
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
