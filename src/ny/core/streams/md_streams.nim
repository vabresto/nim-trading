import std/enumerate
import std/json
import std/net
# import std/options
# import std/os
# import std/tables
# import std/times

import chronicles except toJson
# import db_connector/db_postgres
import jsony
import nim_redis

# import ny/core/db/mddb
# import ny/core/env/envs
import ny/core/md/alpaca/types
# import ny/core/md/utils
import ny/core/types/timestamp
# import ny/core/utils/rec_parseopt
# import ny/core/utils/sim_utils

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
          if item.str == "md_parsed_data":
            resp.mdReply = inner.arr[curIdx + 1].str.fromJson(AlpacaMdWsReply)
          if item.str == "md_raw_data":
            resp.rawJson = inner.arr[curIdx + 1].str.parseJson()
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