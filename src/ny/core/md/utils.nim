import std/tables


func makeMdStreamName*(date: string, symbol: string): string =
  "md:" & date & ":" & symbol


func makeOuStreamName*(date: string, symbol: string): string =
  "ou:" & date & ":" & symbol


proc makeReadStreamsCommand*(streams: Table[string, string], simulation: bool = false): seq[string] =
  result.add "XREAD"
  if simulation:
    result.add "COUNT"
    result.add "1"
  else:
    result.add "BLOCK"
    result.add "0"
  result.add "STREAMS"

  for (stream, id) in streams.pairs:
    result.add stream

  for (stream, id) in streams.pairs:
    result.add id
