## manifest_parser_test.nim
## Business scenario tests for gate/manifest_parser.nim —
## the SSOT for gate manifest JSON parsing and validation.
##
## Tests cover: GateConfig construction, field validation, optional field handling,
## error propagation, and input slice/artifact subscription parsing.

import std/[unittest, json, sets, strutils, macros]
import gate/gate_contract
import gate/manifest_parser
import core/types/gate_types

suite "parseGateConfig: required field validation":
  test "complete gate config parses successfully":
    let json = %* {
      "id": "valid-gate",
      "name": "Test Gate",
      "layer": "functional",
      "entry": "src/gate/runners/valid-gate",
      "stages": ["pre-commit"],
      "filesPattern": "src/**/*.nim",
      "passFilenames": true,
      "weight": "light"
    }
    let config = parseGateConfig(json)
    check config.id == "valid-gate"
    check config.name == "Test Gate"

  test "missing id field raises ValueError":
    let json = %* {
      "name": "No ID Gate",
      "layer": "functional",
      "entry": "runner",
      "stages": ["pre-commit"],
      "passFilenames": false,
      "weight": "light"
    }
    expect ValueError:
      discard parseGateConfig(json)

  test "missing name field raises ValueError":
    let json = %* {
      "id": "no-name-gate",
      "layer": "functional",
      "entry": "runner",
      "stages": ["pre-commit"],
      "passFilenames": false,
      "weight": "light"
    }
    expect ValueError:
      discard parseGateConfig(json)

  test "typo in required field name catches error":
    let json = %* {
      "id": "typo-gate",
      "name": "Typo Gate",
      "layr": "functional",
      "entry": "runner",
      "stages": ["pre-commit"],
      "passFilenames": false,
      "weight": "light"
    }
    expect ValueError:
      discard parseGateConfig(json)

  test "missing stage field raises ValueError":
    let json = %* {
      "id": "no-stage",
      "name": "No Stage Gate",
      "layer": "functional",
      "entry": "runner",
      "passFilenames": false,
      "weight": "light"
    }
    expect ValueError:
      discard parseGateConfig(json)

suite "parseGateConfig: layer parsing":
  test "meta layer parsed correctly":
    let json = %* {
      "id": "meta-gate",
      "name": "Meta Gate",
      "layer": "meta",
      "entry": "bin/meta_gate",
      "stages": ["pre-commit"],
      "passFilenames": false,
      "weight": "light"
    }
    let config = parseGateConfig(json)
    check config.layer == glMeta

  test "functional layer parsed correctly":
    let json = %* {
      "id": "func-gate",
      "name": "Func Gate",
      "layer": "functional",
      "entry": "runner",
      "stages": ["pre-commit"],
      "passFilenames": false,
      "weight": "light"
    }
    let config = parseGateConfig(json)
    check config.layer == glFunctional

  test "unknown layer defaults to functional":
    let json = %* {
      "id": "unknown-layer",
      "name": "Unknown Layer Gate",
      "layer": "unknown",
      "entry": "runner",
      "stages": ["pre-commit"],
      "passFilenames": false,
      "weight": "light"
    }
    let config = parseGateConfig(json)
    check config.layer == glFunctional

suite "parseGateConfig: weight parsing":
  test "light weight parsed correctly (default)":
    let json = %* {
      "id": "light-gate",
      "name": "Light Gate",
      "layer": "functional",
      "entry": "runner",
      "stages": ["pre-commit"],
      "passFilenames": false,
      "weight": "light"
    }
    let config = parseGateConfig(json)
    check config.weight == gwLight

  test "medium weight parsed correctly":
    let json = %* {
      "id": "medium-gate",
      "name": "Medium Gate",
      "layer": "functional",
      "entry": "runner",
      "stages": ["ci"],
      "passFilenames": false,
      "weight": "medium"
    }
    let config = parseGateConfig(json)
    check config.weight == gwMedium

  test "heavy weight parsed correctly":
    let json = %* {
      "id": "heavy-gate",
      "name": "Heavy Gate",
      "layer": "functional",
      "entry": "runner",
      "stages": ["ci"],
      "passFilenames": false,
      "weight": "heavy"
    }
    let config = parseGateConfig(json)
    check config.weight == gwHeavy

  test "unknown weight defaults to light":
    let json = %* {
      "id": "unknown-weight",
      "name": "Unknown Weight Gate",
      "layer": "functional",
      "entry": "runner",
      "stages": ["ci"],
      "passFilenames": false,
      "weight": "unknown-weight"
    }
    let config = parseGateConfig(json)
    check config.weight == gwLight

suite "parseGateConfig: stage parsing":
  test "single pre-commit stage parsed":
    let json = %* {
      "id": "precommit-gate",
      "name": "PreCommit Gate",
      "layer": "functional",
      "entry": "runner",
      "stages": ["pre-commit"],
      "passFilenames": false,
      "weight": "light"
    }
    let config = parseGateConfig(json)
    check gsPreCommit in config.stages
    check config.stages.len == 1

  test "multiple stages parsed":
    let json = %* {
      "id": "multi-stage",
      "name": "Multi Stage Gate",
      "layer": "functional",
      "entry": "runner",
      "stages": ["pre-commit", "ci"],
      "passFilenames": false,
      "weight": "light"
    }
    let config = parseGateConfig(json)
    check gsPreCommit in config.stages
    check gsCI in config.stages
    check config.stages.len == 2

  test "ci stage parsed":
    let json = %* {
      "id": "ci-gate",
      "name": "CI Gate",
      "layer": "functional",
      "entry": "runner",
      "stages": ["ci"],
      "passFilenames": false,
      "weight": "light"
    }
    let config = parseGateConfig(json)
    check gsCI in config.stages

suite "parseGateConfig: optional field defaults":
  test "tier defaults to 1":
    let json = %* {
      "id": "tier-default-test",
      "name": "Tier Default",
      "layer": "functional",
      "entry": "runner",
      "stages": ["pre-commit"],
      "passFilenames": false,
      "weight": "light"
    }
    let config = parseGateConfig(json)
    check config.tier == 1

  test "tier set to 2 when provided":
    let json = %* {
      "id": "tier2-gate",
      "name": "Tier 2 Gate",
      "layer": "functional",
      "entry": "runner",
      "stages": ["pre-commit"],
      "passFilenames": false,
      "weight": "light",
      "tier": 2
    }
    let config = parseGateConfig(json)
    check config.tier == 2

  test "priority defaults to 0":
    let json = %* {
      "id": "priority-default",
      "name": "Priority Default",
      "layer": "functional",
      "entry": "runner",
      "stages": ["pre-commit"],
      "passFilenames": false,
      "weight": "light"
    }
    let config = parseGateConfig(json)
    check config.priority == 0

  test "priority parsed from JSON when provided":
    let json = %* {
      "id": "priority-gate",
      "name": "Priority Gate",
      "layer": "functional",
      "entry": "runner",
      "stages": ["pre-commit"],
      "passFilenames": false,
      "weight": "light",
      "priority": 42
    }
    let config = parseGateConfig(json)
    check config.priority == 42

  test "alwaysRun defaults to false":
    let json = %* {
      "id": "always-default",
      "name": "Always Default",
      "layer": "functional",
      "entry": "runner",
      "stages": ["pre-commit"],
      "passFilenames": false,
      "weight": "light"
    }
    let config = parseGateConfig(json)
    check config.alwaysRun == false

  test "alwaysRun set to true when provided":
    let json = %* {
      "id": "always-gate",
      "name": "Always Gate",
      "layer": "functional",
      "entry": "runner",
      "stages": ["pre-commit"],
      "passFilenames": false,
      "weight": "light",
      "always_run": true
    }
    let config = parseGateConfig(json)
    check config.alwaysRun == true

  test "filesPattern defaults to empty string":
    let json = %* {
      "id": "pattern-default",
      "name": "Pattern Default",
      "layer": "functional",
      "entry": "runner",
      "stages": ["pre-commit"],
      "passFilenames": false,
      "weight": "light"
    }
    let config = parseGateConfig(json)
    check config.filesPattern == ""

  test "severity defaults to error":
    let json = %* {
      "id": "severity-default",
      "name": "Severity Default",
      "layer": "functional",
      "entry": "runner",
      "stages": ["ci"],
      "passFilenames": false,
      "weight": "light"
    }
    let config = parseGateConfig(json)
    check config.severity == gsError

  test "severity set to warn":
    let json = %* {
      "id": "warn-gate",
      "name": "Warn Gate",
      "layer": "functional",
      "entry": "runner",
      "stages": ["ci"],
      "passFilenames": false,
      "weight": "light",
      "severity": "warn"
    }
    let config = parseGateConfig(json)
    check config.severity == gsWarn

  test "executionMode defaults to aot":
    let json = %* {
      "id": "mode-default",
      "name": "Mode Default",
      "layer": "functional",
      "entry": "runner",
      "stages": ["ci"],
      "passFilenames": false,
      "weight": "light"
    }
    let config = parseGateConfig(json)
    check config.executionMode == "aot"

  test "executionMode set to interpreted":
    let json = %* {
      "id": "interpreted-gate",
      "name": "Interpreted Gate",
      "layer": "functional",
      "entry": "runner",
      "stages": ["ci"],
      "passFilenames": false,
      "weight": "light",
      "execution_mode": "interpreted"
    }
    let config = parseGateConfig(json)
    check config.executionMode == "interpreted"

  test "hermeticity defaults to hermetic":
    let json = %* {
      "id": "hermetic-default",
      "name": "Hermetic Default",
      "layer": "functional",
      "entry": "runner",
      "stages": ["ci"],
      "passFilenames": false,
      "weight": "light"
    }
    let config = parseGateConfig(json)
    check config.hermeticity == ghHermetic

  test "hermeticity set to transient":
    let json = %* {
      "id": "transient-gate",
      "name": "Transient Gate",
      "layer": "functional",
      "entry": "runner",
      "stages": ["ci"],
      "passFilenames": false,
      "weight": "light",
      "hermeticity": "transient"
    }
    let config = parseGateConfig(json)
    check config.hermeticity == ghTransient

suite "parseGateConfig: array fields":
  test "argsTemplate parsed correctly":
    let json = %* {
      "id": "args-gate",
      "name": "Args Gate",
      "layer": "functional",
      "entry": "runner",
      "stages": ["ci"],
      "passFilenames": false,
      "weight": "light",
      "argsTemplate": ["$repoRoot", "$maxJobs"]
    }
    let config = parseGateConfig(json)
    check config.argsTemplate == @["$repoRoot", "$maxJobs"]

  test "after dependencies parsed correctly":
    let json = %* {
      "id": "after-gate",
      "name": "After Gate",
      "layer": "functional",
      "entry": "runner",
      "stages": ["ci"],
      "passFilenames": false,
      "weight": "light",
      "after": ["gate-a", "gate-b"]
    }
    let config = parseGateConfig(json)
    check "gate-a" in config.after
    check "gate-b" in config.after

  test "depsDirs parsed correctly":
    let json = %* {
      "id": "deps-gate",
      "name": "Deps Gate",
      "layer": "functional",
      "entry": "runner",
      "stages": ["ci"],
      "passFilenames": false,
      "weight": "light",
      "depsDirs": ["bin/deps", "data/baselines"]
    }
    let config = parseGateConfig(json)
    check "bin/deps" in config.depsDirs
    check "data/baselines" in config.depsDirs

  test "scope parsed correctly":
    let json = %* {
      "id": "scope-gate",
      "name": "Scope Gate",
      "layer": "functional",
      "entry": "runner",
      "stages": ["ci"],
      "passFilenames": false,
      "weight": "light",
      "scope": ["src/core", "tests/unit"]
    }
    let config = parseGateConfig(json)
    check "src/core" in config.scope
    check "tests/unit" in config.scope

  test "envVars parsed correctly":
    let json = %* {
      "id": "env-gate",
      "name": "Env Gate",
      "layer": "functional",
      "entry": "runner",
      "stages": ["ci"],
      "passFilenames": false,
      "weight": "light",
      "envVars": [
        {"name": "AXIOM_MODE", "value": "dev"},
        {"name": "AXIOM_DEBUG", "value": "1"}
      ]
    }
    let config = parseGateConfig(json)
    check config.envVars.len == 2
    check ("AXIOM_MODE", "dev") in config.envVars

  test "envDependencies parsed correctly":
    let json = %* {
      "id": "env-dep-gate",
      "name": "Env Dep Gate",
      "layer": "functional",
      "entry": "runner",
      "stages": ["ci"],
      "passFilenames": false,
      "weight": "light",
      "envDependencies": [
        {"kind": "gitConfig", "key": "user.name"},
        {"kind": "envVar", "key": "AXIOM_HOME"}
      ]
    }
    let config = parseGateConfig(json)
    check config.envDependencies.len == 2

  test "inputSlice parsed correctly":
    let json = %* {
      "id": "slice-gate",
      "name": "Slice Gate",
      "layer": "functional",
      "entry": "runner",
      "stages": ["ci"],
      "passFilenames": false,
      "weight": "light",
      "inputSliceKind": "skFilesPattern",
      "inputSlicePaths": ["src/core"],
      "inputSliceExclude": ["test/**", "*.test.nim"]
    }
    let config = parseGateConfig(json)
    check config.inputSliceKind == skFilesPattern
    check "src/core" in config.inputSlicePaths
    check "test/**" in config.inputSliceExclude

  test "produces and subscribes parsed correctly":
    let json = %* {
      "id": "artifact-gate",
      "name": "Artifact Gate",
      "layer": "functional",
      "entry": "runner",
      "stages": ["ci"],
      "passFilenames": false,
      "weight": "light",
      "produces": ["bin/result.json", "bin/output.json"],
      "subscribes": ["data/baseline.json"]
    }
    let config = parseGateConfig(json)
    check "bin/result.json" in config.produces
    check "bin/output.json" in config.produces
    check "data/baseline.json" in config.subscribes

suite "validateGateManifest: duplicate ID detection":
  test "no duplicates passes validation":
    let gates = @[
      GateConfig(id: "gate-a", name: "Gate A", layer: glFunctional, entry: "a.nim",
        stages: {gsPreCommit}, filesPattern: "", passFilenames: false,
        priority: 0, envVars: @[], weight: gwLight, depsDirs: @[], argsTemplate: @[],
        after: @[], tier: 1, envDependencies: @[], severity: gsError,
        inputSliceKind: skFilesPattern, inputSlicePaths: @[], inputSliceExclude: @[],
        produces: @[], subscribes: @[], alwaysRun: false, gracePeriodUntil: "", hermeticity: ghHermetic),
      GateConfig(id: "gate-b", name: "Gate B", layer: glFunctional, entry: "b.nim",
        stages: {gsCI}, filesPattern: "", passFilenames: false,
        priority: 0, envVars: @[], weight: gwLight, depsDirs: @[], argsTemplate: @[],
        after: @[], tier: 1, envDependencies: @[], severity: gsError,
        inputSliceKind: skFilesPattern, inputSlicePaths: @[], inputSliceExclude: @[],
        produces: @[], subscribes: @[], alwaysRun: false, gracePeriodUntil: "", hermeticity: ghHermetic)
    ]
    validateGateManifest(gates)

  test "duplicate IDs raise ValueError":
    var gates: seq[GateConfig]
    for idx in 0..<2:
      gates.add GateConfig(
        id: "dup-gate", name: "Gate " & $idx, layer: glFunctional, entry: $idx & ".nim",
        stages: {gsPreCommit}, filesPattern: "", passFilenames: false,
        priority: 0, envVars: @[], weight: gwLight, depsDirs: @[], argsTemplate: @[],
        after: @[], tier: 1, envDependencies: @[], severity: gsError,
        inputSliceKind: skFilesPattern, inputSlicePaths: @[], inputSliceExclude: @[],
        produces: @[], subscribes: @[], alwaysRun: false, gracePeriodUntil: "", hermeticity: ghHermetic
      )
    expect ValueError:
      validateGateManifest(gates)

suite "GateConfig field defaults verification":
  test "all default fields verified for minimal config":
    let json = %* {
      "id": "defaults-test",
      "name": "Defaults Test",
      "layer": "functional",
      "entry": "runner",
      "stages": ["ci"],
      "passFilenames": false,
      "weight": "light"
    }
    let config = parseGateConfig(json)
    check config.id == "defaults-test"
    check config.name == "Defaults Test"
    check config.layer == glFunctional
    check config.entry == "runner"
    check config.tier == 1
    check config.priority == 0
    check config.severity == gsError
    check config.executionMode == "aot"
    check config.hermeticity == ghHermetic
    check config.alwaysRun == false
    check config.filesPattern == ""
    check config.argsTemplate.len == 0
    check config.after.len == 0
    check config.scope.len == 0
    check config.depsDirs.len == 0
    check config.envVars.len == 0
    check config.envDependencies.len == 0
    check config.inputSliceKind == skFilesPattern
    check config.inputSlicePaths.len == 0
    check config.inputSliceExclude.len == 0
    check config.produces.len == 0
    check config.subscribes.len == 0
    check config.gracePeriodUntil == ""