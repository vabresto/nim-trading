import std/options


type
  AlpacaAuthError* = object of ValueError
    code*: int

  AlpacaMdWsReplyKind* = enum
    ConnectOk
    AuthOk
    AuthErr
    Subscription

    Trade
    Quote

    BarMinute
    BarDay
    BarUpdated

    TradeCorrection
    TradeCancel

    PriceBands

    TradingStatus

  SubscriptionDetails* = object
    trades*: seq[string]
    quotes*: seq[string]
    bars*: seq[string]
    updatedBars*: seq[string]
    dailyBars*: seq[string]
    statuses*: seq[string]
    lulds*: seq[string]
    corrections*: seq[string]
    cancelErrors*: seq[string]

  TradeDetails* = object
    symbol*: string
    tradeId*: int
    exchange*: string
    price*: float
    size*: int
    tradeConditions*: seq[string]
    timestamp*: string
    tape*: string
    vwap*: float

  QuoteDetails* = object
    symbol*: string
    askExchange*: string
    askPrice*: float
    askSize*: int
    bidExchange*: string
    bidPrice*: float
    bidSize*: int
    quoteConditions*: seq[string]
    timestamp*: string
    tape*: string

  BarDetails* = object
    symbol*: string
    openPrice*: float
    highPrice*: float
    lowPrice*: float
    closePrice*: float
    volume*: int
    timestamp*: string

  TradeCorrectionDetails* = object
    symbol*: string
    exchange*: string
    origTradeId*: int
    origTradePrice*: float
    origTradeSize*: int
    origTradeConditions*: seq[string]
    corrTradeId*: int
    corrTradePrice*: float
    corrTradeSize*: int
    corrTradeConditions*: seq[string]
    timestamp*: string
    tape*: string

  TradeCancelDetails* = object
    symbol*: string
    tradeId*: int
    tradeExchange*: string
    tradePrice*: float
    tradeSize*: int
    action*: string
    timestamp*: string
    tape*: string

  PriceBandDetails* = object
    symbol*: string
    upPrice*: string
    downPrice*: string
    indicator*: string
    timestamp*: string
    tape*: string

  TradingStatusDetails* = object
    symbol*: string
    statusCode*: string
    statusMsg*: string
    reasonCode*: string
    reasonMsg*: string
    timestamp*: string
    tape*: string

  AlpacaMdWsReply* = object
    case kind*: AlpacaMdWsReplyKind
    of ConnectOk, AuthOk:
      discard
    of AuthErr:
      code*: int
      authErrMsg*: string
    of Subscription:
      subscription*: SubscriptionDetails
    of Trade:
      trade*: TradeDetails
    of Quote:
      quote*: QuoteDetails
    of BarMinute, BarDay, BarUpdated:
      bar*: BarDetails
    of TradeCorrection:
      tradeCorrection*: TradeCorrectionDetails
    of TradeCancel:
      tradeCancel*: TradeCancelDetails
    of PriceBands:
      priceBands*: PriceBandDetails
    of TradingStatus:
      tradingStatus*: TradingStatusDetails


func getSymbol*(reply: AlpacaMdWsReply): Option[string] =
  case reply.kind
  of ConnectOk, AuthOk, AuthErr, Subscription:
    none[string]()
  of Trade:
    some reply.trade.symbol
  of Quote:
    some reply.quote.symbol
  of BarMinute, BarDay, BarUpdated:
    some reply.bar.symbol
  of TradeCorrection:
    some reply.tradeCorrection.symbol
  of TradeCancel:
    some reply.tradeCancel.symbol
  of PriceBands:
    some reply.priceBands.symbol
  of TradingStatus:
    some reply.tradingStatus.symbol


func getTimestamp*(reply: AlpacaMdWsReply): Option[string] =
  case reply.kind
  of ConnectOk, AuthOk, AuthErr, Subscription:
    none[string]()
  of Trade:
    some reply.trade.timestamp
  of Quote:
    some reply.quote.timestamp
  of BarMinute, BarDay, BarUpdated:
    some reply.bar.timestamp
  of TradeCorrection:
    some reply.tradeCorrection.timestamp
  of TradeCancel:
    some reply.tradeCancel.timestamp
  of PriceBands:
    some reply.priceBands.timestamp
  of TradingStatus:
    some reply.tradingStatus.timestamp
