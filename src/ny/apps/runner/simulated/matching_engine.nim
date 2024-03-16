## This module implements a very simple fake exchange-like matching engine.
## Because we lack L2/L3 data, we can't build a proper order book, so we'll use a cooldown based approach to simulate fills.
## 
## Overall strategy:
## - If a limit order comes in at a worse price than current nbbo, we have to hold on to it
## - If an order is fillable, we will replicate Alpaca's random 10% fill rate (we can seed the RNG off of the quote's timestamp for reproduciability)

import std/random
import std/times

import ny/core/types/nbbo
import ny/core/types/timestamp
import ny/core/md/md_types
import ny/apps/runner/types

type
  SimMatchingEngine* = object
    curTime*: Timestamp
    nbbo*: Nbbo
    status*: MarketDataStatusUpdateKind

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
    # Send new; for now, we'll reuse timestamp to make life easier
    result.add OrderUpdateEvent(
      orderId: "",
      clientOrderId: msg.clientOrderId,
      timestamp: me.curTime + me.makeJitter(),
      kind: New,
    )
    # First order we fill, second we let strategy cancel
    if msg.clientOrderId == "order-1":
      result.add OrderUpdateEvent(
        orderId: "",
        clientOrderId: msg.clientOrderId,
        timestamp: me.curTime + me.makeDelay() + me.makeJitter(),
        kind: FilledPartial,
        fillAmt: 1,
      )
  of OrderCancel:
    result.add OrderUpdateEvent(
      orderId: msg.idToCancel,
      clientOrderId: "",
      timestamp: me.curTime + me.makeDelay() + me.makeJitter(),
      kind: Cancelled,
    )
    discard
  discard
