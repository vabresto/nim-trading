import std/times
import ny/core/types/timestamp

proc getNowUtc*(): Timestamp =
  # fromUnixFloat(epochTime()).utc
  let curTime = epochTime()
  Timestamp(epoch: curTime.int64, nanos: (curTime * 1_000_000_000.float).int64 mod 1_000_000_000)

