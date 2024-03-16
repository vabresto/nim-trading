import ny/core/types/price
import ny/core/types/timestamp

type
  BarDetails* = object
    openPrice*: Price
    highPrice*: Price
    lowPrice*: Price
    closePrice*: Price
    volume*: int
    timestamp*: Timestamp
