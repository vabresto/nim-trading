import std/json

import chronicles
import mummy
import mummy/routers

import ny/apps/monitor/ws_manager
import ny/apps/monitor/pages/overview
import ny/apps/monitor/pages


proc indexHandler(request: Request) =
  let initalState = WsClientState(kind: Overview)

  var response = """
  <head>
    <title>Nim Trading Dashboard</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">

    <!-- borrow a nice icon to use as our own favicon -->
    <link rel="icon" href="https://www.favicon.studio/favicon.ico">
    <link rel="apple-touch-icon" href="https://www.favicon.studio/android-chrome-192x192.png">
    <meta itemprop="image" content="https://www.favicon.studio/android-chrome-192x192.png">
    <meta property="og:image" content="https://www.favicon.studio/android-chrome-192x192.png">

    <script src="https://unpkg.com/htmx.org@1.9.11" integrity="sha384-0gxUXCCR8yv9FM2b+U3FDbsKthCI66oH5IA9fHppQq9DDMHuMauqq1ZHBpJxQ0J0" crossorigin="anonymous"></script>
    <script src="https://unpkg.com/htmx.org@1.9.11/dist/ext/ws.js"></script>
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/@picocss/pico@2/css/pico.min.css"/>
  </head>

  <body hx-ext="ws" ws-connect="/ws" style="padding: 20px;">
    <header>
      <nav style="width: 95%">
        <ul>
          <li><a class="contrast" ws-send hx-vals='{"type": "change-page", "new-page": "overview"}'><strong>NIM TRADING</strong></a></li>
        </ul>
        <ul>
          <li><a ws-send hx-vals='{"type": "change-page", "new-page": "overview"}'>Overview</a></li>
          <li><a ws-send hx-vals='{"type": "change-page", "new-page": "strategy-list"}'>Strategies</a></li>
        </ul>
      </nav>
    </header>
    <main>
  """

  response &= renderOverviewPage(initalState)
  response &= """
    </main>
  </body>
  """

  request.respond(200, @[("Content-Type", "text/html")], response)


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
    if message.data.len == 0:
      # Not sure why this happens sometimes, heartbeat?
      return
    error "Unexpectedly got error message from client websocket", event, message
  of CloseEvent:
    let manager = getWsManager()
    manager.delWebsocket(websocket)


proc makeServer*(): Server =
  var router: Router
  router.get("/", indexHandler)
  router.get("/ws", upgradeHandler)
  
  newServer(router, websocketHandler)
