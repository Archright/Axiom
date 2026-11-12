import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

## verification_types.nim — SSOT for verification report, synergy, and linkage types.
## Extracted from domain_types.nim (Phase B-4).

import core/types/gate_types
import core/types/certificate_types

type
  VerificationTimelinePoint* = object
    day*: string
    redToGreenTransitions*: int

  VerificationReportSummary* = object
    generatedAt*: string
    certDir*: string
    totalTrustedFunctions*: int
    verifiedFunctions*: int
    redFunctions*: int
    pendingFunctions*: int
    formalProofFunctions*: int
    ## Z3-only certificates that carry solver/mutation evidence but NO Lean kernel
    ## acceptance. Tracked separately from verifiedFunctions so the analyst report
    ## never invoices them as product VERIFIED. P3b invariant: certZ3Candidate
    ## (candidate evidence) must not sum into verifiedFunctions/formalProofFunctions.
    z3CandidateFunctions*: int
    verifiedAxiomFunctions*: int
    pseudoVerifiedFunctions*: int
    yellowFunctions*: int
    certifiedExemptCount*: int
    missingCertificates*: int
    mismatchedFingerprints*: int
    staleFunctions*: int
    blockingFailure*: bool
    cumulativeDefectsHealed*: int
    architectureStabilityIndex*: float
    formalProofIntegrityIndex*: float
    axiomaticIntegrityIndex*: float
    averageRetryCount*: float
    verificationTimeline*: seq[VerificationTimelinePoint]
    cycleDetected*: bool
    cyclicFunctions*: seq[string]
    architectureGate*: ArchitecturePrinciplesGate
    auditTrailGate*: AuditTrailGate
    globalInfluenceGate*: GlobalInfluenceGate
    typeIntegrityGate*: TypeIntegrityGate
    symbolicInvariantGate*: SymbolicInvariantGate
    semanticIntegrityGate*: SemanticIntegrityGate
    currentGraphHash*: string
    symbolCount*: int
    edgeCount*: int
    certificates*: seq[FunctionCertificate]

  SynergyMetrics* = object
    fFactor*: float
    gFactor*: float
    hFactor*: float
    geometricMean*: float

  # Translation Validation — SSOT for semantic equivalence results.
  # Moved from verification/translation_validator.nim to break circular
  # dependency (gate_registry ↔ translation_validator).
  # Pure ADT: no I/O, no Infrastructure dependency.
  TranslationValidationResult* = object
    equivalent*: bool
    nimSmt2*: string
    leanSmt2*: string
    z3OutputFwd*: string
    z3OutputBwd*: string
    message*: string
    verifiedByZ3*: bool
    verifiedByLean*: bool

  # Axiom Linkage — SSOT for proof certificate linkage verification.
  # Moved from verification/proof_linkage.nim to break gate→verification dependency.
  AxiomLinkageResult* = object
    verified*: bool
    reason*: string
    axiomId*: string
    expectedHash*: string
    currentHash*: string

{.pop.}
