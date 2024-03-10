## This module provides some aliases for shared connections

import std/options

import ny/core/env/envs


proc getMdRedisHost*(): Option[string] =
  getOptEnv("MD_REDIS_HOST")


proc getMdRedisPass*(): Option[string] =
  getOptEnv("MD_REDIS_PASS")


proc getAlpacaKey*(): Option[string] =
  getOptEnv("ALPACA_PAPER_KEY")


proc getAlpacaSecret*(): Option[string] =
  getOptEnv("ALPACA_PAPER_SECRET")
