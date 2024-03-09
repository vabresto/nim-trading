import std/options
import std/os

import nim_redis


let client = newRedisClient("localhost", pass=some "foobarabc123")
let clientPtr = client.addr


type
  StreamResponse = object
    stream: string
    id: string
    contents: RedisValue


proc parseStreamResponse(val: RedisValue): ?!StreamResponse {.raises: [].} =
  var resp = StreamResponse()
  try:
    resp.stream = val.arr[0].arr[0].str
    resp.id = val.arr[0].arr[1].arr[0].arr[0].str
    resp.contents = val.arr[0].arr[1].arr[0].arr[1]
    return success resp
  except ValueError:
    return failure "Error parsing as a stream response: " & $val


proc receiveThreadProc() {.thread, gcsafe.} =
  var lastId = "$"

  while true:
    clientPtr[].send(@["XREAD", "BLOCK", "0", "STREAMS", "race:france", lastId])
    let replyRaw = clientPtr[].receive()
    if replyRaw.isOk:
      let replyParseAttempt = replyRaw[].parseStreamResponse
      if replyParseAttempt.isOk:
        let reply = replyParseAttempt[]

        lastId = reply.id
        echo "PARSED: ", reply


var receiveThread: Thread[void]
createThread(receiveThread, receiveThreadProc)

sleep(50_000)
client.close()
echo "Closing gracefully"
