import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

## CEGAR Canonical Adapter — maps engine-internal rich types to the boundary contract.
##
## Per Canonical-Implementation Pattern:
##   - core/orchestrator/cegar_types defines the rich engine type (CegarEngineResult).
##   - core/boundary/verification_interface defines the canonical contract (CegarResult).
##   - This adapter converts between them at the Infrastructure boundary.

import core/orchestrator/cegar_types
import core/boundary/verification_interface
import core/symbolic_types_expr
# axiomIoBoundary

const
  engineToCanonical: array[CegarEngineVerdict, CegarVerdict] = [
    cegarProven:         cvProved,
    cegarCounterexample: cvCounterexample,
    cegarMaxIterations:  cvError,
    cegarBudgetExceeded: cvTimeout
  ]
  canonicalToEngine: array[CegarVerdict, CegarEngineVerdict] = [
    cvProved:         cegarProven,
    cvCounterexample: cegarCounterexample,
    cvTimeout:        cegarBudgetExceeded,
    cvError:          cegarMaxIterations
  ]

func toCanonical*(verdict: CegarEngineVerdict): CegarVerdict {.raises: [].} =
  ## Map engine verdict enum to canonical boundary verdict.
  engineToCanonical[verdict]

func toEngineVerdict*(verdict: CegarVerdict): CegarEngineVerdict {.raises: [].} =
  ## Map canonical boundary verdict back to engine verdict.
  canonicalToEngine[verdict]

func toCanonical*(engineResult: CegarEngineResult): CegarResult {.raises: [].} =
  ## Map rich engine result to canonical boundary result.
  ## Proved invariants are serialized via sExprToString; engine metadata
  ## (iterations, elapsedMs, refinementHistory, unsatCoreVars) stays internal.
  result.verdict = engineResult.verdict.toCanonical()
  result.invariants = newSeq[string](engineResult.provedInvariants.len)
  for i in 0 ..< engineResult.provedInvariants.len:
    result.invariants[i] = sExprToString(engineResult.provedInvariants[i])

{.pop.}
