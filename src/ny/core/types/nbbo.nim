import ny/core/types/timestamp

type
  Nbbo* = object
    askPrice*: float
    bidPrice*: float
    askSize*: int
    bidSize*: int
    timestamp*: Timestamp
