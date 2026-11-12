import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

## ProofStatus — exhaustive proof outcome enum.
##
## Replaces the duplicate definition in engine/proof_certificate.nim.
## This is the SSOT for ProofStatus; engine/proof_certificate re-exports it.

type
  ProofStatus* = enum
    psPass              ## Proof succeeded (unsat = property holds)
    psFail              ## Proof failed (counterexample found / sat)
    psTimeout           ## Solver timeout
    psSkip              ## Skipped (cached / trivial / pre-sieved)
    psError             ## Internal error (IR generation, serialization, etc.)
    psVacuousTrivial    ## Vacuous — trivially true (no meaningful constraint)
    psVacuousCounter    ## Vacuous — trivially false (contradictory)
    psNoObligation      ## No obligation — nothing to prove (separate from Trivial)

{.pop.}