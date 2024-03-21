## This module implements options parsing for recording applications

import std/options
import std/parseopt
import std/strutils
import std/times

import chronicles

logScope:
  topics = "sys sys:cli-args"

type
  ParsedCliArgs* = object
    date*: Option[DateTime]
    symbols*: seq[string]
    heartbeat*: bool = false

proc parseCliArgs*(cmdLine: string = ""): ParsedCliArgs {.raises: [].} =
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
        else:
          error "Got unknown options --", key, val
          quit 208
    of cmdArgument:
      if readingSymbols:
        result.symbols.add key.toUpper
      else:
        error "Got unbound argument: ", val
        quit 209

when isMainModule:
  echo parseCliArgs()
