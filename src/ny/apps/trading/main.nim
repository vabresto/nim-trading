import ny/core/env/envs
import ny/core/trading/client as trading_client
import ny/core/trading/types
import ny/core/types/price


let client = initAlpacaClient(
  baseUrl="https://paper-api.alpaca.markets",
  alpacaKey=loadOrQuit("ALPACA_API_KEY"),
  alpacaSecret=loadOrQuit("ALPACA_API_SECRET"),
)

if not client.isOk:
  echo "Failed to create client"
  quit 205

# let orderSentResp = client[].sendOrder(makeLimitOrder("AAPL", Buy, Gtc, 100, Price(dollars: 50, cents: 0), "test-order-id-096"))
# let orderSentResp = client[].sendOrder(makeMarketOrder("AAPL", Sell, 100, "test-order-id-097".string))
let orderSentResp = client[].sendOrder(makeMarketOnCloseOrder("AAPL", Buy, 100, "test-order-id-098"))

if orderSentResp.isOk:
  if not client[].cancelOrder(orderSentResp[].id):
    echo "Failed to cancel order"
