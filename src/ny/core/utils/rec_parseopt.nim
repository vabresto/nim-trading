## This module implements options parsing for recording applications

import std/net
import std/options
import std/parseopt
import std/strutils
import std/times

import chronicles

import ny/core/heartbeat/server

logScope:
  topics = "sys sys:cli-args"

type
  ParsedCliArgs* = object
    date*: Option[DateTime]
    symbols*: seq[string]
    heartbeat*: bool = false
    monitorAddress*: Option[string]
    monitorPort*: Option[Port]

func monitoringEnabled*(cliArgs: ParsedCliArgs): bool =
  cliArgs.monitorAddress.isSome and cliArgs.monitorPort.isSome

proc parseCliArgs*(cmdLine: string = ""): ParsedCliArgs {.raises: [].} =
  ## Standardized parsing for command line args shared between all services

  # If cmdLine is empty, will pull cli args. Otherwise will read the input string
  # Set a placeholder value in longNoVal because it has different behaviour if non-empty
  var parser = initOptParser(cmdLine, longNoVal = @["_PLACEHOLDER", "heartbeat", "no-heartbeat"])

  var readingSymbols = false
  for kind, key, val in parser.getopt():
    case kind
    of cmdEnd: doAssert(false)  # Doesn't happen with getopt()
    of cmdShortOption, cmdLongOption:
      if val == "":
        case key
        of "heartbeat":
          result.heartbeat = true
        of "no-heartbeat":
          result.heartbeat = false
        else:
          # Currently don't have any flags
          error "Got unbound flag: ", key
          quit 207
      else:
        case key
        of "date":
          try:
            result.date = some val.parse("yyyy-MM-dd")
          except TimeParseError:
            error "Failed to parse time", val
            quit 212
        of "symbol", "symbols":
          result.symbols.add val.toUpper
          readingSymbols = true
        of "monitor-address":
          result.monitorAddress = some val
          if result.monitorPort.isNone:
            result.monitorPort = some 5001.Port
        of "monitor-port":
          try:
            result.monitorPort = some val.parseInt.Port
          except ValueError:
            error "Failed to parse as port", val
            quit 208
        else:
          error "Got unknown options --", key, val
          quit 208
    of cmdArgument:
      if readingSymbols:
        result.symbols.add key.toUpper
      else:
        error "Got unbound argument: ", val
        quit 209
  
  if result.heartbeat:
    startHeartbeatServerThread()
  else:
    info "Heartbeat not enabled"

when isMainModule:
  echo parseCliArgs()
