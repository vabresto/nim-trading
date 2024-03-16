import ny/apps/runner/types

func executeStrategy*(state: var int, update: ResponseMessage): seq[RequestMessage] =
  case update.kind
  of Timer:
    discard
    # return @[RequestMessage(kind: Timer)]
  of MarketData:
    if state == 0:
      state = 1
      return @[RequestMessage(kind: Timer, timer: TimerEvent(at: "2024-03-15T03:15:48.561750000Z"))]
    discard
  of OrderUpdate:
    discard
  return @[]
