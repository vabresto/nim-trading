## This module provides some aliases for shared connections

import std/options
import std/os


proc getOptEnv*(env: string): Option[string] =
  let envKey = getEnv(env)
  if envKEy == "":
    none[string]()
  else:
    some envKey


proc getMdRedisHost*(): Option[string] =
  some "localhost"


proc getMdRedisPass*(): Option[string] =
  getOptEnv("MD_REDIS_PASS")


proc getAlpacaKey*(): Option[string] =
  getOptEnv("ALPACA_PAPER_KEY")


proc getAlpacaSecret*(): Option[string] =
  getOptEnv("ALPACA_PAPER_SECRET")
