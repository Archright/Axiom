## Gate Admin Feature Test — CLI for managing gate policies.
## See tests/features/gate_admin.feature for the specification.
##
## Contract: loadGateIdsFromManifest returns all registered gate IDs.

import std/[unittest, sets]
import gate/gate_registry
import gate/gate_contract

suite "Gate Admin — gate policy management":
  test "allGates returns non-empty list of gate IDs":
    ## Scenario: list all gate IDs
    ## Given the gate registry is loaded from manifest.d/
    ## When I call allGates()
    ## Then the result contains at least 20 gates
    let gates = allGates()
    check gates.len >= 20

  test "allGates returns unique IDs":
    ## Given the gate registry
    ## When I check for duplicate IDs
    ## Then all IDs are unique
    let gates = allGates()
    var seen: HashSet[string]
    for g in gates:
      check g.id notin seen
      seen.incl(g.id)
