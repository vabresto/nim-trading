import ny/core/env/envs
import ny/core/trading/client as trading_client
import ny/core/trading/types


let client = initAlpacaClient(
  baseUrl="https://paper-api.alpaca.markets",
  alpacaKey=loadOrQuit("ALPACA_API_KEY"),
  alpacaSecret=loadOrQuit("ALPACA_API_SECRET"),
)

if not client.isOk:
  echo "Failed to create client"
  quit 205

let orderSentResp = client[].sendOrder(makeLimitOrder("AAPL", Buy, Gtc, 100, "50.00", "test-order-id-071"))

if orderSentResp.isOk:
  if not client[].cancelOrder(orderSentResp[].id):
    echo "Failed to cancel order"
