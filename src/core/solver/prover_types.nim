import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## Prover Type Definitions — SSOT for Z3PoolProver and LeanProver types.
## Extracted from verification/solver/provers to resolve
## SoC-layer-imports violation in core/gateway/gateway_main.nim.
## These are pure type definitions; concrete implementations remain
## in verification/solver/provers which re-exports these types.

type
  Z3PoolProver* = object
    ## Concrete Z3 prover backed by the persistent process pool.
    ## prove returns true iff Z3 returns "unsat".

  LeanProver* = object
    ## Concrete Lean 4 prover backed by the compiler subprocess.
    ## prove returns true iff Lean type-checking succeeds.

{.pop.}
