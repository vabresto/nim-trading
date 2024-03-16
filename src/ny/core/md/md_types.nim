import ny/core/types/timestamp

type
  MarketDataUpdateKind* = enum
    Quote
    Status

  MarketDataStatusUpdateKind* = enum
    Halt
    Resume
    Other
  
  MarketDataUpdate* = object
    timestamp*: Timestamp
    case kind*: MarketDataUpdateKind
    of Quote:
      askPrice*: float
      askSize*: int
      bidPrice*: float
      bidSize*: int
    of Status:
      status*: MarketDataStatusUpdateKind
