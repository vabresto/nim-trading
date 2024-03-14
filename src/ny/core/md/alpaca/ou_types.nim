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
    symbol*: string
    data*: AlpacaOuWsData
    raw*: JsonNode
