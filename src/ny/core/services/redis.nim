import std/options

import chronicles except toJson
import nim_redis

import ny/core/env/envs

template withRedis*(redis, actions: untyped): untyped =
  var redis: RedisClient
  var redisInitialized = false

  try:
    info "Starting redis ..."
    redis = newRedisClient(loadOrQuit("MD_REDIS_HOST"), pass=some loadOrQuit("MD_REDIS_PASS"))
    redisInitialized = true
    info "Redis connected"

    actions
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
