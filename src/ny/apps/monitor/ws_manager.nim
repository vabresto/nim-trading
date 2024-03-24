import std/rlocks
import std/options
import std/tables

import chronicles
import mummy


type
  WsClientStateKind* = enum
    Overview
    StrategyDetails

  WsClientState* = object
    case kind*: WsClientStateKind
    of Overview:
      discard
    of StrategyDetails:
      strategy*: string
      symbol*: Option[string]

  WsManagerImpl = object
    lock: RLock
    websockets {.guard: lock.}: Table[WebSocket, WsClientState]

  WsManager* = ptr WsManagerImpl

  WsSendRender* = (proc (state: WsClientState): Option[string] {.closure, gcsafe, raises: [].})


proc initWsClientState(): WsClientState =
  WsClientState(kind: Overview)


proc initWsManagerImpl(): WsManagerImpl =
  result.lock.initRLock()
  withRLock(result.lock):
    result.websockets = initTable[WebSocket, WsClientState]()


var gWsManager = initWsManagerImpl()
proc getWsManager*(): WsManager {.gcsafe.} =
  {.gcsafe.}:
    gWsManager.addr


proc addWebsocket*(manager: WsManager, ws: WebSocket) =
  withRLock(manager[].lock):
    if ws in manager[].websockets:
      warn "Adding websocket to manager, but it already exists!", ws, state=manager[].websockets[ws]
    manager[].websockets[ws] = initWsClientState()


proc delWebsocket*(manager: WsManager, ws: WebSocket) =
  withRLock(manager[].lock):
    if ws in manager[].websockets:
      manager[].websockets.del(ws)
    else:
      warn "Removing websocket from manager, but it does not exist!", ws


proc numClients*(manager: WsManager): int =
  withRLock(manager[].lock):
    return manager[].websockets.len


proc send*(manager: WsManager, f: WsSendRender) {.gcsafe, effectsOf: f, raises: [].} =
  withRLock(manager[].lock):
    for ws, state in manager[].websockets:
      {.gcsafe.}:
        let resp = f(state)
      if resp.isSome:
        ws.send(resp.get & "\n")
