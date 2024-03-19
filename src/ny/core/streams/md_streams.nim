import std/enumerate
import std/json
import std/net

import chronicles except toJson
import jsony
import nim_redis

import ny/core/md/alpaca/types
import ny/core/types/timestamp
import ny/core/md/alpaca/parsing

type
  MdStreamResponse* = object
    stream*: string
    id*: string
    rawContents*: RedisValue
    rawJson*: JsonNode
    mdReply*: AlpacaMdWsReply
    receiveTimestamp*: Timestamp


proc parseMdStreamResponse*(val: RedisValue): ?!MdStreamResponse {.raises: [].} =
  var resp = MdStreamResponse()
  try:
    case val.kind
    of Array:
      let inner = val.arr[0].arr[1].arr[0].arr[1]
      for curIdx, item in enumerate(inner.arr):
        case item.kind
        of SimpleString, BulkString:
          if item.str == "md_raw_data":
            resp.rawJson = inner.arr[curIdx + 1].str.parseJson()
            resp.mdReply = inner.arr[curIdx + 1].str.fromJson(AlpacaMdWsReply)
          if item.str == "md_receive_timestamp":
            resp.receiveTimestamp = inner.arr[curIdx + 1].str.parseTimestamp
        else:
          discard

      resp.stream = val.arr[0].arr[0].str
      resp.id = val.arr[0].arr[1].arr[0].arr[0].str
      resp.rawContents = val.arr[0].arr[1].arr[0].arr[1]
      return success resp
    of Null, Error, SimpleString, BulkString, Integer:
      return failure "Unable to parse non-array stream value: " & $val
  except OSError, IOError:
    return failure "Error parsing raw json: " & $val
  except ValueError:
    return failure "Error parsing as a stream response: " & $val