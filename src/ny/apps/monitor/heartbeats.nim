import std/rlocks
import std/tables


var gHeartbeatsLock: RLock
var gTotalNumHeartbeatsProcessed {.guard: gHeartbeatsLock.} = 0
var gHeartbeats {.guard: gHeartbeatsLock.} = initTable[string, bool]()

gHeartbeatsLock.initRLock()


proc getHeartbeats*(): Table[string, bool] =
  withRLock(gHeartbeatsLock):
    {.gcsafe.}:
      return gHeartbeats


proc setHeartbeat*(key: string, val: bool) =
  withRLock(gHeartbeatsLock):
    {.gcsafe.}:
      gHeartbeats[key] = val


proc incHeartbeatsProcessed*() =
  withRLock(gHeartbeatsLock):
    {.gcsafe.}:
      inc gTotalNumHeartbeatsProcessed


proc getHeartbeatsProcessed*(): int =
  withRLock(gHeartbeatsLock):
    {.gcsafe.}:
      return gTotalNumHeartbeatsProcessed
