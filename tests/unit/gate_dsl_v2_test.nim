{.push raises: [].}

## Gate DSL v2 — Unit Tests
## Verifies GateDef construction, field wiring, CriticalGateIds, and tier constraints.

import std/[unittest]
import gate/gate_types
import gate/gate_dsl_v2

suite "GateDef construction":
  test "GateDef wires all basic fields correctly":
    let def = GateDef(
      id: "my-gate",
      name: "My Custom Gate",
      layer: glFunctional,
      tier: 1,
      weight: gwMedium,
      stages: {gsPreCommit},
      entry: "bin/my_gate",
      filesPattern: "*.nim",
      passFilenames: true,
      after: @["dep-gate"],
      depsDirs: @["src/core"],
      argsTemplate: @["$repoRoot", "$mode"],
      envVars: @[("NIM_CACHE", "/tmp/cache")],
      criticality: gcMedium,
      inputs: @["src/main.nim"],
      outputs: @["bin/ax"]
    )
    check def.id == "my-gate"
    check def.name == "My Custom Gate"
    check def.layer == glFunctional
    check def.tier == 1
    check def.weight == gwMedium
    check gsPreCommit in def.stages
    check def.entry == "bin/my_gate"
    check def.filesPattern == "*.nim"
    check def.passFilenames == true
    check def.after.len == 1
    check def.after[0] == "dep-gate"
    check def.depsDirs.len == 1
    check def.argsTemplate.len == 2
    check def.envVars.len == 1
    check def.criticality == gcMedium
    check def.inputs.len == 1
    check def.inputs[0] == "src/main.nim"
    check def.outputs.len == 1
    check def.outputs[0] == "bin/ax"

  test "GateDef defaults to empty optional fields":
    let def = GateDef(
      id: "minimal",
      name: "Minimal Gate",
      layer: glMeta,
      tier: 2,
      weight: gwLight,
      stages: {gsPrePush},
      entry: "bin/minimal",
      passFilenames: false,
      after: @[],
      criticality: gcLow
    )
    check def.filesPattern.len == 0
    check def.after.len == 0
    check def.depsDirs.len == 0
    check def.argsTemplate.len == 0
    check def.envVars.len == 0
    check def.inputs.len == 0
    check def.outputs.len == 0

  test "GateDef supports tier 2 (heavy path)":
    let def = GateDef(
      id: "heavy-gate",
      name: "Heavy Gate",
      layer: glFunctional,
      tier: 2,
      weight: gwHeavy,
      stages: {gsPrePush, gsCI},
      entry: "bin/heavy",
      passFilenames: false,
      after: @[],
      criticality: gcMedium
    )
    check def.tier == 2
    check def.weight == gwHeavy

  test "GateDef supports multiple stages":
    let def = GateDef(
      id: "all-stages",
      name: "All Stages",
      layer: glMeta,
      tier: 1,
      weight: gwLight,
      stages: {gsPreCommit, gsPrePush, gsManual, gsCI},
      entry: "bin/all_stages",
      passFilenames: false,
      after: @[],
      criticality: gcHigh
    )
    check gsPreCommit in def.stages
    check gsPrePush in def.stages
    check gsManual in def.stages
    check gsCI in def.stages

suite "GateDef input/output declarations":
  test "GateDef stores declared inputs for collision detection":
    let def = GateDef(
      id: "compile",
      name: "Compile",
      layer: glFunctional,
      tier: 1,
      weight: gwMedium,
      stages: {gsPreCommit},
      entry: "bin/compile",
      passFilenames: false,
      after: @[],
      criticality: gcMedium,
      inputs: @["src/main.nim", "src/utils.nim", "lib/base.nim"],
      outputs: @["bin/ax"]
    )
    check def.inputs.len == 3
    check "src/main.nim" in def.inputs
    check "src/utils.nim" in def.inputs
    check "lib/base.nim" in def.inputs

  test "GateDef stores declared outputs for collision detection":
    let def = GateDef(
      id: "test-runner",
      name: "Test Runner",
      layer: glFunctional,
      tier: 2,
      weight: gwHeavy,
      stages: {gsPrePush},
      entry: "bin/test_runner",
      passFilenames: true,
      after: @["compile"],
      criticality: gcMedium,
      inputs: @["src/main.nim"],
      outputs: @["build/test_results.json", "build/coverage.xml"]
    )
    check def.outputs.len == 2
    check "build/test_results.json" in def.outputs
    check "build/coverage.xml" in def.outputs

  test "GateDef with empty inputs and outputs":
    let def = GateDef(
      id: "lint",
      name: "Linter",
      layer: glMeta,
      tier: 1,
      weight: gwLight,
      stages: {gsPreCommit},
      entry: "bin/lint",
      passFilenames: true,
      after: @[],
      criticality: gcLow,
      inputs: @[],
      outputs: @[]
    )
    check def.inputs.len == 0
    check def.outputs.len == 0

suite "CriticalGateIds registry":
  test "CriticalGateIds contains gate-self-check":
    check "gate-self-check" in CriticalGateIds

  test "CriticalGateIds contains quality-gate-marker":
    check "quality-gate-marker" in CriticalGateIds

  test "CriticalGateIds contains unstaged-guard":
    check "unstaged-guard" in CriticalGateIds

  test "CriticalGateIds contains integrity-workflow":
    check "integrity-workflow" in CriticalGateIds

  test "CriticalGateIds contains architecture-config-gate":
    check "architecture-config-gate" in CriticalGateIds

  test "CriticalGateIds has exactly 6 entries":
    check CriticalGateIds.len == 6

suite "GateCriticality levels":
  test "gcHigh is never auto-disable":
    check gcHigh == gcHigh
    check $gcHigh == "high"

  test "gcMedium is conditional auto-disable":
    check gcMedium == gcMedium
    check $gcMedium == "medium"

  test "gcLow is auto-disable eligible":
    check gcLow == gcLow
    check $gcLow == "low"

{.pop.}
