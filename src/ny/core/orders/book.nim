import std/algorithm
import std/options
import std/sets
import std/tables

import ny/core/trading/types

type
  OrdersBook* = object
    byId*: Table[string, AlpacaOrderRef]
    byClientId*: Table[string, AlpacaOrderRef]
    byPrice*: Table[SideKind, Table[string, HashSet[AlpacaOrderRef]]]


proc initOrdersBook*(): OrdersBook =
  result.byPrice[Buy] = initTable[string, HashSet[AlpacaOrderRef]]()
  result.byPrice[Sell] = initTable[string, HashSet[AlpacaOrderRef]]()


proc addOrder*(book: var OrdersBook, order: AlpacaOrder) =
  var managedOrder: AlpacaOrderRef
  new(managedOrder)
  managedOrder[] = order

  book.byId[order.id] = managedOrder
  book.byClientId[order.clientOrderId] = managedOrder

  if order.limitPrice notin book.byPrice[order.side]:
    book.byPrice[order.side][order.limitPrice] = initHashSet[AlpacaOrderRef]()
  book.byPrice[order.side][order.limitPrice].incl managedOrder


proc getOrder*(book: OrdersBook, id: string): Option[AlpacaOrderRef] =
  if id in book.byId:
    some book.byId[id]
  elif id in book.byClientId:
    some book.byClientId[id]
  else:
    none[AlpacaOrderRef]()


proc removeOrder*(book: var OrdersBook, anyId: string): Option[AlpacaOrderRef] =
  let order = block:
    let order = book.getOrder(anyId)
    if order.isSome:
      order.get
    else:
      return none[AlpacaOrderRef]()

  book.byId.del(order.id)
  book.byClientId.del(order.clientOrderId)
  book.byPrice[order.side][order.limitPrice].excl order
  if book.byPrice[order.side][order.limitPrice].len == 0:
    book.byPrice[order.side].del(order.limitPrice)

  some order


proc sortedPrices*(book: OrdersBook, side: SideKind, order: SortOrder = Ascending): seq[string] =
  for price in book.byPrice[side].keys():
    result.add price
  
  result.sorted(order)
