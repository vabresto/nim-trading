import std/options
import std/strformat

import chronicles

import ny/apps/monitor/ws_manager


proc renderNumConnectedClientsImpl*(manager: WsManager): string {.gcsafe.} =
  fmt"""
  <div id="server-info" hx-swap-oob="true">
    <p>Num connected clients: {manager.numClients()}<p>
  </div>
  """

proc getRenderNumConnectedClients*(): WsSendRender =
  (proc (state: WsClientState): Option[string] {.nimcall, gcsafe, raises: [].} =
    let manager = getWsManager()
    if state.kind == Overview:
      try:
        some renderNumConnectedClientsImpl(manager)
      except ValueError:
        error "Value error trying to render num connected clients"
        none[string]()
    else:
      none[string]()
  )
