import std/json


type
  AlpacaOuWsDataOrder* = object
    id*: string # remote order id
    clientOrderId*: string
    symbol*: string
    side*: string
    kind*: string
    tif*: string
    size*: string
    notional*: string
    limitPrice*: string
    extendedHours*: bool

  AlpacaOuWsData* = object
    event*: string
    timestamp*: string
    order*: AlpacaOuWsDataOrder

  AlpacaOuWsReply* = object
    stream*: string
    # symbol*: string
    data*: AlpacaOuWsData
    raw*: JsonNode

proc renameHook*(v: var AlpacaOuWsDataOrder, fieldName: var string) =
  if fieldName == "time_in_force":
    fieldName = "tif"
  elif fieldName == "order_type":
    fieldName = "kind"
  elif fieldName == "qty":
    fieldName = "size"

func symbol*(alpaca: AlpacaOuWsReply): string =
  alpaca.data.order.symbol
