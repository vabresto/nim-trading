## This module sends out market requests received from the models to the alpaca rest api
import std/os
import std/rlocks

import chronicles
import questionable/results as qr
import results
import threading/channels

import ny/apps/runner/live/chans
import ny/core/types/strategy_base
import ny/core/types/tif
import ny/apps/runner/live/timer_types
import ny/core/env/envs
import ny/core/trading/client as trading_client
import ny/core/trading/types
import ny/core/trading/enums/tif

logScope:
  topics = "sys sys:live live-output"

var marketConnectorThread: Thread[seq[string]]
var marketConnectorLock: RLock
var marketConnectorThreadCreated {.guard: marketConnectorLock.} = false

marketConnectorLock.initRLock()

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
    var processedAny = false
    for (symbol, oc) in chans:
      var resp: OutputEvent
      if oc.tryRecv(resp):
        processedAny = true
        info "Got output event", outputEvent=resp
        case resp.kind
        of Timer:
          timerChan.send(TimerChanMsg(symbol: symbol, kind: CreateTimer, create: RequestTimer(timer: resp.timer)))
        of OrderSend:
          let orderSentResp = case resp.orderKind:
            of Limit:
              client[].sendOrder(makeLimitOrder(symbol, resp.side.toAlpacaSide, resp.tif.toAlpacaTif, resp.quantity, resp.price, resp.clientOrderId.string))
            of Market:
              if resp.tif == TifKind.Day:
                client[].sendOrder(makeMarketOrder(symbol, resp.side.toAlpacaSide, resp.quantity, resp.clientOrderId.string))
              else:
                client[].sendOrder(makeMarketOnCloseOrder(symbol, resp.side.toAlpacaSide, resp.quantity, resp.clientOrderId.string))
          if orderSentResp.isErr:
            error "Failed to send order creation command", cmd=resp, err=orderSentResp.error.msg
        of OrderCancel:
          let orderCancelResp = client[].cancelOrder(resp.idToCancel.string)
          if not orderCancelResp:
            error "Failed to send order cancellation command", cmd=resp

    if not processedAny:
      # Add a sleep so we don't max out the cores
      # Obviously slows down trading but not practically an issue for this project
      sleep(1)


proc createMarketOutputThread*(symbols: seq[string]) =
  withRLock(marketConnectorLock):
    if not marketConnectorThreadCreated:
      marketConnectorThreadCreated = true
      info "Creating market output thread ...", symbols
      createThread(marketConnectorThread, marketOutputThreadEx, symbols)
      
