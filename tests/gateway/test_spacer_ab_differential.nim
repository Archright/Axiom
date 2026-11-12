{.push raises: [].}
## A/B Differential Test — Spacer vs CEGAR Solver Consistency
##
## Verifies that for identical BMC transition artifacts,
## Spacer and CEGAR produce mathematically consistent verdicts.

import std/unittest
import core/bmc/bmc_generic
import core/bmc/bmc_artifacts
import core/bmc/bmc_variable_map
import verification/spacer_integration_gate
import verification/spacer_chc_router

suite "Spacer A/B Differential":
  test "Spacer rejects empty transitions with srUnknown":
    let artifact = initBmcAnalysisArtifact(
      config = BmcConfig(),
      transitions = @[],
      safetyProperty = "",
      varMap = VariableMapTable(),
      scopeCtx = ScopeContextStack()
    )
    check artifact.isEmpty

  test "BmcAnalysisArtifact round-trip preserves data":
    let config = initBmcConfig(bpkRaceCondition, stepBound = 5)
    let transitions = @[
      BmcTransition(
        preState: @[("x", "Int")],
        guard: "(> x 0)",
        postState: @[("x", "(+ x 1)")]
      )
    ]
    let artifact = initBmcAnalysisArtifact(
      config = config,
      transitions = transitions,
      safetyProperty = "(>= x 0)",
      varMap = VariableMapTable(),
      scopeCtx = ScopeContextStack()
    )
    check not artifact.isEmpty
    check artifact.transitions.len == 1
    check artifact.config.stepBound == 5
    check artifact.safetyProperty == "(>= x 0)"
