import nim_redis

proc getStreamName*(val: RedisValue): ?!tuple[stream: string, id: string] {.raises: [].} =
  ## This helper function extracts the stream name and message id from a stream response (so that 
  ## the calling code can properly route the message to the appropriate consumer, and resubscribe
  ## for the appropriate subsequent messages)
  try:
    case val.kind
    of Array:
      let streamName = val.arr[0].arr[0].str
      let id = val.arr[0].arr[1].arr[0].arr[0].str
      return success (streamName, id)
    of Null, Error, SimpleString, BulkString, Integer:
      return failure "Unable to parse non-array stream value: " & $val
  except ValueError:
    return failure "Error parsing as a stream response: " & $val
