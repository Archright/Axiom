## Gate Definitions Feature Test — compile-time gate validation.
## See tests/features/gate_defs.feature for the specification.
##
## Contract: gate registry is loaded at compile time with all validations passing.

import std/[unittest, sets, strutils]
import gate/gate_registry
import gate/gate_types

suite "Gate Definitions — compile-time validation":
  test "gate registry loads all gates at compile time":
    ## Scenario: validate gate definitions at compile time
    ## Given the gate registry is compiled
    ## When I call allGates()
    ## Then all gates are loaded (compile-time assertions already passed)
    let gates = allGates()
    check gates.len >= 20

  test "all gates have non-empty id and name":
    ## Given the gate registry
    ## When I inspect each gate
    ## Then all gates have non-empty id and name
    for g in allGates():
      check g.id.len > 0
      check g.name.len > 0

  test "meta gates do not reference gate_hook entry":
    ## Given the gate registry
    ## When I inspect meta gates
    ## Then no meta gate references gate_hook in its entry
    for g in allGates():
      if g.layer == glMeta:
        check not g.entry.contains("gate_hook")
