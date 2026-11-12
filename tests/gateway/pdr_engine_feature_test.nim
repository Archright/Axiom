## PDR Engine Feature Test.
## Verifies the PDR/IC3 solver interface and types.
##
## Tests:
##   - PdrConfig default values
##   - PdrResult structure
##   - runPdrEngine interface (stub returns non-converged)

import std/unittest
import verification/solver/pdr_engine

suite "PDR Engine — Solver Interface":

  test "DefaultMaxFrames is 20":
    ## Given the DefaultMaxFrames constant
    ## When checked
    ## Then PDR depth limit is 20 frames
    check DefaultMaxFrames == 20

  test "DefaultMaxGeneralizeDepth is 3":
    ## Given the DefaultMaxGeneralizeDepth constant
    ## When checked
    ## Then clause generalization depth is 3
    check DefaultMaxGeneralizeDepth == 3

  test "PdrConfig has all required fields":
    ## Given a PdrConfig value
    ## When constructed
    ## Then all solver parameters are accessible
    let cfg = PdrConfig(maxFrames: 10, z3TimeoutMs: 2000, maxGeneralizeDepth: 5)
    check cfg.maxFrames == 10
    check cfg.z3TimeoutMs == 2000
    check cfg.maxGeneralizeDepth == 5

  test "PdrResult tracks convergence state":
    ## Given a PdrResult value
    ## When constructed
    ## Then convergence and invariant fields are accessible
    let res = PdrResult(
      converged: true,
      inductiveInvariant: @["(>= x 0)"],
      iterations: 5,
      elapsedMs: 150,
      error: ""
    )
    check res.converged
    check res.inductiveInvariant.len == 1
    check res.iterations == 5

  test "runPdrEngine returns non-converged (stub)":
    ## Given the stub PDR engine
    ## When runPdrEngine is called with a property
    ## Then it returns non-converged (falls back to CEGAR)
    let result = runPdrEngine(
      property = "(>= x 0)",
      initialState = "(= x 0)",
      transitionRelation = "(= x' (+ x 1))"
    )
    check not result.converged
    check result.error.len > 0
