import chronicles

var gIsSimulation = false


proc setIsSimulation*(sim: bool) =
  info "Set simulation flag", sim
  gIsSimulation = sim


func isSimuluation*(): bool =
  {.noSideEffect.}:
    gIsSimulation


func getInitialStreamId*(): string =
  {.noSideEffect.}:
    if gIsSimulation:
      "0"
    else:
      "$"
