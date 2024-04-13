## This module provides wrappers for all db access. The primary reason for it is so we can use a single connection
## to not overload the db, and this requires using a lock. The lock might not be needed, not sure if the pg
## connection is thread-safe.

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
