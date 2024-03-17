import questionable/results as qr
import results

type
  SysSideKind* = enum
    Buy
    Sell

func parseSide*(s: string): ?!SysSideKind =
  case s
  of "buy", "Buy":
    success Buy
  of "sell", "Sell":
    success Sell
  else:
    failure "Failed to parse as SysSideKind: " & s
