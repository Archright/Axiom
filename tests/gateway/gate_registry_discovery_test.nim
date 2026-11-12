## Gate Registry Discovery — Compile-Time Test
##
## Verifies that the gate registry (``src/gate/gate_registry.nim``) correctly:
##   1. Returns a non-empty sequence from ``allGates()``
##   2. Gate count matches the manifest entry count
##   3. Every gate id is unique (no duplicates)
##   4. Gates are sorted by ``id`` ascending
##   5. Every manifest entry appears in ``allGates()``

import std/[unittest, json]
import gate/gate_registry
import gate/gate_types
import gate/manifest_provider

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

proc getManifestIds(): seq[string] =
  let manifestJson = getGateManifestAsJson()
  let manifest = parseJson(manifestJson)
  for gate in manifest["gates"]:
    result.add(gate["id"].getStr())

# ---------------------------------------------------------------------------
# Test suite
# ---------------------------------------------------------------------------

suite "Gate Registry Discovery":

  test "allGates() returns a non-empty sequence":
    let gates = allGates()
    check gates.len > 0

  test "gate count equals manifest entry count":
    let gates = allGates()
    let manifestIds = getManifestIds()
    check gates.len == manifestIds.len

  test "every gate id is unique":
    let gates = allGates()
    var seen: seq[string]
    for g in gates:
      check g.id notin seen
      seen.add(g.id)

  test "gates are sorted by id ascending":
    let gates = allGates()
    for i in 1 ..< gates.len:
      check cmp(gates[i - 1].id, gates[i].id) <= 0

  test "every manifest gate appears in allGates()":
    let gates = allGates()
    let manifestIds = getManifestIds()
    var gateIds: seq[string]
    for g in gates:
      gateIds.add(g.id)
    for mid in manifestIds:
      check mid in gateIds


