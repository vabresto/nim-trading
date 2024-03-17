import ny/core/types/md/bar_details
import ny/core/types/price
import ny/core/types/timestamp


type
  MarketDataUpdateKind* = enum
    Quote
    BarMinute
    Status

  MarketDataStatusUpdateKind* = enum
    Halt
    Resume
    Other
  
  MarketDataUpdate* = object
    timestamp*: Timestamp
    case kind*: MarketDataUpdateKind
    of Quote:
      askPrice*: Price
      askSize*: int
      bidPrice*: Price
      bidSize*: int
    of BarMinute:
      bar*: BarDetails
    of Status:
      status*: MarketDataStatusUpdateKind
