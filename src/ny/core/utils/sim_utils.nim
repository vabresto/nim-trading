const kIsSimulation = false


func isSimuluation*(): bool =
  {.noSideEffect.}:
    kIsSimulation


func getInitialStreamId*(): string =
  if kIsSimulation:
    "0"
  else:
    "$"
