import std/strformat

import chronicles
import mummy
import mummy/routers

import ny/apps/monitor/ws_manager
import ny/apps/monitor/pages/overview


proc indexHandler(request: Request) =
  request.respond(200, @[("Content-Type", "text/html")], fmt"""
  <head>
    <script src="https://unpkg.com/htmx.org@1.9.11" integrity="sha384-0gxUXCCR8yv9FM2b+U3FDbsKthCI66oH5IA9fHppQq9DDMHuMauqq1ZHBpJxQ0J0" crossorigin="anonymous"></script>
    <script src="https://unpkg.com/htmx.org@1.9.11/dist/ext/ws.js"></script>
  </head>

  <body>
    <div hx-ext="ws" ws-connect="/ws">
      <form id="change-page" ws-send>
        <input type="hidden" id="type" name="type" value="change-page">
        
        <input type="radio" id="new-page-overview" name="new-page" value="overview">
        <label for="new-page-overview">Overview</label><br>
        <input type="radio" id="new-page-strategy-details" name="new-page" value="strategy-details">
        <label for="new-page-strategy-details">Strategy Details</label><br>

        <button type="submit">Submit</button>
      </form>

      {renderOverviewPage()}
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
    warn "Unexpectedly got message from client websocket", event, message
    echo message.kind, ": ", message.data
    # TODO: We do want to start handling getting messages from clients
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
