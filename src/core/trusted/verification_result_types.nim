import core/trusted/layer_declaration
import core/trusted/axiom_pragmas
axiomLayer "domain"
{.push raises: [].}

import core/types/solver_types

type
  VerificationStatus* = enum
    vsProved
    vsDisproved
    vsNoObligation
    vsInconclusive

  TerminationKind* = enum
    tkCompleted
    tkTimedOut
    tkResourceLimited
    tkFailed

  ReasonKind* = enum
    rkNone
    rkSolverUnknown
    rkSolverTimeout
    rkNotEncodable
    rkNoProperty
    rkNoObligation
    rkNoApplicableObligation  ## P5: formal enum for ogrNoApplicableObligation (was rkNoObligation+reason string)
    rkUnsupportedTheory
    rkBackendError
    rkEvidenceRejected
    rkCandidateCounterexample
    rkObligationUnsupported   ## P3: semantic scope out of model (obligation generator)
    rkObligationIllFormed     ## P3: semantic validation failure (obligation generator)

  SolverMethod* = enum
    smCHC
    smBMC
    smTypeLevel
    smNone

  ProvenanceKind* = enum
    pkSpacer
    pkZ3Bmc
    pkLean
    pkDual
    pkNone

  ## Proof scope discriminates bounded vs unbounded proofs structurally.
  ## depth K is provenance/evidence metadata, NOT a scope discriminator
  ## (see docs/spec/cert_lifecycle_contracts.md §1).
  ProofScope* = enum
    psUnbounded
    psBounded

  VerificationResult* = object
    status*: VerificationStatus
    proofScope*: ProofScope
    termination*: TerminationKind
    reason*: ReasonKind
    solverMethod*: SolverMethod
    provenance*: ProvenanceKind
    evidence*: string
    solverStatus*: SolverStatus
    model*: string

func deriveVerdict*(status: VerificationStatus; reason: ReasonKind;
                    termination: TerminationKind = tkCompleted;
                    solverMethod: SolverMethod = smNone;
                    provenance: ProvenanceKind = pkNone;
                    proofScope: ProofScope = psUnbounded): VerificationResult {.axiomDecision(
  id = "DECISION-0405",
  reason = "Single classifier SSOT for VerificationResult — all factories route through this function; incoherent (status,reason) pairs are coerced to the canonical choice deterministically; proofScope disambiguates bounded vs unbounded proofs",
  adr = "docs/spec/verification_result_types.md",
  introduced = "v34").} =
  var coercedReason = reason
  var coercedStatus = status
  case status
  of vsProved:
    if reason != rkNone:
      coercedReason = rkNone
  of vsDisproved:
    if reason notin {rkCandidateCounterexample, rkNone}:
      coercedReason = rkCandidateCounterexample
  of vsNoObligation:
    ## rkNoObligation (legacy) and rkNoApplicableObligation (P5 formal) both
    ## coerce to rkNoObligation for backward compat.  The distinction is
    ## preserved in the ObligationVerdictInfo.kind field downstream.
    coercedReason = rkNoObligation
  of vsInconclusive:
    if reason == rkNone:
      coercedReason = rkEvidenceRejected
  VerificationResult(
    status: coercedStatus,
    proofScope: proofScope,
    termination: termination,
    reason: coercedReason,
    solverMethod: solverMethod,
    provenance: provenance
  )

func makeProved*(solverMethod: SolverMethod = smCHC; provenance: ProvenanceKind = pkSpacer;
                 proofScope: ProofScope): VerificationResult =
  deriveVerdict(vsProved, rkNone, tkCompleted, solverMethod, provenance, proofScope)

func makeDisproved*(solverMethod: SolverMethod = smCHC; provenance: ProvenanceKind = pkSpacer;
                    proofScope: ProofScope): VerificationResult =
  deriveVerdict(vsDisproved, rkNone, tkCompleted, solverMethod, provenance, proofScope)

func isProved*(r: VerificationResult): bool {.inline.} =
  r.status == vsProved

func isUnboundedProved*(r: VerificationResult): bool {.inline.} =
  r.status == vsProved and r.proofScope == psUnbounded

func isBoundedProved*(r: VerificationResult): bool {.inline.} =
  r.status == vsProved and r.proofScope == psBounded

func makeInconclusive*(reason: ReasonKind; termination: TerminationKind = tkCompleted): VerificationResult =
  deriveVerdict(vsInconclusive, reason, termination, smNone, pkNone)

func makeTimeout*: VerificationResult =
  deriveVerdict(vsInconclusive, rkSolverTimeout, tkTimedOut, smNone, pkNone)

func makeNotEncodable*: VerificationResult =
  deriveVerdict(vsInconclusive, rkNotEncodable, tkCompleted, smNone, pkNone)

func makeNoProperty*: VerificationResult =
  deriveVerdict(vsInconclusive, rkNoProperty, tkCompleted, smNone, pkNone)

func makeNoObligation*: VerificationResult =
  deriveVerdict(vsNoObligation, rkNoObligation, tkCompleted, smNone, pkNone)

func makeNoApplicableObligation*: VerificationResult =
  ## P5 formal path: obligation generator determined no applicable obligation.
  ## Derives vsNoObligation with rkNoApplicableObligation reason.
  ## deriveVerdict coerces the reason to rkNoObligation for
  ## VerificationResult consistency; the semantic distinction is
  ## carried by ObligationVerdictInfo.kind downstream.
  deriveVerdict(vsNoObligation, rkNoApplicableObligation, tkCompleted, smNone, pkNone)

func makeSolverUnknown*: VerificationResult =
  deriveVerdict(vsInconclusive, rkSolverUnknown, tkCompleted, smNone, pkNone)

func makeCandidateCounterexample*(model: string; solverMethod: SolverMethod;
                                  provenance: ProvenanceKind;
                                  proofScope: ProofScope = psBounded): VerificationResult =
  ## SAT yields a CANDIDATE counterexample — verdict is NOT final.
  ## vsInconclusive is used here; P4 finalizes vsDisproved after semantic validation.
  ## BMC counterexamples are bounded evidence by construction (psBounded default).
  ## Do NOT set vsDisproved in P1 (that is the P4 workstream responsibility).
  result = deriveVerdict(vsInconclusive, rkCandidateCounterexample, tkCompleted, solverMethod, provenance, proofScope)
  result.solverStatus = solverSat
  result.model = model

{.pop.}