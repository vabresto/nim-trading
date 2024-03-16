import std/options
import std/sets
import std/tables

import ny/core/trading/types

type
  OrdersBook* = object
    byId*: Table[string, OrderRef]
    byClientId*: Table[string, OrderRef]
    byPrice*: Table[string, HashSet[OrderRef]]


proc addOrder*(book: var OrdersBook, order: Order) =
  var managedOrder: OrderRef
  new(managedOrder)
  managedOrder[] = order

  book.byId[order.id] = managedOrder
  book.byClientId[order.clientOrderId] = managedOrder

  if order.limitPrice notin book.byPrice:
    book.byPrice[order.limitPrice] = initHashSet[OrderRef]()
  book.byPrice[order.limitPrice].incl managedOrder


proc getOrder*(book: OrdersBook, id: string): Option[OrderRef] =
  if id in book.byId:
    some book.byId[id]
  elif id in book.byClientId:
    some book.byClientId[id]
  else:
    none[OrderRef]()


proc removeOrder*(book: var OrdersBook, anyId: string): Option[OrderRef] =
  let order = block:
    let order = book.getOrder(anyId)
    if order.isSome:
      order.get
    else:
      return none[OrderRef]()

  book.byId.del(order.id)
  book.byClientId.del(order.clientOrderId)
  book.byPrice[order.limitPrice].excl order
  if book.byPrice[order.limitPrice].len == 0:
    book.byPrice.del(order.limitPrice)

  some order
