## This module sends out market requests received from the models to the alpaca rest api
import std/rlocks

import chronicles
import questionable/results as qr
import results
import threading/channels

import ny/apps/runner/live/chan_types
import ny/apps/runner/live/chans
import ny/core/types/strategy_base
import ny/core/types/tif
import ny/core/types/timestamp
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
  var timerChan = getTimerChannel()
  var outChan = getTheOutputChannel()

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
    var resp: OutputEventMsg
    outChan.recv(resp)
    trace "Got output event", outputEvent=resp
    case resp.event.kind
    of Timer:
      timerChan.send(TimerChanMsg(symbol: resp.symbol, timer: resp.event.timer))
    of OrderSend:
      let orderSentResp = case resp.event.orderKind:
        of Limit:
          client[].sendOrder(makeLimitOrder(resp.symbol, resp.event.side.toAlpacaSide, resp.event.tif.toAlpacaTif, resp.event.quantity, resp.event.price, resp.event.clientOrderId.string))
        of Market:
          if resp.event.tif == TifKind.Day:
            client[].sendOrder(makeMarketOrder(resp.symbol, resp.event.side.toAlpacaSide, resp.event.quantity, resp.event.clientOrderId.string))
          else:
            client[].sendOrder(makeMarketOnCloseOrder(resp.symbol, resp.event.side.toAlpacaSide, resp.event.quantity, resp.event.clientOrderId.string))
      if orderSentResp.isErr:
        error "Failed to send order creation command", cmd=resp, err=orderSentResp.error.msg
        try:
          let ic = getChannelForSymbol(resp.symbol)
          ic.send(InputEvent(kind: CommandFailed, cmd: FailedCommand(timestamp: getNowUtc(), kind: OrderSendFailed, clientOrderId: resp.event.clientOrderId)))
        except KeyError:
          error "Failed to get channel for symbol", symbol=resp.symbol
        except Exception:
          error "Failed to send OrderSendFailed message", clientOrderId=resp.event.clientOrderId.string
    of OrderCancel:
      let orderCancelResp = client[].cancelOrder(resp.event.idToCancel.string)
      if not orderCancelResp:
        error "Failed to send order cancellation command", cmd=resp
        try:
          let ic = getChannelForSymbol(resp.symbol)
          ic.send(InputEvent(kind: CommandFailed, cmd: FailedCommand(timestamp: getNowUtc(), kind: OrderCancelFailed, idToCancel: resp.event.idToCancel)))
        except KeyError:
          error "Failed to get channel for symbol", symbol=resp.symbol
        except Exception:
          error "Failed to send OrderCancelFailed message", idToCancel=resp.event.idToCancel.string

proc createMarketOutputThread*(symbols: seq[string]) =
  withRLock(marketConnectorLock):
    if not marketConnectorThreadCreated:
      marketConnectorThreadCreated = true
      info "Creating market output thread ...", symbols
      createThread(marketConnectorThread, marketOutputThreadEx, symbols)
      
