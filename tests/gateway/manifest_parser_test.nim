## Manifest Parser Feature Test — SSOT gate manifest JSON parsing.
## See tests/features/manifest_parser.feature for the specification.
##
## Contract: parseGateConfig round-trip, required field validation,
## validateGateManifest duplicate ID detection.

import std/[unittest, json]
import gate/manifest_parser
import gate/gate_types

suite "Manifest Parser — SSOT gate JSON parsing":

  test "parse valid gate JSON with all required fields":
    ## Scenario: parse valid gate JSON with all required fields
    ## Given a JSON object with all required fields
    ## When I call parseGateConfig
    ## Then the result is a valid GateConfig
    let node = %*{
      "id": "test-gate",
      "name": "Test Gate",
      "layer": "functional",
      "entry": "src/gate/runners/test_gate",
      "stages": ["pre-commit"],
      "passFilenames": false,
      "weight": "light"
    }
    let cfg = parseGateConfig(node)
    check cfg.id == "test-gate"
    check cfg.name == "Test Gate"
    check cfg.layer == glFunctional
    check cfg.entry == "src/gate/runners/test_gate"
    check gsPreCommit in cfg.stages
    check cfg.passFilenames == false
    check cfg.weight == gwLight

  test "parse gate JSON with optional fields":
    ## Given a JSON object with optional fields
    ## When I call parseGateConfig
    ## Then optional fields are parsed correctly
    let node = %*{
      "id": "meta-gate",
      "name": "Meta Gate",
      "layer": "meta",
      "entry": "src/gate/runners/meta_gate",
      "stages": ["pre-commit", "pre-push"],
      "passFilenames": true,
      "weight": "medium",
      "tier": 2,
      "severity": "warn",
      "hermeticity": "transient",
      "after": ["other-gate"],
      "filesPattern": "src/"
    }
    let cfg = parseGateConfig(node)
    check cfg.layer == glMeta
    check cfg.weight == gwMedium
    check cfg.tier == 2
    check cfg.severity == gsWarn
    check cfg.hermeticity == ghTransient
    check "other-gate" in cfg.after
    check cfg.filesPattern == "src/"

  test "validate manifest with unique gate IDs passes":
    ## Scenario: validate manifest with unique gate IDs
    ## Given a sequence of GateConfig objects with unique IDs
    ## When I call validateGateManifest
    ## Then no error is raised
    let gates = @[
      GateConfig(id: "gate-a"),
      GateConfig(id: "gate-b"),
      GateConfig(id: "gate-c"),
    ]
    validateGateManifest(gates)  # Should not raise

  test "reject manifest with duplicate gate IDs":
    ## Scenario: reject manifest with duplicate gate IDs
    ## Given a sequence with duplicate IDs
    ## When I call validateGateManifest
    ## Then ValueError is raised
    let gates = @[
      GateConfig(id: "gate-a"),
      GateConfig(id: "gate-a"),
    ]
    expect ValueError:
      validateGateManifest(gates)
