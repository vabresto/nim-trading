## This module implements a very simple fake exchange-like matching engine.
## Because we lack L2/L3 data, we can't build a proper order book, so we'll use a cooldown based approach to simulate fills.
## 
## Overall strategy (not yet implemented):
## - If a limit order comes in at a worse price than current nbbo, we have to hold on to it
## - If an order is fillable, we will replicate Alpaca's random 10% fill rate (we can seed the RNG off of the quote's timestamp for reproduciability)

import std/algorithm
import std/options
import std/random
import std/tables
import std/times

import chronicles

import ny/core/md/md_types
import ny/core/trading/enums/side
import ny/core/trading/types
import ny/core/types/book
import ny/core/types/nbbo
import ny/core/types/order
import ny/core/types/price
import ny/core/types/side
import ny/core/types/strategy_base
import ny/core/types/timestamp


logScope:
  topics = "sys sys:sim sim-matching-engine"

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

proc tryFillOrders(me: var SimMatchingEngine): seq[InputEvent] =
  for price in me.book.sortedPrices(Buy):
    info "Calling tryFillOrders", nnboPrice=me.nbbo.askPrice, orderPrice=price
    if me.nbbo.askPrice <= price:
      var exchangeSharesAvailable = me.nbbo.askSize
      var delay = me.makeDelay()

      for (id, order) in me.book.byPrice[Buy][price].pairs:
        let fillAmt = min(order[].openInterest, exchangeSharesAvailable)
        if fillAmt > 0:
          if fillAmt == order[].openInterest:
            exchangeSharesAvailable -= fillAmt
            discard me.book.removeOrder(order.id.string)
            result.add InputEvent(kind: OrderUpdate, ou: SysOrderUpdateEvent(
              orderId: order.id,
              clientOrderId: order.clientOrderId,
              timestamp: me.curTime + delay + me.makeJitter(),
              kind: FilledFull,
              fillAmt: fillAmt,
            ))
          else:
            result.add InputEvent(kind: OrderUpdate, ou: SysOrderUpdateEvent(
              orderId: order.id,
              clientOrderId: order.clientOrderId,
              timestamp: me.curTime + delay + me.makeJitter(),
              kind: FilledPartial,
              fillAmt: fillAmt,
            ))
          order.cumSharesFilled += fillAmt
          delay += me.makeDelay()

  for price in me.book.sortedPrices(Sell, Descending):
    if me.nbbo.bidPrice >= price:
      var exchangeSharesAvailable = me.nbbo.bidSize
      var delay = me.makeDelay()

      for (id, order) in me.book.byPrice[Sell][price].pairs:
        let fillAmt = min(order[].openInterest, exchangeSharesAvailable)
        if fillAmt > 0:
          if fillAmt == order[].openInterest:
            exchangeSharesAvailable -= fillAmt
            discard me.book.removeOrder(order.id.string)
            result.add InputEvent(kind: OrderUpdate, ou: SysOrderUpdateEvent(
              orderId: order.id,
              clientOrderId: order.clientOrderId,
              timestamp: me.curTime + delay + me.makeJitter(),
              kind: FilledFull,
              fillAmt: fillAmt,
            ))
          else:
            result.add InputEvent(kind: OrderUpdate, ou: SysOrderUpdateEvent(
              orderId: order.id,
              clientOrderId: order.clientOrderId,
              timestamp: me.curTime + delay + me.makeJitter(),
              kind: FilledPartial,
              fillAmt: fillAmt,
            ))
          order.cumSharesFilled += fillAmt
          delay += me.makeDelay()
  discard

proc onMarketDataEvent*(me: var SimMatchingEngine, ev: MarketDataUpdate): seq[InputEvent] =
  me.curTime = ev.timestamp
  case ev.kind
  of Quote:
    me.nbbo = Nbbo(
      askPrice: ev.askPrice,
      askSize: ev.askSize,
      bidPrice: ev.bidPrice,
      bidSize: ev.bidSize,
    )
    result = me.tryFillOrders()
  of BarMinute:
    discard
  of Status:
    me.status = ev.status

proc onRequest*(me: var SimMatchingEngine, msg: OutputEvent): seq[InputEvent] =
  case msg.kind
  of Timer:
    return @[InputEvent(kind: Timer, timer: msg.timer)]
  of OrderSend:
    let orderLookup = me.book.getOrder(msg.clientOrderId.string)
    if orderLookup.isSome:
      error "Reject due to duplicated client order id", clientId=msg.clientOrderId
      return

    let exchId = ("sim:o:" & $me.orderCount).OrderId
    inc me.orderCount

    me.book.addOrder SysOrder(
      id: exchId,
      clientOrderId: msg.clientOrderId,
      side: msg.side,
      size: msg.quantity,
      kind: Limit,
      tif: Day,
      price: msg.price,
    )

    result.add InputEvent(kind: OrderUpdate, ou: SysOrderUpdateEvent(
      orderId: exchId,
      clientOrderId: msg.clientOrderId,
      timestamp: me.curTime + me.makeJitter(),
      kind: New,
      side: msg.side,
      size: msg.quantity,
      tif: Day,
      price: msg.price,
    ))

    result &= me.tryFillOrders()

  of OrderCancel:
    let order = me.book.removeOrder(msg.idToCancel.string)

    if order.isSome:
      result.add InputEvent(kind: OrderUpdate, ou: SysOrderUpdateEvent(
        orderId: msg.idToCancel,
        clientOrderId: order.get.clientOrderId,
        timestamp: me.curTime + me.makeDelay() + me.makeJitter(),
        kind: Cancelled,
      ))
    else:
      warn "Tried to cancel order that doesn't exist", id=msg.idToCancel
