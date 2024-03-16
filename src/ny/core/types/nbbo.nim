import ny/core/types/price
import ny/core/types/timestamp

type
  Nbbo* = object
    askPrice*: Price
    bidPrice*: Price
    askSize*: int
    bidSize*: int
    timestamp*: Timestamp
