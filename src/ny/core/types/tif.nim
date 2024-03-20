import questionable/results as qr
import results

type
  TifKind* = enum
    Day
    ClosingAuction


func parseTif*(s: string): ?!TifKind =
  case s
  of "day", "Day":
    success Day
  of "cls", "ClosingAuction":
    success ClosingAuction
  else:
    failure "Failed to parse as TifKind: " & s
