import jsony


type
  OrderKind* = enum
    Market
    Limit
    Stop
    StopLimit
    StopTrailing


proc dumpHook*(s: var string, v: OrderKind) =
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


proc enumHook*(v: string): OrderKind =
  case v:
  of "market": Market
  of "limit": Limit
  of "stop": Stop
  of "stop_limit": StopLimit
  of "trailing_stop": StopTrailing
  else:
    raise newException(ValueError, "Can't parse OrderKind: " & v)


proc parseHook*(s: string, i: var int, v: var OrderKind) =
  var parsed: string
  parseHook(s, i, parsed)
  v = enumHook(parsed)
