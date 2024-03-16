## Implements a timer module to get a callback at a specified point in time
## Note: In simulation mode, we need to ensure that events are chronologically ordered,
## but we don't want to/can't wait for the actual requested time.

import std/heapqueue

import chronicles
import threading/channels

import ny/apps/runner/live/chans
import ny/apps/runner/live/timer_types
import ny/core/types/strategy_base

var timerThread: Thread[void]
var timerThreadCreated = false


proc timerThreadEx() {.thread, raises: [].} =
  var timers = initHeapQueue[TimerEvent]()
  var chan = getTimerChannel()

  while true:
    var msg: TimerChanMsg
    if chan.tryRecv(msg):
      case msg.kind
      of CreateTimer:
        info "Creating timer", timer=msg.create.timer
        timers.push(msg.create.timer)
      of DoneTimer:
        discard


proc createTimerThread*() =
  if not timerThreadCreated:
    info "Creating timer thread ..."
    createThread(timerThread, timerThreadEx)
    timerThreadCreated = true
