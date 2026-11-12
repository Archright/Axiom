import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

## Concrete Solver Provider Implementations (Infrastructure layer).
##
## Z3Provider and Lean4Provider concrete execute/providerName procs.
## These call infrastructure (z3_pool, lean_replay) and belong in verification/.
##
## The abstract types and SolverProvider concept remain in core/provider_interface.nim.

import core/results
import core/judge/lean_replay
import core/provider_interface
import verification/solver/z3_pool
import std/strutils
import core/axiom_pragmas
# axiomIoBoundary

# ============================================================================
# Z3Provider Implementation
# ============================================================================

proc execute*(provider: Z3Provider; query: string): ProviderResult {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Execute Z3 query via persistent pool.
  var cd, td: string
  let res = z3ExecPersistent(query, provider.timeoutMs, desiredWorkers = 2,
    canonicalEnvelopeDigest = cd, transportPayloadDigest = td)
  if res.isOk():
    let output = res.get().strip()
    let status = 
      if output.toLowerAscii() == "unsat": psSolverUnsat
      elif output.toLowerAscii() == "sat": psSolverSat
      elif output.toLowerAscii() == "unknown": psSolverUnknown
      elif output.toLowerAscii() == "timeout": psSolverTimeout
      else: psSolverUnknown
    ProviderResult(status: status, output: output, error: "")
  else:
    ProviderResult(status: psSolverUnknown, output: "", error: res.error())

func providerName*(provider: Z3Provider): string {.inline, raises: [].} =
  "Z3Provider"

# ============================================================================
# Lean4Provider Implementation
# ============================================================================

proc execute*(provider: Lean4Provider; source: string): ProviderResult {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Execute Lean 4 type-checking on source.
  let res = runLeanReplay("provider_node", source)
  if res.isOk():
    let isValid = res.get().isValid
    let status = if isValid: psSolverUnsat else: psSolverSat
    ProviderResult(
      status: status, 
      output: if isValid: "valid" else: "invalid",
      error: ""
    )
  else:
    ProviderResult(status: psSolverUnknown, output: "", error: res.error())

func providerName*(provider: Lean4Provider): string {.inline, raises: [].} =
  "Lean4Provider"

# ============================================================================
# Backward Compatibility Helpers
# ============================================================================

proc z3ExecuteViaProvider*(query: string; timeoutMs: int = 30000): ProviderResult {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Execute Z3 query via provider interface.
  ## Drop-in replacement for direct z3ExecPersistent calls.
  let provider = initZ3Provider(timeoutMs)
  provider.execute(query)

proc leanExecuteViaProvider*(source: string): ProviderResult {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Execute Lean 4 via provider interface.
  ## Drop-in replacement for direct runLeanReplay calls.
  let provider = initLean4Provider()
  provider.execute(source)

{.pop.}
