## This module sends out market requests received from the models to the alpaca rest api

import chronicles
import questionable/results as qr
import results
import threading/channels

import ny/apps/runner/live/chans
import ny/core/types/strategy_base
import ny/apps/runner/live/timer_types
import ny/core/env/envs
import ny/core/trading/client as trading_client
import ny/core/trading/types

logScope:
  topics = "sys sys:live live-output"

var marketConnectorThread: Thread[seq[string]]
var marketConnectorThreadCreated = false

proc marketOutputThreadEx(symbols: seq[string]) {.thread, raises: [].} =
  # Init, and store mapping of chan + symbol
  var chans = newSeq[tuple[symbol: string, chan: Chan[OutputEvent]]]()
  for symbol in symbols:
    try:
      let (_, oc) = getChannelsForSymbol(symbol)
      chans.add (symbol, oc)
    except KeyError:
      error "Failed to get channels for symbol; terminating", symbol
      quit 200

  var timerChan = getTimerChannel()

  info "Creating alpaca http client ..."
  let client = initAlpacaClient(
    baseUrl="https://paper-api.alpaca.markets",
    alpacaKey=loadOrQuit("ALPACA_API_KEY"),
    alpacaSecret=loadOrQuit("ALPACA_API_SECRET"),
  )

  if not client.isOk:
    echo "Failed to create client"
    quit 205
  info "Alpaca http client created"

  info "Starting output loop ..."
  while true:
    for (symbol, oc) in chans:
      var resp: OutputEvent
      if oc.tryRecv(resp):
        case resp.kind
        of Timer:
          timerChan.send(TimerChanMsg(symbol: symbol, kind: CreateTimer, create: RequestTimer(timer: resp.timer)))
        of OrderSend:
          let orderSentResp = client[].sendOrder(makeLimitOrder(symbol, resp.side.toAlpacaSide, Day, resp.quantity, $resp.price, resp.clientOrderId.string))
          if orderSentResp.isErr:
            error "Failed to send order creation command", cmd=resp, err=orderSentResp.error.msg
        of OrderCancel:
          let orderCancelResp = client[].cancelOrder(resp.idToCancel.string)
          if not orderCancelResp:
            error "Failed to send order cancellation command", cmd=resp


proc createMarketOutputThread*(symbols: seq[string]) =
  if not marketConnectorThreadCreated:
    info "Creating market output thread ...", symbols
    createThread(marketConnectorThread, marketOutputThreadEx, symbols)
    marketConnectorThreadCreated = true
