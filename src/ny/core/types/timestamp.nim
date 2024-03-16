import std/strutils
import std/times

type
  Timestamp* = object
    epoch*: int64 = 0
    nanos*: NanosecondRange = 0

func `$`*(ts: Timestamp): string =
  {.noSideEffect.}:
    initTime(ts.epoch, ts.nanos).inZone(local()).format("yyyy-MM-dd'T'hh:mm:ss'.'fffffffffzzz")

func `<`*(a, b: Timestamp): bool =
  if a.epoch == b.epoch:
    a.nanos < b.nanos
  else:
    a.epoch < b.epoch

proc parseTimestamp*(s: string): Timestamp {.noSideEffect.} =
  let splitted = s.split(".")
  let epochPart = splitted[0]
  var nanosPart = splitted[1]

  if nanosPart[^1] != 'Z':
    return #error

  # 9 digits ns, plus one for 'Z'
  while nanosPart.len < 10:
    nanosPart[^1] = '0'
    nanosPart.add 'Z'

  {.noSideEffect.}:
    let dt = parse(epochPart & "." & nanosPart, "yyyy-MM-dd'T'hh:mm:ss'.'fffffffffzzz")
  Timestamp(epoch: dt.toTime.toUnix, nanos: dt.nanosecond)
