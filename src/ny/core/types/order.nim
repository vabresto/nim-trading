import std/hashes

import ny/core/types/order_kind
import ny/core/types/price
import ny/core/types/side
import ny/core/types/tif

type
  # Ideally we want these to be distinct strings, but need to implement serialization so we can log json
  OrderId* {.borrow.} = string
  ClientOrderId* {.borrow.} = string

  SysOrder* = object
    ## Internal order representation
    id*: OrderId = "".OrderId # set by the remote
    clientOrderId*: ClientOrderId = "".ClientOrderId
    side*: SysSideKind
    kind*: OrderKind
    tif*: TifKind
    size*: int
    price*: Price
    cumSharesFilled*: int = 0
    done*: bool = false

  SysOrderRef* = ref SysOrder

  OrderUpdateKind* = enum
    Ack
    New
    FilledPartial
    FilledFull
    Cancelled
    CancelPending


func `$`*(order: SysOrderRef): string = $(order[])
# func `$`*(id: OrderId): string {.borrow.}
# func `$`*(id: ClientOrderId): string {.borrow.}

# func hash*(id: OrderId): Hash {.borrow.}
# func hash*(id: ClientOrderId): Hash {.borrow.}
func hash*(order: SysOrderRef): Hash = hash(order[])

# func `==`*(a, b: OrderId): bool {.borrow.}
# func `==`*(a, b: ClientOrderId): bool {.borrow.}

func openInterest*(order: SysOrder): int =
  order.size - order.cumSharesFilled