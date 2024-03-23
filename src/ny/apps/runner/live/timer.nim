## Implements a timer module to get a callback at a specified point in time
## Note: In simulation mode, we need to ensure that events are chronologically ordered,
## but we don't want to/can't wait for the actual requested time.

import std/heapqueue
import std/posix # linux only; used for cond vars
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

  TimerEventScheduler* = ref object
    events*: HeapQueue[QueuedTimerEvent]
    mutex*: Pthread_mutex
    cv*: Pthread_cond

func `<`(a, b: QueuedTimerEvent): bool = a.event < b.event

var gTimerInsertionThread: Thread[ptr TimerEventScheduler]
var gTimerWaitThread: Thread[ptr TimerEventScheduler]
var gTimerThreadLock: RLock
var gTimerThreadCreated {.guard: gTimerThreadLock.} = false


template cCall(call: untyped, msg: string, onErr: untyped): untyped =
  block:
    let fErr = call
    if fErr.int != 0:
      fatal msg, fErr=fErr, failReason=strerror(fErr)
      onErr


template cCall(call: untyped, msg: string): untyped =
  block:
    let fErr = call
    if fErr.int != 0:
      fatal msg, fErr=fErr, failReason=strerror(fErr)


proc newTimerEventScheduler(): TimerEventScheduler =
  new(result)
  result.events = initHeapQueue[QueuedTimerEvent]()
  cCall(pthread_mutex_init(result.mutex.addr, nil), "Failed to initialize TimerEventScheduler mutex; terminating", quit 216)
  cCall(pthread_cond_init(result.cv.addr, nil), "Failed to initialize TimerEventScheduler cond var; terminating", quit 217)


# Note: We don't have any clean up for this, but that's fine because this lives for the entire lifetime of the program
var gEventScheduler = newTimerEventScheduler()


proc addEvent(sched: var TimerEventScheduler, msg: QueuedTimerEvent) {.gcsafe.} =
  cCall(pthread_mutex_lock(sched.mutex.addr), "(addEvent) Failed to lock TimerEventScheduler mutex")

  sched.events.push QueuedTimerEvent(symbol: msg.symbol, event: msg.event)
  cCall(pthread_cond_signal(sched.cv.addr), "(addEvent) Failed to signal TimerEventScheduler cv")
  cCall(pthread_mutex_unlock(sched.mutex.addr), "(addEvent) Failed to unlock TimerEventScheduler mutex")


proc waitForNextEvent(sched: var TimerEventScheduler): QueuedTimerEvent =
  cCall(pthread_mutex_lock(sched.mutex.addr), "(waitForNextEvent) Failed to lock TimerEventScheduler mutex")
  
  while sched.events.len == 0 or sched.events[0].event.timestamp > getNowUtc():
    trace "Waiting for next event; non queued"
    if sched.events.len == 0:
      cCall(pthread_cond_wait(sched.cv.addr, sched.mutex.addr), "(waitForNextEvent) Failed to wait for TimerEventScheduler cv")
    else:
      let target = sched.events[0].event.timestamp
      trace "Waiting for next event; queue not empty", wakeUp=sched.events[0].event.timestamp, queueSize=sched.events.len

      if target <= getNowUtc():
        result = sched.events.pop
        cCall(pthread_mutex_unlock(sched.mutex.addr), "(waitForNextEvent) Failed to unlock TimerEventScheduler mutex (1)")
        return # just be explicit

      let timespec = Timespec(tv_sec: cast[posix.Time](target.epoch.clong), tv_nsec: target.nanos)
      let timeoutErr = pthread_cond_timedwait(sched.cv.addr, sched.mutex.addr, timespec.addr)
      if timeoutErr == ETIMEDOUT:
        # Timeout errors in this context mean that we hit our target time
        discard
      elif timeoutErr != 0:
        error "(waitForNextEvent) Failed to timed wait for TimerEventScheduler cv", target, curTime=getNowUtc(), timeoutErr=timeoutErr, failReason=strerror(timeoutErr)

  result = sched.events.pop
  cCall(pthread_mutex_unlock(sched.mutex.addr), "(waitForNextEvent) Failed to unlock TimerEventScheduler mutex (2)")
  return # just be explicit


proc timerInsertionThreadEx(sched: ptr TimerEventScheduler) {.thread, raises: [].} =
  var chan = getTimerChannel()
  while true:
    var msg: TimerChanMsg
    chan.recv(msg)
    trace "Creating timer", timer=msg.timer
    sched[].addEvent QueuedTimerEvent(symbol: msg.symbol, event: msg.timer)


proc timerWaitThreadEx(sched: ptr TimerEventScheduler) {.thread, raises: [].} =
  while true:
    let event = sched[].waitForNextEvent()
    try:
      let ic = getChannelForSymbol(event.symbol)
      trace "Sending timer", timer=event.event
      ic.send(InputEvent(kind: Timer, timer: event.event))
    except KeyError:
      error "Key error", msg=getCurrentExceptionMsg()


proc createTimerThread*() =
  withRLock(gTimerThreadLock):
    if not gTimerThreadCreated:
      info "Creating timer threads ..."
      createThread(gTimerInsertionThread, timerInsertionThreadEx, gEventScheduler.addr)
      createThread(gTimerWaitThread, timerWaitThreadEx, gEventScheduler.addr)
      gTimerThreadCreated = true
