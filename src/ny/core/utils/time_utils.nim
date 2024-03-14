import std/times


proc getNowUtc*(): DateTime =
  fromUnixFloat(epochTime()).utc
