import jsony

import ny/core/types/tif

type
  AlpacaTifKind* = enum
    Day
    Gtc
    OpeningAuction
    ClosingAuction
    Ioc
    Fok


proc dumpHook*(s: var string, v: AlpacaTifKind) =
  case v
  of Day:
    s.add "day"
  of Gtc:
    s.add "gtc"
  of OpeningAuction:
    s.add "opg"
  of ClosingAuction:
    s.add "cls"
  of Ioc:
    s.add "ioc"
  of Fok:
    s.add "fok"


proc enumHook*(v: string): AlpacaTifKind =
  case v:
  of "day": Day
  of "gtc": Gtc
  of "opg": OpeningAuction
  of "cls": ClosingAuction
  of "ioc": Ioc
  of "fok": Fok
  else:
    raise newException(ValueError, "Can't parse AlpacaTifKind: " & v)


proc parseHook*(s: string, i: var int, v: var AlpacaTifKind) =
  var parsed: string
  parseHook(s, i, parsed)
  v = enumHook(parsed)


proc toAlpacaTif*(tif: TifKind): AlpacaTifKind =
  case tif
  of TifKind.Day:
    AlpacaTifKind.Day
  of TifKind.ClosingAuction:
    AlpacaTifKind.ClosingAuction
