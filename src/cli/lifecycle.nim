import core/trusted/layer_declaration
axiomLayer "presentation"
{.push raises: [CatchableError].}
# axiomIoBoundary

## Shared bootstrap lifecycle for all Axiom CLI entry points.
##
## Every entry point (`runCli`, `runMain`, etc.) MUST call
## `bootstrapAxiomRuntime()` before processing arguments. This ensures
## the evidence writer and Z3 persistent prover hooks are registered
## regardless of which entry point is used.

import core/gateway/gateway
import verification/state_manager
import verification/solver/provers

var bootstrapped = false

proc bootstrapAxiomRuntime*() =
  ## Register all global hooks and perform one-time initialization.
  ## Idempotent: safe to call multiple times; only the first call takes effect.
  if bootstrapped:
    return
  bootstrapped = true

  when defined(gcOrc):
    GC_disableOrc()  # Phase 1: Runtime ORC cycle collection permanently disabled.
                     # Axiom core types use {.acyclic.} + value types; no cycles exist.
                     # Phase 2: --mm:arc compile flag enabled (config/effects.nims).

  registerEvidenceWriter(writeSolverEvidence)
  registerZ3PersistentProver(
    proc(query: string; timeoutMs: int): bool {.gcsafe, raises: [].} =
      Z3PoolProver().prove(query, timeoutMs)
  )

{.pop.}
