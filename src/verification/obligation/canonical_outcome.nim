import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

## Canonical Outcome — combination invariant for ProofCertificate status
## and ObligationGenerationResultKind.
##
## Invariants (user principle):
##   - One canonical execution produces one outcome.
##   - If the outcome admits no evidence, it cannot be promoted upward.
##   - Verified => CLE => KAA; NoObligation => NoVerificationFailure;
##     Unsupported => NoVerificationFailure.
##
## Design: all functions are pure (func + {.raises: [].}).
## Import paths are confirmed by nim check — layer violations abort compilation.

import engine/proof_certificate
import verification/obligation/obligation_ir

# ---------------------------------------------------------------------------
# isNoFailureStatus — statuses where verification did NOT fail
# ---------------------------------------------------------------------------

func isNoFailureStatus*(status: ProofStatus): bool {.raises: [].} =
  ## Returns true for statuses that are NOT verification failures.
  ## psPass (verified success), psNoObligation (nothing to prove),
  ## psSkip (cached/trivial/pre-sieved), psVacuousTrivial (trivially true),
  ## and psVacuousCounter (vacuous — no meaningful constraint) all fall
  ## outside the failure set {psFail, psError, psTimeout}.
  status notin {psFail, psError, psTimeout}

# ---------------------------------------------------------------------------
# outcomeContractSatisfied — status+verdict pair must respect the invariant
# ---------------------------------------------------------------------------

func outcomeContractSatisfied*(status: ProofStatus;
                                verdict: ObligationGenerationResultKind): bool {.raises: [].} =
  ## Enforces the canonical outcome contract:
  ##   ogrNoApplicableObligation  →  no-failure status set
  ##     (psFail and psError are forbidden — no verification failure allowed)
  ##   ogrUnsupported             →  psSkip exclusively
  ##   ogrIllFormed               →  psSkip exclusively
  ##   ogrGenerated               →  any status permitted (genuine verification)
  case verdict
  of ogrNoApplicableObligation:
    isNoFailureStatus(status)
  of ogrUnsupported, ogrIllFormed:
    status == psSkip
  of ogrGenerated:
    ## Genuine verification outcome required — psNoObligation and psSkip
    ## are not verification results; they indicate absence of work or
    ## pre-filtering, not a proof attempt on a generated obligation.
    status notin {psNoObligation, psSkip}

# ---------------------------------------------------------------------------
# verifyOutcomeContract — full certificate pair check
# ---------------------------------------------------------------------------

func verifyOutcomeContract*(cert: ProofCertificate): bool {.raises: [].} =
  ## Validates that the certificate's status and obligationVerdict satisfy
  ## the canonical outcome contract. Pure projection — no side effects.
  outcomeContractSatisfied(cert.status, cert.obligationVerdict)

# ---------------------------------------------------------------------------
# requiresSemanticEvidence — statuses that need semantic evidence to be
# considered verified (promotable to verified tier)
# ---------------------------------------------------------------------------

func requiresSemanticEvidence*(status: ProofStatus): bool {.raises: [].} =
  ## Returns true for statuses that represent genuine verification results
  ## and thus require semantic evidence for promotion to a verified tier.
  ## psPass is the primary verified status; psVacuousTrivial is trivially
  ## true and also counts as verified. All other statuses do not qualify.
  status in {psPass, psVacuousTrivial}

{.pop.}