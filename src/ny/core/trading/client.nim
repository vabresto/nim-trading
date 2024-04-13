import std/httpclient
import std/json
import std/net

import chronicles except toJson
import jsony
import questionable/results as qr
import results

import ny/core/trading/types

export qr
export results


type
  AlpacaClient* = object
    client*: HttpClient
    baseUrl*: string


proc initAlpacaClient*(baseUrl: string, alpacaKey: string, alpacaSecret: string): ?!AlpacaClient {.raises: [].} =
  ## Creates an http client with appropriate headers set for accessing the Alpaca API
  try:
    var client = newHttpClient()
    client.headers = newHttpHeaders({
      "Content-Type": "application/json",
      "Accept": "application/json",
      "APCA-API-KEY-ID": alpacaKey,
      "APCA-API-SECRET-KEY": alpacaSecret,
    })
    return success AlpacaClient(client: client, baseUrl: baseUrl)
  except KeyError, LibraryError, IOError:
    error "Failed to create alpaca client", error=getCurrentExceptionMsg()
    return failure "Failed to create alpaca client"
  except Exception:
    error "Generic exception; failed to create alpaca client", error=getCurrentExceptionMsg()
    return failure "Failed to create alpaca client"


proc close*(alpaca: AlpacaClient) =
  alpaca.client.close()


proc sendOrder*(alpaca: AlpacaClient, order: AlpacaOrder): ?!OrderCreateResponse {.raises: [].} =
  ## For now, we don't support replacing. Simpler to just require a cancel and send a new order.
  try:
    info "Sending order", order, asJson=order.toJson()
    let resp = alpaca.client.request(alpaca.baseUrl & "/v2/orders", httpMethod=HttpPost, body=order.toJson())
    if resp.code == Http200:
      ## Example response
      ## {
      ##  "id":"uuid",
      ##  "client_order_id":"client_order_id",
      ##  "created_at":"timestamp",
      ##  "updated_at":"timestamp",
      ##  "submitted_at":"timestamp",
      ##  "filled_at":null,
      ##  "expired_at":null,
      ##  "canceled_at":null,
      ##  "failed_at":null,
      ##  "replaced_at":null,
      ##  "replaced_by":null,
      ##  "replaces":null,
      ##  "asset_id":"b0b6dd9d-8b9b-48a9-ba46-b9d54906e415",
      ##  "symbol":"AAPL",
      ##  "asset_class":"us_equity",
      ##  "notional":null,
      ##  "qty":"100",
      ##  "filled_qty":"0",
      ##  "filled_avg_price":null,
      ##  "order_class":"",
      ##  "order_type":"limit",
      ##  "type":"limit",
      ##  "side":"buy",
      ##  "time_in_force":"gtc",
      ##  "limit_price":"50",
      ##  "stop_price":null,
      ##  "status":"accepted",
      ##  "extended_hours":false,
      ##  "legs":null,
      ##  "trail_percent":null,
      ##  "trail_price":null,
      ##  "hwm":null,
      ##  "subtag":null,
      ##  "source":null
      ## }

      let respBody = resp.body.parseJson
      let id = respBody["id"].getStr()
      let clientId = respBody["client_order_id"].getStr()
      return success OrderCreateResponse(id: id, clientOrderId: clientId, raw: respBody)
    else:
      let respBody = resp.body.parseJson
      error "Failed to send order", status=resp.status, respBody
      return failure "Failed to send order, response: " & resp.status
  except ValueError, HttpRequestError, OSError, IOError, TimeoutError, ProtocolError, KeyError, SslError:
    error "Failed to send order", error=getCurrentExceptionMsg()
    return failure "Failed to send order, exception: " & getCurrentExceptionMsg()
  except Exception:
    error "Generic exception; failed to send order", error=getCurrentExceptionMsg()
    return failure "Failed to send order, exception: " & getCurrentExceptionMsg()


proc cancelOrder*(alpaca: AlpacaClient, orderId: string): bool {.raises: [].} =
  try:
    let resp = alpaca.client.request(alpaca.baseUrl & "/v2/orders/" & orderId, httpMethod=HttpDelete)
    if resp.code != Http204:
      error "Failed to cancel order", error=resp.body
      return false
    info "Cancelled order", orderId
    return true
  except ValueError, HttpRequestError, OSError, IOError, TimeoutError, ProtocolError, KeyError, SslError:
    error "Failed to cancel order", error=getCurrentExceptionMsg()
    return false
  except Exception:
    error "Generic exception; failed to send order", error=getCurrentExceptionMsg()
    return false
