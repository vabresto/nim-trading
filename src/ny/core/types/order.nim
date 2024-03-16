import std/hashes

import ny/core/types/order_kind
import ny/core/types/price
import ny/core/types/side
import ny/core/types/tif

type
  SysOrder* = object
    id*: string = "" # set by the remote
    clientOrderId*: string = ""
    side*: SysSideKind
    kind*: OrderKind
    tif*: TifKind
    size*: int
    price*: Price
    cumSharesFilled*: int = 0

  SysOrderRef* = ref SysOrder

func `$`*(order: SysOrderRef): string = $(order[])
func hash*(order: SysOrderRef): Hash = hash(order[])

func openInterest*(order: SysOrder): int =
  order.size - order.cumSharesFilled
