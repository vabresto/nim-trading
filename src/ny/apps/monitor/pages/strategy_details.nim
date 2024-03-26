import std/json
import std/strformat
import std/tables
import std/times

import chronicles
import db_connector/db_postgres

import ny/core/inspector/server as inspector_server
import ny/apps/monitor/ws_manager
import ny/core/types/price
import ny/core/types/timestamp
import ny/core/db/mddb
import ny/core/env/envs


var gStrategyDetailsDb = getMdDb(loadOrQuit("MD_PG_HOST"), loadOrQuit("MD_PG_USER"), loadOrQuit("MD_PG_PASS"), loadOrQuit("MD_PG_NAME"))


proc getTimestamp(node: JsonNode): Timestamp =
  Timestamp(epoch: node["epoch"].getInt, nanos: node["nanos"].getInt)


proc getPrice(node: JsonNode): Price =
  Price(dollars: node["dollars"].getInt, cents: node["cents"].getInt)


proc renderStrategyStates*(state: WsClientState): string =
  {.gcsafe.}:
    let strategyStates = getStrategyStates()

  let strategy = state.strategy
  let symbol = state.symbol
  let date = state.date
  let details = strategyStates[date][strategy][symbol]

  let pnl = details["base"]["stratPnl"].getPrice
  let pnlColour = if pnl >= Price(dollars: 0, cents: 0):
    "green"
  else:
    "red"

  result = fmt"""
  <div id="strategy-states" hx-swap-oob="true">
    <section>
      <h2>Strategy Stats: {strategy}</h2>
      <h4>Mode: {(if details["isSim"].getBool: "Simulation" else: "Live")}</h4>

      <div class="overflow-auto">
        <table class="striped">
          <thead>
            <tr>
              <th>Key</th>
              <th>Value</th>
            </tr>
          </thead>
        <tbody>
          <tr><td>Strategy</td><td>{strategy}</td></tr>
          <tr><td>Symbol</td><td>{symbol}</td></tr>
          <tr><td>Strategy Timestamp</td><td>{details["base"]["curTime"].getTimestamp.friendlyString}</td></tr>
          <tr><td>Current Timestamp</td><td>{details["timestamp"].getTimestamp.friendlyString}</td></tr>

          <tr><td>Event Num</td><td>{details["base"]["curEventNum"].getInt}</td></tr>
          <tr><td>Position</td><td>{details["base"]["position"].getInt}</td></tr>
          <tr><td>Position VWAP</td><td>${details["base"]["positionVwap"].getFloat}</td></tr>
          <tr><td>Strategy PnL</td><td style="color: {pnlColour};">${pnl}</td></tr>

          <tr>
            <td>NBBO</td>
            <td>
  """

  if details["base"]["nbbo"] == newJNull():
    result &= """
      <span style="color: red;">No NBBOs Yet</span>
    """
  else:
    result &= fmt"""
      <strong>Bid:</strong> {details["base"]["nbbo"]["bidSize"].getInt} @ ${details["base"]["nbbo"]["bidPrice"].getPrice} <br>
      <strong>Ask:</strong> {details["base"]["nbbo"]["askSize"].getInt} @ ${details["base"]["nbbo"]["askPrice"].getPrice} <br>
      <strong>Timestamp:</strong> {details["base"]["nbbo"]["timestamp"].getTimestamp.friendlyString}
    """

  result &= fmt"""
            </td>
          </tr>

          <tr><td>Orders Sent</td><td>{details["base"]["numOrdersSent"].getInt}</td></tr>
          <tr><td>Orders Closed</td><td>{details["base"]["numOrdersClosed"].getInt}</td></tr>

          <tr><td>Shares Bought</td><td>{details["base"]["stratTotalSharesBought"].getInt}</td></tr>
          <tr><td>Shares Sold</td><td>{details["base"]["stratTotalSharesSold"].getInt}</td></tr>
          <tr><td>Notional Bought</td><td>${details["base"]["stratTotalNotionalBought"].getPrice}</td></tr>
          <tr><td>Notional Sold</td><td>${details["base"]["stratTotalNotionalSold"].getPrice}</td></tr>
        </tbody>
        </table>
      </div>
    </section>
  """

  block `PendingOrders`:
    result &= fmt"""
      <section>
        <h3>Pending Orders</h3>
        <div class="overflow-auto">
          <table class="striped">
            <thead>
              <tr>
                <th>Client Order Id</th>
                <th>Exchange Order Id</th>
                <th>TIF</th>
                <th>Kind</th>
                <th>Side</th>
                <th>Size</th>
                <th>Price</th>
                <th>Cum Shares Filled</th>
              </tr>
            </thead>
          <tbody>
    """

    if details["base"]["pendingOrders"].len == 0:
      result &= """
      <tr>
        <td colspan="8" style="text-align: center;">No Pending Orders</td>
      </tr>
      """

    for key, order in details["base"]["pendingOrders"].pairs:
      result &= fmt"""
      <tr>
        <td>{order["clientOrderId"].getStr}</td>
        <td>{order["id"].getStr}</td>
        <td>{order["tif"].getStr}</td>
        <td>{order["kind"].getStr}</td>
        <td>{order["side"].getStr}</td>
        <td>{order["size"].getInt}</td>
        <td>${order["price"].getPrice}</td>
        <td>{order["cumSharesFilled"].getInt}</td>
      </tr>
      """

    result &= """
          </tbody>
        </table>
      </div>
    </section>
    """

  block `OpenOrders`:
    result &= fmt"""
      <section>
        <h3>Open Orders</h3>
        <div class="overflow-auto">
          <table class="striped">
            <thead>
              <tr>
                <th>Client Order Id</th>
                <th>Exchange Order Id</th>
                <th>TIF</th>
                <th>Kind</th>
                <th>Side</th>
                <th>Size</th>
                <th>Price</th>
                <th>Cum Shares Filled</th>
              </tr>
            </thead>
          <tbody>
    """

    if details["base"]["openOrders"].len == 0:
      result &= """
      <tr>
        <td colspan="8" style="text-align: center;">No Open Orders</td>
      </tr>
      """

    for key, order in details["base"]["openOrders"].pairs:
      result &= fmt"""
      <tr>
        <td>{order["clientOrderId"].getStr}</td>
        <td>{order["id"].getStr}</td>
        <td>{order["tif"].getStr}</td>
        <td>{order["kind"].getStr}</td>
        <td>{order["side"].getStr}</td>
        <td>{order["size"].getInt}</td>
        <td>${order["price"].getPrice}</td>
        <td>{order["cumSharesFilled"].getInt}</td>
      </tr>
      """

    result &= """
          </tbody>
        </table>
      </div>
    </section>
    """

  block `StrategySpecificStats`:
    result &= fmt"""
      <section>
        <h3>Strategy Specific Stats</h3>
        <div class="overflow-auto">
          <table class="striped">
            <thead>
              <tr>
                <th>Key</th>
                <th>Value</th>
              </tr>
            </thead>
            <tbody>
              <tr><td>State</td><td>{details["strategy"]["state"].getStr}</td></tr>
              <tr><td>Num Consecutive Increases</td><td>{details["strategy"]["numConsecIncreases"].getInt}</td></tr>
              <tr>
                <td>Minute Bar</td>
                <td>
    """

    if details["strategy"]["lastBar"] == newJNull():
      result &= """
        <span style="color: red;">No Minute Bars Yet</span>
      """
    else:
      result &= fmt"""
        <strong>Open:</strong> {details["strategy"]["lastBar"]["openPrice"].getPrice} <br>
        <strong>High:</strong> {details["strategy"]["lastBar"]["highPrice"].getPrice} <br>
        <strong>Low:</strong> {details["strategy"]["lastBar"]["lowPrice"].getPrice} <br>
        <strong>Close:</strong> {details["strategy"]["lastBar"]["closePrice"].getPrice} <br>
        <strong>Volume:</strong> {details["strategy"]["lastBar"]["volume"].getInt} <br>
        <strong>Timestamp:</strong> {details["strategy"]["lastBar"]["timestamp"].getTimestamp.friendlyString}
      """

    result &= """
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
    """

  block `FillHistory`:
    try:
      let fills = gStrategyDetailsDb.getFillHistory(getNowUtc().toDateTime().getDateStr(), strategy, symbol)
      result &= """
        <section>
          <h3>Fill History</h3>
          <div class="overflow-auto">
            <table class="striped">
              <thead>
                <tr>
                  <th>Date</th>
                  <th>Symbol</th>
                  <th>Event Timestamp</th>
                  <th>Event Type</th>
                  <th>Client Order Id</th>
                  <th>Side</th>
                  <th>Event Fill Quantity</th>
                  <th>Event Fill Price</th>
                  <th>Order Total Fill Quantity</th>
                  <th>Position Quantity</th>
                </tr>
              </thead>
            <tbody>
      """
      
      if fills.len == 0:
        result &= """
          <tr>
            <td colspan="9" style="text-align: center;">No Fill History</td>
          </tr>
        """

      for item in fills:
        result &= fmt"""
          <tr>
            <td>{item.date}</td>
            <td>{item.symbol}</td>
            <td>{item.eventTimestamp.friendlyString}</td>
            <td>{item.eventType}</td>
            <td>{item.clientOrderId}</td>
            <td>{item.side}</td>
            <td>{item.eventFillQty}</td>
            <td>{item.eventFillPrice}</td>
            <td>{item.orderTotalFillQty}</td>
            <td>{item.positionQty}</td>
          </tr>
        """

      result &= """
            </tbody>
          </table>
        </div>
      </section>
      """
    except DbError:
      error "Failed to get fill history", err=getCurrentExceptionMsg()
      result &= """<p style="color: red;">Failed to get fill history</p>"""

  result &= "</div>"


proc renderStrategyDetailsPage*(state: WsClientState): string =
  fmt"""
    <div id="page">
      {renderStrategyStates(state)}
    </div>
  """
