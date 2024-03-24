import std/json
import std/strformat

import chronicles
import mummy
import mummy/routers

import ny/apps/monitor/ws_manager
import ny/apps/monitor/pages/overview
import ny/apps/monitor/pages


proc indexHandler(request: Request) =
  let initalState = WsClientState(kind: Overview)

  request.respond(200, @[("Content-Type", "text/html")], fmt"""
  <head>
    <script src="https://unpkg.com/htmx.org@1.9.11" integrity="sha384-0gxUXCCR8yv9FM2b+U3FDbsKthCI66oH5IA9fHppQq9DDMHuMauqq1ZHBpJxQ0J0" crossorigin="anonymous"></script>
    <script src="https://unpkg.com/htmx.org@1.9.11/dist/ext/ws.js"></script>
  </head>

  <body>
    <div hx-ext="ws" ws-connect="/ws">
      <form id="change-page" ws-send>
        <input type="hidden" id="type" name="type" value="change-page">
        
        <input type="radio" id="new-page-overview" name="new-page" value="overview" checked>
        <label for="new-page-overview">Overview</label><br>
        <input type="radio" id="new-page-strategy-list" name="new-page" value="strategy-list">
        <label for="new-page-strategy-list">Strategy List</label><br>

        <button type="submit">Submit</button>
      </form>

      {renderOverviewPage(initalState)}
    </div>
  </body>
  """)


proc upgradeHandler(request: Request) =
  let websocket = request.upgradeToWebSocket()
  let manager = getWsManager()
  manager.addWebsocket(websocket)


proc websocketHandler(
  websocket: WebSocket,
  event: WebSocketEvent,
  message: Message
) {.gcsafe.} =
  case event:
  of OpenEvent:
    discard
  of MessageEvent:
    try:
      echo message.kind, ": ", message.data
      let parsed = message.data.parseJson

      if "type" in parsed and parsed["type"].getStr == "change-page":
        if "new-page" in parsed:
          let manager = getWsManager()
          case parsed["new-page"].getStr
          of "overview":
            manager.setState(websocket, WsClientState(kind: Overview))
          of "strategy-list":
            manager.setState(websocket, WsClientState(kind: StrategyList))
          of "strategy-details":
            manager.setState(websocket, WsClientState(kind: StrategyDetails, symbol: parsed["symbol"].getStr, strategy: parsed["strategy"].getStr))
          else:
            error "Unknown page requested", page=parsed["new-page"].getStr
            return

          manager.send(websocket, renderPage)
    except Exception:
      error "Unhandled exception handling websocket message", message, err=getCurrentExceptionMsg()
  of ErrorEvent:
    error "Unexpectedly got error message from client websocket", event, message
  of CloseEvent:
    let manager = getWsManager()
    manager.delWebsocket(websocket)


proc makeServer*(): Server =
  var router: Router
  router.get("/", indexHandler)
  router.get("/ws", upgradeHandler)
  
  newServer(router, websocketHandler)
