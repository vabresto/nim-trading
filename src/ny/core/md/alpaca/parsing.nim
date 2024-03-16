import ny/core/md/md_types

proc parseAlpacaMdTradingStatus*(statusCode: string): MarketDataStatusUpdateKind =
  case statusCode
  of "2", "H":
    Halt
  of "3", "T":
    Resume
  else:
    Other
