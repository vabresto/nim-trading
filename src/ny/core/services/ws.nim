# import std/options

import chronicles except toJson
import nim_redis

# import ny/core/env/envs

template withWebsocket*(ws, init: untyped, loop: untyped): untyped =
  var ws: WebSocket
  var wsInitialized = false

  try:
    info "Starting trade updates websocket ..."

    init

    wsInitialized = true
    info "Trade updates websocket connected"

    info "Running main loop ..."
    while true:
      # If we're on to the next day, reload the program to get the new config
      if getNowUtc().toDateTime().getDateStr() != today:
        break
      
      loop

  except OSError:
    error "Redis (?) OSError", msg=getCurrentExceptionMsg()
  finally:
    if redisInitialized:
      try:
        redis.close()
      except Exception:
        error "Failed to close redis connection", err=getCurrentExceptionMsg()
      finally:
        redisInitialized = false
