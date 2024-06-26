## # Overview
## 
## This module implements a custom nanosecond precision timestamp. Although Nim datetimes are
## already nanosecond resolution, there are some inconveniences working with them, whereas
## this `Timestamp` class is simplified and has a smaller but well-defined scope.

import std/strutils
import std/times

import chronicles

type
  Timestamp* = object
    ## Represents a UTC time point
    epoch*: int64 = 0
    nanos*: NanosecondRange = 0

const tsStringFormat* = "yyyy-MM-dd'T'HH:mm:ss'.'fffffffffzzz"

func toTime*(ts: Timestamp): Time {.noSideEffect.} =
  initTime(ts.epoch, ts.nanos)

func fromTime*(time: Time): Timestamp {.noSideEffect.} =
  Timestamp(epoch: time.toUnix, nanos: time.nanosecond)

proc getNowUtc*(): Timestamp =
  let curTime = epochTime()
  Timestamp(epoch: curTime.int64, nanos: (curTime * 1_000_000_000.float).int64 mod 1_000_000_000)

proc toDateTime*(ts: Timestamp): DateTime {.noSideEffect.} =
  {.noSideEffect.}:
    ts.toTime.inZone(local())

proc getDateStr*(ts: Timestamp): string {.noSideEffect.} =
  {.noSideEffect.}:
    ts.toDateTime.getDateStr()

func `+`*(ts: Timestamp, dur: Duration): Timestamp {.noSideEffect.} =
  var time = ts.toTime
  time += dur
  fromTime(time)

func `-`*(ts: Timestamp, dur: Duration): Timestamp {.noSideEffect.} =
  var time = ts.toTime
  time -= dur
  fromTime(time)

func `-`*(a: Timestamp, b: Timestamp): Duration {.noSideEffect.} =
  a.toTime - b.toTime

func `$`*(ts: Timestamp): string =
  ts.toDateTime.format(tsStringFormat)

func friendlyString*(ts: Timestamp): string =
  ts.toDateTime.format("yyyy-MM-dd' 'HH:mm:ss'.'fff")

func `<`*(a, b: Timestamp): bool =
  if a.epoch == b.epoch:
    a.nanos < b.nanos
  else:
    a.epoch < b.epoch

func `<=`*(a, b: Timestamp): bool =
  a < b or a == b

proc parseTimestamp*(s: string): Timestamp {.noSideEffect, raises: [].} =
  # A few different cases:
  # - could be a raw alpaca md timestamp with timezone info
  # - could be a raw alpaca md timestamp WITHOUT timezone info (ex. bar minute)
  # - could be a timestamp from the db/redis stream, which we've already parsed

  try:
    if s[^1] != 'Z' and "-" in s:
      # We've already parsed this; it may have a timezone and is guaranteed to already have 9 nanos
      {.noSideEffect.}:
        let dt = parse(s, tsStringFormat)
      Timestamp(epoch: dt.toTime.toUnix, nanos: dt.nanosecond)
    elif s[^1] != 'Z' and "+" in s:
      # Currently this should only happen with alpaca bars
      {.noSideEffect.}:
        let dt = parse(s, "yyyy-MM-dd'T'HH:mm:sszz") # note: only two z's here
      Timestamp(epoch: dt.toTime.toUnix, nanos: dt.nanosecond)
    else:
      if "." notin s:
        # no subsecond portion
        {.noSideEffect.}:
          let dt = parse(s, "yyyy-MM-dd'T'HH:mm:sszzz")
        Timestamp(epoch: dt.toTime.toUnix, nanos: dt.nanosecond)
      else:
        let splitted = s.split(".")
        let epochPart = splitted[0]
        var nanosPart = splitted[1]

        if nanosPart[^1] != 'Z':
          {.noSideEffect.}:
            error "No timezone component?", s
          return Timestamp(epoch: -1, nanos: 0)

        # 9 digits ns, plus one for 'Z'
        while nanosPart.len < 10:
          nanosPart[^1] = '0'
          nanosPart.add 'Z'

        {.noSideEffect.}:
          let dt = parse(epochPart & "." & nanosPart, tsStringFormat)
        Timestamp(epoch: dt.toTime.toUnix, nanos: dt.nanosecond)
  except TimeParseError:
    {.noSideEffect.}:
      error "Failed to parse timestamp!", s
    Timestamp(epoch: -1, nanos: 0)


proc parseDbTimestamp*(s: string): Timestamp {.noSideEffect, raises: [].} =
  try:
    let splitted = s.split(".")
    let epochPart = splitted[0]
    var (nanosTzSplitted, tzSplitter) = if "+" in splitted[1]:
      (splitted[1].split("+"), "+")
    elif "-" in splitted[1]:
      (splitted[1].split("-"), "-")
    else:
      {.noSideEffect.}:
        error "No timezone component from db?", s
      return Timestamp(epoch: -1, nanos: 0)

    var nanosPart = nanosTzSplitted[0]
    let tzPart = nanosTzSplitted[1]

    while nanosPart.len < 6:
      nanosPart.add '0'

    {.noSideEffect.}:
      let dt = parse(epochPart & "." & nanosPart & tzSplitter & tzPart, "yyyy-MM-dd' 'hh:mm:ss'.'ffffffzz")
    Timestamp(epoch: dt.toTime.toUnix, nanos: dt.nanosecond)
  except TimeParseError:
    {.noSideEffect.}:
      error "Failed to parse db timestamp!", s
    Timestamp(epoch: -1, nanos: 0)
