import chronicles

import ny/core/types/timestamp
import ny/core/types/order
import ny/core/types/price
import ny/core/types/strategy_base

type
  DummyStrategyState* = object of StrategyBase
    state*: int = 0


func initDummyStrategy*(): DummyStrategyState =
  DummyStrategyState()


func executeDummyStrategy*(state: var DummyStrategyState, update: InputEvent): seq[OutputEvent] {.raises: [].} =
  {.noSideEffect.}:
    info "Strategy got event", update, ts=update.timestamp

  case update.kind
  of Timer:
    discard
    # return @[OutputEvent(kind: Timer)]
  of MarketData:
    if state.state == 0:
      state.state = 1
      return @[OutputEvent(kind: Timer, timer: TimerEvent(timestamp: "2024-03-15T03:15:48.561750000Z".parseTimestamp))]
    elif state.state == 1:
      state.state = 2
      return @[OutputEvent(kind: OrderSend, clientOrderId: "order-1".ClientOrderId, side: Buy, quantity: 5, price: "150.00".parsePrice)]
    elif state.state == 2:
      state.state = 3
      return @[
        OutputEvent(kind: OrderSend, clientOrderId: "order-2".ClientOrderId, side: Buy, quantity: 5, price: "140.00".parsePrice),
        OutputEvent(kind: OrderSend, clientOrderId: "order-3".ClientOrderId, side: Buy, quantity: 5, price: "135.00".parsePrice),
        OutputEvent(kind: OrderSend, clientOrderId: "order-4".ClientOrderId, side: Buy, quantity: 5, price: "130.00".parsePrice),
        OutputEvent(kind: OrderSend, clientOrderId: "order-5".ClientOrderId, side: Buy, quantity: 5, price: "125.00".parsePrice),
      ]
    elif state.state == 3:
      state.state = 4
      return @[OutputEvent(kind: OrderCancel, idToCancel: "order-2".OrderId)]
    discard
  of OrderUpdate:
    discard
  return @[]
