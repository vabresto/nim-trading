## This module implements a very simple fake exchange-like matching engine.
## Because we lack L2/L3 data, we can't build a proper order book, so we'll use a cooldown based approach to simulate fills.
## 
## Overall strategy (not yet implemented):
## - If a limit order comes in at a worse price than current nbbo, we have to hold on to it
## - If an order is fillable, we will replicate Alpaca's random 10% fill rate (we can seed the RNG off of the quote's timestamp for reproduciability)

import std/algorithm
import std/options
import std/random
import std/sets
import std/tables
import std/times

import chronicles

import ny/core/types/nbbo
import ny/core/types/timestamp
import ny/core/md/md_types
import ny/apps/runner/types
import ny/core/orders/book
import ny/core/trading/types
import ny/core/types/side
import ny/core/types/price
import ny/core/types/order

type
  SimMatchingEngine* = object
    curTime*: Timestamp
    nbbo*: Nbbo
    status*: MarketDataStatusUpdateKind
    book*: OrdersBook
    orderCount*: int = 1

proc initSimMatchingEngine*(): SimMatchingEngine =
  result.book = initOrdersBook()

proc makeJitter(me: var SimMatchingEngine): Duration =
  var rng = initRand(me.curTime.epoch)
  initDuration(nanoseconds=rng.gauss(mu=5_000_000, sigma=400_000).int64) # mean 5ms, stddev 400micros

proc makeDelay(me: var SimMatchingEngine): Duration =
  var rng = initRand(me.curTime.epoch)
  initDuration(nanoseconds=rng.gauss(mu=500_000_000, sigma=50_000_000).int64) # mean 500ms, stddev 50ms

proc tryFillOrders(me: var SimMatchingEngine): seq[OrderUpdateEvent] =
  for price in me.book.sortedPrices(Buy):
    if me.nbbo.askPrice <= price:
      var exchangeSharesAvailable = me.nbbo.askSize
      var delay = me.makeDelay()

      for order in me.book.byPrice[Buy][price]:
        let fillAmt = min(order[].openInterest, exchangeSharesAvailable)
        if fillAmt > 0:
          if fillAmt == order[].openInterest:
            exchangeSharesAvailable -= fillAmt
            discard me.book.removeOrder(order.clientOrderId)
            result.add OrderUpdateEvent(
              orderId: order.id,
              clientOrderId: order.clientOrderId,
              timestamp: me.curTime + delay + me.makeJitter(),
              kind: FilledFull,
              fillAmt: fillAmt,
            )
          else:
            result.add OrderUpdateEvent(
              orderId: order.id,
              clientOrderId: order.clientOrderId,
              timestamp: me.curTime + delay + me.makeJitter(),
              kind: FilledPartial,
              fillAmt: fillAmt,
            )
          order.cumSharesFilled += fillAmt
          delay += me.makeDelay()

  for price in me.book.sortedPrices(Sell, Descending):
    if me.nbbo.bidPrice >= price:
      var exchangeSharesAvailable = me.nbbo.bidSize
      var delay = me.makeDelay()

      for order in me.book.byPrice[Sell][price]:
        let fillAmt = min(order[].openInterest, exchangeSharesAvailable)
        if fillAmt > 0:
          if fillAmt == order[].openInterest:
            exchangeSharesAvailable -= fillAmt
            discard me.book.removeOrder(order.clientOrderId)
            result.add OrderUpdateEvent(
              orderId: order.id,
              clientOrderId: order.clientOrderId,
              timestamp: me.curTime + delay + me.makeJitter(),
              kind: FilledFull,
              fillAmt: fillAmt,
            )
          else:
            result.add OrderUpdateEvent(
              orderId: order.id,
              clientOrderId: order.clientOrderId,
              timestamp: me.curTime + delay + me.makeJitter(),
              kind: FilledPartial,
              fillAmt: fillAmt,
            )
          order.cumSharesFilled += fillAmt
          delay += me.makeDelay()
  discard

proc onMarketDataEvent*(me: var SimMatchingEngine, ev: MarketDataUpdate): seq[OrderUpdateEvent] =
  me.curTime = ev.timestamp
  case ev.kind
  of Quote:
    me.nbbo = Nbbo(
      askPrice: ev.askPrice.fromFloat,
      askSize: ev.askSize,
      bidPrice: ev.bidPrice.fromFloat,
      bidSize: ev.bidSize,
    )

    result = me.tryFillOrders()
  of Status:
    me.status = ev.status

proc onRequest*(me: var SimMatchingEngine, msg: RequestMessage): seq[OrderUpdateEvent] =
  case msg.kind
  of Timer:
    return @[]
  of OrderSend:
    let orderLookup = me.book.getOrder(msg.clientOrderId)
    if orderLookup.isSome:
      error "Reject due to duplicated client order id", clientId=msg.clientOrderId
      return

    let exchId = "sim:o:" & $me.orderCount
    inc me.orderCount

    me.book.addOrder SysOrder(
      id: exchId,
      clientOrderId: msg.clientOrderId,
      side: msg.side.toSysSide,
      size: msg.quantity,
      kind: Limit,
      tif: Day,
      price: msg.price.fromString,
    )

    result.add OrderUpdateEvent(
      orderId: exchId,
      clientOrderId: msg.clientOrderId,
      timestamp: me.curTime + me.makeJitter(),
      kind: New,
    )

    result &= me.tryFillOrders()

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
