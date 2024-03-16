import std/algorithm
import std/options
import std/sets
import std/tables

import ny/core/trading/types
import ny/core/types/price
import ny/core/types/order
import ny/core/types/side

type
  OrdersBook* = object
    byId*: Table[OrderId, SysOrderRef]
    byClientId*: Table[ClientOrderId, SysOrderRef]
    byPrice*: Table[SysSideKind, Table[Price, HashSet[SysOrderRef]]]


proc initOrdersBook*(): OrdersBook =
  result.byPrice[Buy] = initTable[Price, HashSet[SysOrderRef]]()
  result.byPrice[Sell] = initTable[Price, HashSet[SysOrderRef]]()


proc addOrder*(book: var OrdersBook, order: SysOrder) =
  var managedOrder: SysOrderRef
  new(managedOrder)
  managedOrder[] = order

  book.byId[order.id] = managedOrder
  book.byClientId[order.clientOrderId] = managedOrder

  if order.price notin book.byPrice[order.side]:
    book.byPrice[order.side][order.price] = initHashSet[SysOrderRef]()
  book.byPrice[order.side][order.price].incl managedOrder


proc getOrder*(book: OrdersBook, id: string): Option[SysOrderRef] =
  if id.OrderId in book.byId:
    some book.byId[id.OrderId]
  elif id.ClientOrderId in book.byClientId:
    some book.byClientId[id.ClientOrderId]
  else:
    none[SysOrderRef]()


proc removeOrder*(book: var OrdersBook, anyId: string): Option[SysOrderRef] =
  let order = block:
    let order = book.getOrder(anyId)
    if order.isSome:
      order.get
    else:
      return none[SysOrderRef]()

  book.byId.del(order.id)
  book.byClientId.del(order.clientOrderId)
  book.byPrice[order.side][order.price].excl order
  if book.byPrice[order.side][order.price].len == 0:
    book.byPrice[order.side].del(order.price)

  some order


proc sortedPrices*(book: OrdersBook, side: SysSideKind, order: SortOrder = Ascending): seq[Price] =
  for price in book.byPrice[side].keys():
    result.add price
  
  result.sorted(order)
