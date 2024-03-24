import std/asyncdispatch
import std/json
import std/net
import std/rlocks
import std/options
import std/os
import std/sequtils
import std/sets
import std/strformat
import std/strutils
import std/sugar
import std/tables

import chronicles
import mummy
import mummy/routers

import ny/core/env/envs
import ny/core/heartbeat/client
import ny/core/types/timestamp
import ny/core/inspector/server as inspector_server


proc renderStrategyStates*(): string {.gcsafe.} =
  {.gcsafe.}:
    let strategyStates = getStrategyStates()

  fmt"""
  <div id="strategy-states" hx-swap-oob="true">
    {strategyStates}
  </div>
  """
