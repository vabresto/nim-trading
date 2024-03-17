import questionable/results as qr
import results

type
  TifKind* = enum
    Day

func parseTif*(s: string): ?!TifKind =
  case s
  of "day", "Day":
    success Day
  else:
    failure "Failed to parse as TifKind: " & s
