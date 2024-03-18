## This module implements options parsing for recording applications

import std/options
import std/parseopt
import std/strutils
import std/times

type
  ParsedCliArgs* = object
    date*: Option[DateTime]
    symbols*: seq[string]

proc parseCliArgs*(cmdLine: string = ""): ParsedCliArgs =
  # If cmdLine is empty, will pull cli args. Otherwise will read the input string
  # Set a placeholder value in longNoVal because it has different behaviour if non-empty
  var parser = initOptParser(cmdLine, longNoVal = @["_PLACEHOLDER"])

  var readingSymbols = false
  for kind, key, val in parser.getopt():
    case kind
    of cmdEnd: doAssert(false)  # Doesn't happen with getopt()
    of cmdShortOption, cmdLongOption:
      if val == "":
        # Currently don't have any flags
        echo "ERROR: Got unbound flag: ", val
        quit 207
      else:
        case key
        of "date":
          result.date = some val.parse("yyyy-MM-dd")
        of "symbol", "symbols":
          result.symbols.add val.toUpper
          readingSymbols = true
        else:
          echo "ERROR: Got unknown options --", key, "=", val
          quit 208
    of cmdArgument:
      if readingSymbols:
        result.symbols.add key.toUpper
      else:
        echo "ERROR: Got unbound argument: ", val
        quit 209

when isMainModule:
  echo parseCliArgs()
