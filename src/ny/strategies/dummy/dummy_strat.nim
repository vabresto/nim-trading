import chronicles

import ny/apps/runner/types
import ny/core/types/timestamp
import ny/core/types/strategy_base

type
  DummyStrategyState* = object of StrategyBase
    state*: int = 0


func initDummyStrategy*(): DummyStrategyState =
  DummyStrategyState()


func executeDummyStrategy*(state: var DummyStrategyState, update: ResponseMessage): seq[RequestMessage] =
  {.noSideEffect.}:
    info "Strategy got event", update, ts=update.timestamp

  case update.kind
  of Timer:
    discard
    # return @[RequestMessage(kind: Timer)]
  of MarketData:
    if state.state == 0:
      state.state = 1
      return @[RequestMessage(kind: Timer, timer: TimerEvent(at: "2024-03-15T03:15:48.561750000Z".parseTimestamp))]
    elif state.state == 1:
      state.state = 2
      return @[RequestMessage(kind: OrderSend, clientOrderId: "order-1", side: Buy, quantity: 5, price: "150.00")]
    elif state.state == 2:
      state.state = 3
      return @[
        RequestMessage(kind: OrderSend, clientOrderId: "order-2", side: Buy, quantity: 5, price: "140.00"),
        RequestMessage(kind: OrderSend, clientOrderId: "order-3", side: Buy, quantity: 5, price: "135.00"),
        RequestMessage(kind: OrderSend, clientOrderId: "order-4", side: Buy, quantity: 5, price: "130.00"),
        RequestMessage(kind: OrderSend, clientOrderId: "order-5", side: Buy, quantity: 5, price: "125.00"),
      ]
    elif state.state == 3:
      state.state = 4
      return @[RequestMessage(kind: OrderCancel, idToCancel: "order-2")]
    discard
  of OrderUpdate:
    discard
  return @[]
