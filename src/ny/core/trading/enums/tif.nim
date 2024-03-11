import jsony


type
  TifKind* = enum
    Day
    Gtc
    OpeningAuction
    ClosingAuction
    Ioc
    Fok


proc dumpHook*(s: var string, v: TifKind) =
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


proc enumHook*(v: string): TifKind =
  case v:
  of "day": Day
  of "gtc": Gtc
  of "opg": OpeningAuction
  of "cls": ClosingAuction
  of "ioc": Ioc
  of "fok": Fok
  else:
    raise newException(ValueError, "Can't parse TifKind: " & v)


proc parseHook*(s: string, i: var int, v: var TifKind) =
  var parsed: string
  parseHook(s, i, parsed)
  v = enumHook(parsed)
