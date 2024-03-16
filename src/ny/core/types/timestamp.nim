import std/strutils
import std/times

type
  Timestamp* = object
    epoch*: int64 = 0
    nanos*: NanosecondRange = 0

const tsStringFormat* = "yyyy-MM-dd'T'hh:mm:ss'.'fffffffffzzz"

func toTime*(ts: Timestamp): Time {.noSideEffect.} =
  initTime(ts.epoch, ts.nanos)

func fromTime*(time: Time): Timestamp {.noSideEffect.} =
  Timestamp(epoch: time.toUnix, nanos: time.nanosecond)

proc toDateTime*(ts: Timestamp): DateTime {.noSideEffect.} =
  {.noSideEffect.}:
    ts.toTime().inZone(local())

func `+`*(ts: Timestamp, dur: Duration): Timestamp {.noSideEffect.} =
  var time =ts.toTime
  time += dur
  fromTime(time)

func `-`*(ts: Timestamp, dur: Duration): Timestamp {.noSideEffect.} =
  var time =ts.toTime
  time -= dur
  fromTime(time)

func `$`*(ts: Timestamp): string =
  ts.toDateTime.format(tsStringFormat)

func `<`*(a, b: Timestamp): bool =
  if a.epoch == b.epoch:
    a.nanos < b.nanos
  else:
    a.epoch < b.epoch

proc parseTimestamp*(s: string): Timestamp {.noSideEffect.} =
  if s[^1] != 'Z':
    # We've already parsed this; it may have a timezone and is guaranteed to already have 9 nanos
    {.noSideEffect.}:
      let dt = parse(s, tsStringFormat)
    Timestamp(epoch: dt.toTime.toUnix, nanos: dt.nanosecond)
  else:
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
      let dt = parse(epochPart & "." & nanosPart, tsStringFormat)
    Timestamp(epoch: dt.toTime.toUnix, nanos: dt.nanosecond)

