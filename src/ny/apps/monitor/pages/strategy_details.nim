import std/strformat

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
import ny/core/services/postgres
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
  let details = strategyStates[strategy][symbol]

  result = fmt"""
  <div id="strategy-states" hx-swap-oob="true">
    <h2>Strategy Stats (Mode: {(if details["isSim"].getBool: "Simulation" else: "Live")})</h2>
    <table>
      <thead>
        <tr>
          <th>Key</th>
          <th>Value</th>
        </tr>
      </thead>
    <tbody>
      <tr><td>Strategy</td><td>{strategy}</td><tr>
      <tr><td>Symbol</td><td>{symbol}</td><tr>
      <tr><td>Strategy Timestamp</td><td>{details["base"]["curTime"].getTimestamp}</td></tr>
      <tr><td>Current Timestamp</td><td>{details["timestamp"].getTimestamp}</td></tr>

      <tr><td>Event Num</td><td>{details["base"]["curEventNum"].getInt}</td><tr>
      <tr><td>Position</td><td>{details["base"]["position"].getInt}</td><tr>
      <tr><td>Position VWAP</td><td>${details["base"]["positionVwap"].getFloat}</td><tr>
      <tr><td>Strategy PnL</td><td>${details["base"]["stratPnl"].getPrice}</td><tr>

      <tr>
        <td>NBBO</td>
        <td>
        Bid: {details["base"]["nbbo"]["bidSize"].getInt} @ ${details["base"]["nbbo"]["bidPrice"].getPrice} <br>
        Ask: {details["base"]["nbbo"]["askSize"].getInt} @ ${details["base"]["nbbo"]["askPrice"].getPrice} <br>
        Timestamp: {details["base"]["nbbo"]["timestamp"].getTimestamp}
        </td>
      <tr>

      <tr><td>Orders Sent</td><td>{details["base"]["numOrdersSent"].getInt}</td><tr>
      <tr><td>Orders Closed</td><td>{details["base"]["numOrdersClosed"].getInt}</td><tr>

      <tr><td>Shares Bought</td><td>{details["base"]["stratTotalSharesBought"].getInt}</td><tr>
      <tr><td>Shares Sold</td><td>{details["base"]["stratTotalSharesSold"].getInt}</td><tr>
      <tr><td>Notional Bought</td><td>${details["base"]["stratTotalNotionalBought"].getPrice}</td><tr>
      <tr><td>Notional Sold</td><td>${details["base"]["stratTotalNotionalSold"].getPrice}</td><tr>
    </tbody>
    </table>
  """

  block `PendingOrders`:
    result &= fmt"""
      <h3>Pending Orders</h3>
      <table>
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
        <td colspan="8">No Pending Orders</td>
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
    """

  block `OpenOrders`:
    result &= fmt"""
      <h3>Open Orders</h3>
      <table>
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
        <td colspan="8">No Open Orders</td>
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
    """

  block `StrategySpecificStats`:
    result &= fmt"""
      <h3>Strategy Specific Stats</h3>
      <table>
        <thead>
          <tr>
            <th>Key</th>
            <th>Value</th>
          </tr>
        </thead>
        <tbody>
          <tr><td>State</td><td>{details["strategy"]["state"].getStr}</td><tr>
          <tr><td>Num Consecutive Increases</td><td>{details["strategy"]["numConsecIncreases"].getInt}</td><tr>
          <tr>
            <td>Minute Bar</td>
            <td>
            Open: {details["strategy"]["lastBar"]["openPrice"].getPrice} <br>
            High: {details["strategy"]["lastBar"]["highPrice"].getPrice} <br>
            Low: {details["strategy"]["lastBar"]["lowPrice"].getPrice} <br>
            Close: {details["strategy"]["lastBar"]["closePrice"].getPrice} <br>
            Volume: {details["strategy"]["lastBar"]["volume"].getInt} <br>
            Timestamp: {details["strategy"]["lastBar"]["timestamp"].getTimestamp}
            </td>
          <tr>
        </tbody>
      </table>
    """

  block `FillHistory`:
    try:
      let fills = gStrategyDetailsDb.getFillHistory(getNowUtc().toDateTime().getDateStr(), strategy, symbol)
      result &= """
        <h3>Fill History</h3>
        <table>
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
            <td colspan="9">No Fill History</td>
          </tr>
        """

      for item in fills:
        result &= fmt"""
          <tr>
            <td>{item.date}</td>
            <td>{item.symbol}</td>
            <td>{item.eventTimestamp}</td>
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
      """
    except DbError:
      error "Failed to get fill history"
      result &= """<p style="color: red;">Failed to get fill history</p>"""

  result &= "</div>"


proc renderStrategyDetailsPage*(state: WsClientState): string =
  fmt"""
    <div id="page">
      {renderStrategyStates(state)}
    </div>
  """
