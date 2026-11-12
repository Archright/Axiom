import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}
{.warning[UnusedImport]: off.}

import std/os
import gate/framework/topology_types
import gate/topology_spec
import generated/manifest_registry

proc verifyTopologyIntegrity*(): string {.raises: [].} =
  result = ""

  # Check 1: Every gate in TopologySpec exists in ManifestRegistry
  for gate in TopologySpec:
    var found = false
    for (id, path) in ManifestRegistry:
      if gate.id == id:
        found = true
        break
    if not found:
      return "[FAIL] Gate '" & gate.id & "' in TopologySpec not found in ManifestRegistry"

  # Check 2: Every gate path exists on disk
  for gate in TopologySpec:
    if not fileExists(gate.entry & ".nim") and not fileExists(gate.entry):
      return "[FAIL] Gate file not found: " & gate.entry & " (gate: " & gate.id & ")"

  # Check 3: No duplicate gate IDs
  for i in 0..<TopologySpec.len:
    for j in (i+1)..<TopologySpec.len:
      if TopologySpec[i].id == TopologySpec[j].id:
        return "[FAIL] Duplicate gate ID: " & TopologySpec[i].id

  # Check 4: ManifestRegistry entries match TopologySpec
  for (id, path) in ManifestRegistry:
    var found = false
    for gate in TopologySpec:
      if gate.id == id:
        found = true
        if gate.entry != path:
          return "[FAIL] Path mismatch for gate '" & id & "': manifest has '" & path & "', spec has '" & gate.entry & "'"
        break
    if not found:
      return "[FAIL] Gate '" & id & "' in ManifestRegistry not found in TopologySpec"

static:
  block:
    let error = verifyTopologyIntegrity()
    assert error.len == 0, error

{.pop.}
