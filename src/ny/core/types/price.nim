import std/math
import std/strutils

type
  Price* = object
    dollars*: int
    cents*: range[0 .. 99]

func `$`*(p: Price): string = $p.dollars & "." & $p.cents

func `<`*(a, b: Price): bool =
  if a.dollars == b.dollars:
    a.cents < b.cents
  else:
    a.dollars < b.dollars

func `<=`*(a, b: Price): bool =
  if a.dollars == b.dollars:
    a.cents <= b.cents
  else:
    a.dollars < b.dollars

func `+`*(a, b: Price): Price =
  let totalCents = a.cents + b.cents
  let totalDollars = a.dollars + b.dollars
  Price(dollars: floorDiv(totalDollars + totalCents, 100), cents: floorMod(totalCents, 100))

func `-`*(a, b: Price): Price =
  a + Price(dollars: -b.dollars, cents: b.cents)

func `*`*(a: Price, b: int): Price =
  let allCents = (a.dollars * 100 + a.cents) * b
  Price(dollars: floorDiv(allCents, 100), cents: floorMod(allCents, 100))

func fromFloat*(price: float): Price =
  let allCents = (price * 100).int
  Price(dollars: floorDiv(allCents, 100), cents: floorMod(allCents, 100))

func fromString*(price: string): Price =
  if "." in price:
    let splitted = price.split(".")
    Price(dollars: splitted[0].parseInt, cents: splitted[1].parseInt)
  else:
    Price(dollars: price.parseInt, cents: 0)
