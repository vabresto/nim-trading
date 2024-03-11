import std/tables


func makeMdStreamName*(date: string, symbol: string): string =
  "md:" & date & ":" & symbol


func makeOuStreamName*(date: string, symbol: string): string =
  "ou:" & date & ":" & symbol


proc makeReadMdStreamsCommand*(streams: Table[string, string]): seq[string] =
  result.add "XREAD"
  result.add "BLOCK"
  result.add "0"
  result.add "STREAMS"

  for (stream, id) in streams.pairs:
    result.add stream

  for (stream, id) in streams.pairs:
    result.add id
