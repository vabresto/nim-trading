import jsony


type
  SideKind* = enum
    Buy
    Sell


proc dumpHook*(s: var string, v: SideKind) =
  case v
  of Buy:
    s.add "buy"
  of Sell:
    s.add "sell"


proc enumHook*(v: string): SideKind =
  case v:
  of "buy": Buy
  of "sell": Sell
  else:
    raise newException(ValueError, "Can't parse SideKind: " & v)


proc parseHook*(s: string, i: var int, v: var SideKind) =
  var parsed: string
  parseHook(s, i, parsed)
  v = enumHook(parsed)
