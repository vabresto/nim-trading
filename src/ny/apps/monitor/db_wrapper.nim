import std/rlocks

import ny/core/db/mddb
import ny/core/env/envs


var gDbWrapperLock: RLock
var gDb {.guard: gDbWrapperLock.} = getMdDb(loadOrQuit("MD_PG_HOST"), loadOrQuit("MD_PG_USER"), loadOrQuit("MD_PG_PASS"), loadOrQuit("MD_PG_NAME"))

gDbWrapperLock.initRLock()


proc getFillHistory*(date: string, strategy: string, symbol: string): seq[FillHistoryEvent] =
  withRLock(gDbWrapperLock):
    {.gcsafe.}:
      return mddb.getFillHistory(gDb, date, strategy, symbol)


proc getDailyLatencyStats*(): seq[DailyLatencyStat] =
  withRLock(gDbWrapperLock):
    {.gcsafe.}:
      return mddb.getDailyLatencyStats(gDb)
