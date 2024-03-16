import jsony


type
  AlpacaOrderKind* = enum
    Market
    Limit
    Stop
    StopLimit
    StopTrailing


proc dumpHook*(s: var string, v: AlpacaOrderKind) =
  case v
  of Market:
    s.add "market"
  of Limit:
    s.add "limit"
  of Stop:
    s.add "stop"
  of StopLimit:
    s.add "stop_limit"
  of StopTrailing:
    s.add "trailing_stop"


proc enumHook*(v: string): AlpacaOrderKind =
  case v:
  of "market": Market
  of "limit": Limit
  of "stop": Stop
  of "stop_limit": StopLimit
  of "trailing_stop": StopTrailing
  else:
    raise newException(ValueError, "Can't parse AlpacaOrderKind: " & v)


proc parseHook*(s: string, i: var int, v: var AlpacaOrderKind) =
  var parsed: string
  parseHook(s, i, parsed)
  v = enumHook(parsed)
