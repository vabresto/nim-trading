import std/options
import std/os

import chronicles


proc getOptEnv*(env: string): Option[string] =
  let envKey = getEnv(env)
  if envKEy == "":
    none[string]()
  else:
    some envKey


proc loadOrQuit*(env: string): string =
  ## Tries to load an environment variable, and terminates the program if it fails
  let opt = getOptEnv(env)
  if opt.isNone:
    error "Failed to load required env var, terminating", env
    quit 206
  opt.get
