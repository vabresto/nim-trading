import jsony

import ny/core/types/side

type
  AlpacaSideKind* = enum
    Buy
    Sell


proc dumpHook*(s: var string, v: AlpacaSideKind) =
  case v
  of Buy:
    s.add "buy"
  of Sell:
    s.add "sell"


proc enumHook*(v: string): AlpacaSideKind =
  case v:
  of "buy": Buy
  of "sell": Sell
  else:
    raise newException(ValueError, "Can't parse AlpacaSideKind: " & v)


proc parseHook*(s: string, i: var int, v: var AlpacaSideKind) =
  var parsed: string
  parseHook(s, i, parsed)
  v = enumHook(parsed)


proc toSysSide*(s: AlpacaSideKind): SysSideKind =
  case s
  of Buy:
    SysSideKind.Buy
  of Sell:
    SysSideKind.Sell


proc toAlpacaSide*(s: SysSideKind): AlpacaSideKind =
  case s
  of SysSideKind.Buy:
    AlpacaSideKind.Buy
  of SysSideKind.Sell:
    AlpacaSideKind.Sell
