## This module implements a very simple fake exchange-like matching engine.
## Because we lack L2/L3 data, we can't build a proper order book, so we'll use a cooldown based approach to simulate fills.
## 
## Overall strategy:
## - If a limit order comes in at a worse price than current nbbo, we have to hold on to it
## - If an order is fillable, we will replicate Alpaca's random 10% fill rate (we can seed the RNG off of the quote's timestamp for reproduciability)

import std/options
import std/random
import std/times

import chronicles

import ny/core/types/nbbo
import ny/core/types/timestamp
import ny/core/md/md_types
import ny/apps/runner/types
import ny/core/orders/book
import ny/core/trading/types

type
  SimMatchingEngine* = object
    curTime*: Timestamp
    nbbo*: Nbbo
    status*: MarketDataStatusUpdateKind
    book*: OrdersBook
    orderCount*: int = 1

proc initSimMatchingEngine*(): SimMatchingEngine =
  result.book = initOrdersBook()

proc tryFillOrders(me: var SimMatchingEngine) =
  for price in me.book.sortedPrices(Buy):
    info "Considering buy price", price
  for price in me.book.sortedPrices(Sell):
    info "Considering sell price", price
  discard

proc onMarketDataEvent*(me: var SimMatchingEngine, ev: MarketDataUpdate) =
  me.curTime = ev.timestamp
  case ev.kind
  of Quote:
    me.nbbo = Nbbo(
      askPrice: ev.askPrice,
      askSize: ev.askSize,
      bidPrice: ev.bidPrice,
      bidSize: ev.bidSize,
    )

    me.tryFillOrders()
  of Status:
    me.status = ev.status

proc makeJitter(me: var SimMatchingEngine): Duration =
  var rng = initRand(me.curTime.epoch)
  initDuration(nanoseconds=rng.gauss(mu=5_000_000, sigma=400_000).int64) # mean 5ms, stddev 400micros

proc makeDelay(me: var SimMatchingEngine): Duration =
  var rng = initRand(me.curTime.epoch)
  initDuration(nanoseconds=rng.gauss(mu=500_000_000, sigma=50_000_000).int64) # mean 500ms, stddev 50ms

proc onRequest*(me: var SimMatchingEngine, msg: RequestMessage): seq[OrderUpdateEvent] =
  case msg.kind
  of Timer:
    return @[]
  of OrderSend:
    let orderLookup = me.book.getOrder(msg.clientOrderId)
    if orderLookup.isSome:
      warn "Reject due to duplicated client order id", clientId=msg.clientOrderId
      return

    let exchId = "sim:o:" & $me.orderCount
    inc me.orderCount

    me.book.addOrder Order(
      id: exchId,
      clientOrderId: msg.clientOrderId,
      symbol: "SIM",
      side: msg.side,
      size: $msg.quantity,
      kind: Limit,
      tif: Day,
      limitPrice: msg.price,
    )

    result.add OrderUpdateEvent(
      orderId: exchId,
      clientOrderId: msg.clientOrderId,
      timestamp: me.curTime + me.makeJitter(),
      kind: New,
    )

    me.tryFillOrders()

    # See if we can fill; only handle limit orders for now
    case msg.side
    of Buy:
      if msg.price >= $me.nbbo.askPrice:
        let fillAmt = min(msg.quantity, me.nbbo.askSize)
        if fillAmt == msg.quantity:
          discard me.book.removeOrder(msg.clientOrderId)
          result.add OrderUpdateEvent(
            orderId: exchId,
            clientOrderId: msg.clientOrderId,
            timestamp: me.curTime + me.makeDelay() + me.makeJitter(),
            kind: FilledFull,
            fillAmt: fillAmt,
          )
        else:
          result.add OrderUpdateEvent(
            orderId: exchId,
            clientOrderId: msg.clientOrderId,
            timestamp: me.curTime + me.makeDelay() + me.makeJitter(),
            kind: FilledPartial,
            fillAmt: fillAmt,
          )
    of Sell:
      if msg.price <= $me.nbbo.bidPrice:
        let fillAmt = min(msg.quantity, me.nbbo.bidSize)
        if fillAmt == msg.quantity:
          discard me.book.removeOrder(msg.clientOrderId)
          result.add OrderUpdateEvent(
            orderId: exchId,
            clientOrderId: msg.clientOrderId,
            timestamp: me.curTime + me.makeDelay() + me.makeJitter(),
            kind: FilledFull,
            fillAmt: fillAmt,
          )
        else:
          result.add OrderUpdateEvent(
            orderId: exchId,
            clientOrderId: msg.clientOrderId,
            timestamp: me.curTime + me.makeDelay() + me.makeJitter(),
            kind: FilledPartial,
            fillAmt: fillAmt,
          )


  of OrderCancel:
    let order = me.book.removeOrder(msg.idToCancel)

    if order.isSome:
      result.add OrderUpdateEvent(
        orderId: msg.idToCancel,
        clientOrderId: order.get.clientOrderId,
        timestamp: me.curTime + me.makeDelay() + me.makeJitter(),
        kind: Cancelled,
      )
    else:
      warn "Tried to cancel order that doesn't exist", id=msg.idToCancel
