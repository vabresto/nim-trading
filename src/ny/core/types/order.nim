import std/hashes

import ny/core/types/order_kind
import ny/core/types/price
import ny/core/types/side
import ny/core/types/tif

type
  OrderId* {.borrow.} = distinct string
  ClientOrderId* {.borrow.} = distinct string

  SysOrder* = object
    id*: OrderId = "".OrderId # set by the remote
    clientOrderId*: ClientOrderId = "".ClientOrderId
    side*: SysSideKind
    kind*: OrderKind
    tif*: TifKind
    size*: int
    price*: Price
    cumSharesFilled*: int = 0

  SysOrderRef* = ref SysOrder

  OrderUpdateKind* = enum
    Ack
    New
    FilledPartial
    FilledFull
    Cancelled
    CancelPending


func `$`*(order: SysOrderRef): string = $(order[])
func `$`*(id: OrderId): string {.borrow.}
func `$`*(id: ClientOrderId): string {.borrow.}

func hash*(id: OrderId): Hash {.borrow.}
func hash*(id: ClientOrderId): Hash {.borrow.}
func hash*(order: SysOrderRef): Hash = hash(order[])

func `==`*(a, b: OrderId): bool {.borrow.}
func `==`*(a, b: ClientOrderId): bool {.borrow.}
func `==`*(a, b: SysOrderRef): bool =
  {.noSideEffect.}:
    echo "CALLING =="
  a.clientOrderId == b.clientOrderId

func openInterest*(order: SysOrder): int =
  order.size - order.cumSharesFilled