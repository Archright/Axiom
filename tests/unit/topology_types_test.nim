## topology_types_test.nim
## Business scenario tests for gate/framework/topology_types.nim —
## the SSOT for gate manifest schema and entry construction.
##
## Tests cover: TopologyEntry construction with defaults, enum values,
## required vs optional field handling, and field propagation.

import std/unittest
import gate/framework/topology_types

suite "initTopologyEntry: default field handling":
  test "minimal entry uses all defaults":
    let stagesEmpty: seq[StageKind] = @[]
    let entry = initTopologyEntry(
      id = "minimal-gate",
      name = "Minimal Test Gate",
      layer = lkFunctional,
      entry = "src/gate/runners/minimal",
      stages = stagesEmpty,
      passFilenames = false,
      weight = wkLight,
      category = ckRule
    )
    check entry.id == "minimal-gate"
    check entry.name == "Minimal Test Gate"
    check entry.layer == lkFunctional
    check entry.entry == "src/gate/runners/minimal"
    check entry.stages.len == 0
    check entry.passFilenames == false
    check entry.weight == wkLight
    check entry.category == ckRule
    check entry.filesPattern == ""
    check entry.argsTemplate.len == 0
    check entry.after.len == 0
    check entry.tier == 1
    check entry.severity == svError
    check entry.executionMode == emAOT
    check entry.hermeticity == hkHermetic
    check entry.priority == 0
    check entry.alwaysRun == false
    check entry.depsDirs.len == 0
    check entry.timeoutSeconds == 0

  test "explicit values override defaults":
    let argsTemplate: seq[string] = @["$repoRoot", "$maxJobs"]
    let after: seq[string] = @["ci-skip-detector", "nim-check"]
    let depsDirs: seq[string] = @["bin/custom_gate", "data/baselines/"]
    let entry = initTopologyEntry(
      id = "custom-gate",
      name = "Custom Gate",
      layer = lkMeta,
      entry = "bin/custom_gate",
      stages = @[skPrePush, skCI],
      passFilenames = true,
      weight = wkHeavy,
      category = ckTheorem,
      filesPattern = "src/**/*.nim",
      argsTemplate = argsTemplate,
      after = after,
      tier = 2,
      severity = svWarn,
      executionMode = emInterpreted,
      hermeticity = hkTransient,
      priority = 42,
      alwaysRun = true,
      depsDirs = depsDirs,
      timeoutSeconds = 300
    )
    check entry.id == "custom-gate"
    check entry.name == "Custom Gate"
    check entry.layer == lkMeta
    check entry.entry == "bin/custom_gate"
    check entry.stages == @[skPrePush, skCI]
    check entry.passFilenames == true
    check entry.weight == wkHeavy
    check entry.category == ckTheorem
    check entry.filesPattern == "src/**/*.nim"
    check entry.argsTemplate == argsTemplate
    check entry.after == after
    check entry.tier == 2
    check entry.severity == svWarn
    check entry.executionMode == emInterpreted
    check entry.hermeticity == hkTransient
    check entry.priority == 42
    check entry.alwaysRun == true
    check entry.depsDirs == depsDirs
    check entry.timeoutSeconds == 300

  test "single stage as sequence":
    let entry = initTopologyEntry(
      id = "single-stage",
      name = "Single Stage Gate",
      layer = lkFunctional,
      entry = "runner",
      stages = @[skPreCommit],
      passFilenames = false,
      weight = wkLight,
      category = ckRule
    )
    check skPreCommit in entry.stages
    check entry.stages.len == 1

  test "multiple stages preserved in order":
    let stages: seq[StageKind] = @[skPreCommit, skPrePush, skCI]
    let entry = initTopologyEntry(
      id = "multi-stage",
      name = "Multi Stage Gate",
      layer = lkFunctional,
      entry = "runner",
      stages = stages,
      passFilenames = false,
      weight = wkLight,
      category = ckRule
    )
    check entry.stages == stages

suite "TopologyEntry enum field values":
  test "StageKind enum covers all stages":
    var foundStages = 0
    for _ in StageKind:
      inc foundStages
    check foundStages == 4

  test "LayerKind enum covers both layers":
    var foundLayers = 0
    for _ in LayerKind:
      inc foundLayers
    check foundLayers == 2

  test "WeightKind enum covers all weights":
    var foundWeights = 0
    for _ in WeightKind:
      inc foundWeights
    check foundWeights == 3

  test "CategoryKind enum covers all categories":
    var foundCategories = 0
    for _ in CategoryKind:
      inc foundCategories
    check foundCategories == 4

  test "SeverityKind enum covers both severities":
    var foundSeverities = 0
    for _ in SeverityKind:
      inc foundSeverities
    check foundSeverities == 2

  test "ExecutionModeKind enum covers both modes":
    var foundModes = 0
    for _ in ExecutionModeKind:
      inc foundModes
    check foundModes == 2

  test "HermeticityKind enum covers both kinds":
    var foundKinds = 0
    for _ in HermeticityKind:
      inc foundKinds
    check foundKinds == 2

suite "TopologyGateEntry type":
  test "TopologyGateEntry construction":
    let gateEntry = TopologyGateEntry(
      id: "test-gate",
      path: "src/gate/runners/test_gate"
    )
    check gateEntry.id == "test-gate"
    check gateEntry.path == "src/gate/runners/test_gate"

suite "ManifestRegistryEntry type":
  test "ManifestRegistryEntry construction":
    let regEntry = ManifestRegistryEntry(
      id: "registry-gate",
      entry: "src/gate/runners/registry_gate"
    )
    check regEntry.id == "registry-gate"
    check regEntry.entry == "src/gate/runners/registry_gate"

suite "initTopologyEntry edge cases":
  test "empty id and name allowed":
    let stagesEmpty: seq[StageKind] = @[]
    let entry = initTopologyEntry(
      id = "",
      name = "",
      layer = lkFunctional,
      entry = "",
      stages = stagesEmpty,
      passFilenames = false,
      weight = wkLight,
      category = ckRule
    )
    check entry.id == ""
    check entry.name == ""
    check entry.entry == ""
    check entry.stages.len == 0

  test "empty strings for all string fields":
    let entry = initTopologyEntry(
      id = "gate",
      name = "Gate",
      layer = lkFunctional,
      entry = "entry",
      stages = @[skCI],
      passFilenames = false,
      weight = wkLight,
      category = ckRule,
      filesPattern = ""
    )
    check entry.filesPattern == ""

  test "empty seq fields preserved":
    let stagesEmpty: seq[StageKind] = @[]
    let argsEmpty: seq[string] = @[]
    let after: seq[string] = @[]
    let depsEmpty: seq[string] = @[]
    let entry = initTopologyEntry(
      id = "gate",
      name = "Gate",
      layer = lkFunctional,
      entry = "entry",
      stages = stagesEmpty,
      passFilenames = false,
      weight = wkLight,
      category = ckRule,
      argsTemplate = argsEmpty,
      after = after,
      depsDirs = depsEmpty
    )
    check entry.argsTemplate.len == 0
    check entry.after.len == 0
    check entry.depsDirs.len == 0

  test "tier and priority combined":
    let entry = initTopologyEntry(
      id = "tier-test",
      name = "Tier Test",
      layer = lkFunctional,
      entry = "runner",
      stages = @[skPreCommit],
      passFilenames = false,
      weight = wkMedium,
      category = ckRule,
      tier = 2,
      priority = 100
    )
    check entry.tier == 2
    check entry.priority == 100

  test "alwaysRun flag toggles":
    var entry = initTopologyEntry(
      id = "always-run-false",
      name = "Not Always Run",
      layer = lkFunctional,
      entry = "runner",
      stages = @[skPreCommit],
      passFilenames = false,
      weight = wkLight,
      category = ckRule,
      alwaysRun = false
    )
    check entry.alwaysRun == false
    
    entry = initTopologyEntry(
      id = "always-run-true",
      name = "Always Run",
      layer = lkFunctional,
      entry = "runner",
      stages = @[skPreCommit],
      passFilenames = false,
      weight = wkLight,
      category = ckRule,
      alwaysRun = true
    )
    check entry.alwaysRun == true