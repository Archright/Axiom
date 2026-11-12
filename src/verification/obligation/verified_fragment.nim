import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

## VerifiedFragmentV1 — static support boundary for generated obligations.
##
## A VerifiedFragmentV1 is the COMBINATION of:
##   (a) static admissibility from admissibility.nim
##       (assessAdmissibility(entry, funcDef).decision != INELIGIBLE)
##   (b) the obligation result is ogrGenerated
##   (c) every obligation in the generated result has kind within the
##       5-kind allowlist: {okContractPre, okContractPost, okSafetyDiv,
##       okSafetyIndex, okSafetyLoopBound} — the only kinds
##       extractObligationCandidates actually produces.
##
## Semantic boundary (IMPORTANT): VerifiedFragmentV1 is the
## StaticProofCandidateFragmentV1 — the static support boundary.
## The actual proof boundary is established only at execution time by
## CanonicalLeanEvidence. Do NOT conflate the two: a fragment
## membership says the obligation is statically admissible and
## generated within the product scope; it does NOT say the proof
## succeeded. Proof success is a runtime property of the Lean kernel
## acceptance and Axiom validation pipeline.

import core/trusted/axiom_pragmas
import core/trusted/axiom_ir
import verification/admissibility
import verification/obligation/obligation_types
import verification/obligation/obligation_ir

# ---------------------------------------------------------------------------
# VerifiedFragmentV1 — the static support boundary
# ---------------------------------------------------------------------------

type
  VerifiedFragmentV1* = object
    obligationKinds*: set[ObligationKind]
    ## The set of ObligationKind values that this fragment admits.
    ## Only the 5 kinds produced by extractObligationCandidates are
    ## permitted: okContractPre, okContractPost, okSafetyDiv,
    ## okSafetyIndex, okSafetyLoopBound.

  FragmentExclusion* = enum
    feInFragment         ## all three conditions hold
    feStaticAdmissibility ## condition 1 failed — static admissibility said INELIGIBLE
    feObligationBoundary  ## conditions 2/3 failed — not generated, or a kind
                          ## outside the allowlist
  ## Which of `inVerifiedFragmentV1`'s three conditions rejected a candidate.
  ## Exposed so callers that must explain a rejection read this one authority
  ## instead of re-deriving the admissibility verdict themselves.

const
  VerifiedFragmentAllowlist*: set[ObligationKind] = {
    okContractPre, okContractPost, okSafetyDiv,
    okSafetyIndex, okSafetyLoopBound
  }
  ## The closed allowlist of obligation kinds that extractObligationCandidates
  ## actually produces. Any Generated result whose obligations fall
  ## entirely within this set is a verified fragment candidate.

func verifiedFragmentExclusion*(entry: RuntimeAxiomEntry; funcDef: IRFuncDef;
                                genResult: ObligationGenerationResult): FragmentExclusion {.raises: [].} =
  ## Which of the three fragment conditions rejected the candidate.  Evaluated
  ## in the order `inVerifiedFragmentV1` documents, so the first failing
  ## condition is the reported cause.
  if assessAdmissibility(entry, funcDef).decision == INELIGIBLE:
    return feStaticAdmissibility
  if genResult.kind != ogrGenerated:
    return feObligationBoundary
  for obl in genResult.obligations.items:
    if obl.kind notin VerifiedFragmentAllowlist:
      return feObligationBoundary
  feInFragment

func inVerifiedFragmentV1*(entry: RuntimeAxiomEntry; funcDef: IRFuncDef;
                           genResult: ObligationGenerationResult): bool {.raises: [].} =
  ## True iff the combination of static admissibility and generated
  ## obligation kinds falls within the VerifiedFragmentV1 boundary.
  ##
  ## Three conditions (ALL must hold):
  ## 1. Static admissibility: assessAdmissibility(entry, funcDef).decision != INELIGIBLE
  ## 2. The result is ogrGenerated (has obligations to verify)
  ## 3. Every obligation's kind is in VerifiedFragmentAllowlist
  ##
  ## Note: this is a STATIC boundary only. The actual proof boundary
  ## is established at execution time by CanonicalLeanEvidence.
  verifiedFragmentExclusion(entry, funcDef, genResult) == feInFragment

{.pop.}
