import std/options

import chronicles
import threading/channels
import std/isolation

import ny/apps/runner/chans
import ny/apps/runner/types


type
  RunnerThreadArgs* = object
    symbol*: string


# func executeStrategy[T](state: var T, update: ResponseMessage): Option[RequestMessage] =
#   discard


func executeStrategy(state: var int, update: ResponseMessage): Option[RequestMessage] =
  case update.kind
  of Timer:
    return some RequestMessage(kind: Timer)
  of MarketData:
    discard
  of OrderUpdate:
    discard
  return none[RequestMessage]()


proc runner*(args: RunnerThreadArgs) {.thread, nimcall, raises: [], forbids: [MarketIoEffect].} =
  let (ic, oc) = block:
    try:
      {.gcsafe.}:
        getChannelsForSymbol(args.symbol)
    except KeyError:
      error "Failed to initialize runner; quitting", args
      return

  var state = 0

  while true:
    let msg = block:
      var msg: ResponseMessage
      if not ic.tryRecv(msg):
        continue
      msg
    
    info "Got message", msg

    var req = state.executeStrategy(msg)
    if req.isSome:
      try:
        let reply = req.get
        oc.send(isolate(reply))
      except Exception:
        error "Failed to send request!", req
