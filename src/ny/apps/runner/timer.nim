## Implements a timer module to get a callback at a specified point in time
## Note: In simulation mode, we need to ensure that events are chronologically ordered,
## but we don't want to/can't wait for the actual requested time.

import std/heapqueue
import std/times

import chronicles
import threading/channels

import ny/apps/runner/chans
import ny/apps/runner/timer_types
import ny/apps/runner/types
# import ny/core/utils/time_utils


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

    # @next: need to figure out how to set this up properly, sometimes float is more convenient, other times string

    # let curTime = epochTime()
    # while timers.len > 0 and timers[0].at <= curTime:
    #   info "Ring ring", timer=timers[0]
    #   try:
    #     if not chan.trySend(TimerChanMsg(kind: DoneTimer, done: RespondTimer(timer: timers.pop()))):
    #       error "Timer failed to ring!", curTime
    #   except Exception:
    #     # For =destroy hook
    #     error "Failed to send timer ring down channel!"


proc createTimerThread*() =
  if not timerThreadCreated:
    info "Creating timer thread ..."
    createThread(timerThread, timerThreadEx)
    timerThreadCreated = true
