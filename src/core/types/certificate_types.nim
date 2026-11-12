import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

import std/options
import core/types/verification_tier
import core/types/asi_types
import core/contracts/spec_binding_macro
type
  CertificateStatusBase* = enum
    csbGreen
    csbRed
    csbPending
    csbYellow
    csbNoObligation  ## No semantic obligation — normal proof-pipeline termination (≠ failure, ≠ certified)
    csbStale
    csbVerifiedAxiom
    csbPseudoVerified
    csbZ3Verified       ## Phase 4A: Z3 SMT solver confirmed (unsat) — LEGACY ONLY
    csbZ3Candidate      ## Z3 candidate only — NOT verified, NOT deep-verified, NOT certGreen
    csbLeanVerified     ## Phase 4A: Lean 4 kernel type-checked
    csbDualVerified     ## Phase 4A: Both Z3 + Lean passed (highest confidence)
    csbTypeLevelVerified  ## NEW: type-level encoding fast-path
    csbWellFormed         ## Phase D: function is well-formed (syntax/type checking ok)
    csbSafetyVerified     ## Phase D: safety property verified (no overflow, bounds, etc.)
    csbSoundnessDebt      ## Phase E: proof contains sorry (Soundness Debt)
    csbNotCurrent         ## legacy/older-schema evidence — NOT trusted input (Phase-4/5)

  CertificateStatus* = distinct CertificateStatusBase
func `==`*(a, b: CertificateStatus): bool =
  cast[CertificateStatusBase](a) == cast[CertificateStatusBase](b)
func `$`*(a: CertificateStatus): string =
  case cast[CertificateStatusBase](a)
  of csbGreen: "certGreen"
  of csbRed: "certRed"
  of csbPending: "certPending"
  of csbYellow: "certYellow"
  of csbNoObligation: "certNoObligation"
  of csbStale: "certStale"
  of csbVerifiedAxiom: "certVerifiedAxiom"
  of csbPseudoVerified: "certPseudoVerified"
  of csbZ3Verified: "certZ3Verified"
  of csbZ3Candidate: "certZ3Candidate"
  of csbLeanVerified: "certLeanVerified"
  of csbDualVerified: "certDualVerified"
  of csbTypeLevelVerified: "certTypeLevelVerified"
  of csbWellFormed: "certWellFormed"
  of csbSafetyVerified: "certSafetyVerified"
  of csbSoundnessDebt: "certSoundnessDebt"
  of csbNotCurrent: "certNotCurrent"
const
  certGreen* = CertificateStatus(CertificateStatusBase.csbGreen)
  certRed* = CertificateStatus(CertificateStatusBase.csbRed)
  certPending* = CertificateStatus(CertificateStatusBase.csbPending)
  certYellow* = CertificateStatus(CertificateStatusBase.csbYellow)
  certNoObligation* = CertificateStatus(CertificateStatusBase.csbNoObligation)
  certStale* = CertificateStatus(CertificateStatusBase.csbStale)
  ## Active: used in metrics.nim, domain_utils.nim for certificate status classification.
  certVerifiedAxiom* = CertificateStatus(CertificateStatusBase.csbVerifiedAxiom)
  certPseudoVerified* = CertificateStatus(CertificateStatusBase.csbPseudoVerified)
  certZ3Verified* = CertificateStatus(CertificateStatusBase.csbZ3Verified)
  certZ3Candidate* = CertificateStatus(CertificateStatusBase.csbZ3Candidate)
  certLeanVerified* = CertificateStatus(CertificateStatusBase.csbLeanVerified)
  certDualVerified* = CertificateStatus(CertificateStatusBase.csbDualVerified)
  certTypeLevelVerified* = CertificateStatus(CertificateStatusBase.csbTypeLevelVerified)
  certWellFormed* = CertificateStatus(CertificateStatusBase.csbWellFormed)
  certSafetyVerified* = CertificateStatus(CertificateStatusBase.csbSafetyVerified)
  certSoundnessDebt* = CertificateStatus(CertificateStatusBase.csbSoundnessDebt)
  certNotCurrent* = CertificateStatus(CertificateStatusBase.csbNotCurrent)

func parseCertificateStatus*(s: string): CertificateStatus =
  ## Convert string to CertificateStatus enum for backward compatibility
  case s
  of "certGreen": certGreen
  of "certRed": certRed
  of "certZ3Verified": certZ3Verified
  of "certZ3Candidate": certZ3Candidate
  of "certLeanVerified": certLeanVerified
  of "certDualVerified": certDualVerified
  of "certPending": certPending
  of "certYellow": certYellow
  of "certNoObligation": certNoObligation
  of "certStale": certStale
  of "certVerifiedAxiom": certVerifiedAxiom
  of "certPseudoVerified": certPseudoVerified
  of "certTypeLevelVerified": certTypeLevelVerified
  of "certWellFormed": certWellFormed
  of "certSafetyVerified": certSafetyVerified
  of "certSoundnessDebt": certSoundnessDebt
  of "certNotCurrent": certNotCurrent
  else: certRed

# ─── B2: Tier-to-Certificate Status Mapping ────────────────────────────

func tierToCertStatus*(tier: VerificationTier): CertificateStatus =
  ## Map a verification tier to its canonical certificate status.
  ## Z3-only and K-induction are candidate-only, never verified.
  case tier
  of vtZ3Only:     certZ3Candidate
  of vtKInduction: certZ3Candidate
  of vtDual:       certGreen
  of vtLeanOnly:   certLeanVerified
  of vtNone:       certNoObligation
  of vtUfAbstract: certZ3Candidate

func tierToStatusString*(tier: VerificationTier): string =
  $tierToCertStatus(tier)

func isVerifiedCertificateStatus*(s: string): bool =
  ## A certificate status string is verified if it represents a
  ## fully verified result (not a candidate or legacy status).
  let status = parseCertificateStatus(s)
  status in {certGreen, certLeanVerified, certDualVerified, certTypeLevelVerified, certSafetyVerified}

# ─── Phase 1: SolverProvenance (ASi Inflation Fix) ────────────────────────

type
  SoundnessMode* = enum
    smLax
    smSoundnessGuard
    smFullStrict

type
  HydrationConfig* = object
    soundnessMode*: SoundnessMode
    verifyIrHash*: bool

var defaultHydrationConfig* = HydrationConfig(
  soundnessMode: smLax,
  verifyIrHash: false
)

type
  SolverProvenance* = enum
    spZ3SAT        ## Verified by Z3 SAT solver (high confidence)
    spSpacerCHC    ## Verified by Spacer CHC (medium confidence)
    spHeuristic    ## Pre-sieved by heuristic (low confidence)
    spUnknown      ## Missing/unrecognized provenance (lowest confidence — never Z3)
func parseSolverProvenance*(s: string): SolverProvenance =
  ## Parse solver provenance string from certificate JSON.
  ## Unknown/missing values default to `spUnknown` (explicit low-trust).
  ## NEVER to spZ3SAT — silent trust inflation is a Theater violation (WS-P2-B).
  case s
  of "spZ3SAT": spZ3SAT
  of "spSpacerCHC": spSpacerCHC
  of "spHeuristic": spHeuristic
  else: spUnknown

type
  NonNegativeDuration* {.spec("SPEC-T1-DURATION").} = object
    ## Smart type for non-negative duration values (>= 0).
    ## Private field pattern prevents construction bypass.
    val: float

# --- NonNegativeDuration: Safe Factory ---

func initNonNegativeDuration*(raw: float): Option[NonNegativeDuration] =
  ## Safely creates NonNegativeDuration. Returns none if value is negative.
  if raw >= 0.0:
    some(NonNegativeDuration(val: raw))
  else:
    none(NonNegativeDuration)

func defaultDuration*(): NonNegativeDuration =
  ## Module-internal default. Duration of 0.0 for unknown/unset durations.
  NonNegativeDuration(val: 0.0)

func toFloat*(d: NonNegativeDuration): float {.inline.} =
  d.val

func `$`*(d: NonNegativeDuration): string {.inline.} =
  $d.val

func `==`*(a, b: NonNegativeDuration): bool {.inline.} =
  a.val == b.val

func `!=`*(a, b: NonNegativeDuration): bool {.inline.} =
  a.val != b.val

func `<`*(a, b: NonNegativeDuration): bool {.inline.} =
  a.val < b.val

func `<=`*(a, b: NonNegativeDuration): bool {.inline.} =
  a.val <= b.val

func `>`*(a, b: NonNegativeDuration): bool {.inline.} =
  a.val > b.val

func `>=`*(a, b: NonNegativeDuration): bool {.inline.} =
  a.val >= b.val

type
  DeepVerificationCode* = enum
    dvcSuccess
    dvcFileNotFound
    dvcSmtMissing
    dvcZ3NotUnsat
    dvcLeanNotVerified
    dvcFingerprintMismatch
    dvcTamperedStatus
    dvcPbtFailed
    dvcNotInKernelScope   ## Phase 2 WS-A: symbol not in verification_scope.lock kernel_symbols
    dvcNotCurrent         ## Artifact is structurally valid but not current product truth (toolchain/execution-contract lineage mismatch)
type
  FilePath* = distinct string

  FunctionCertificate* = object
    certificatePath*: FilePath
    theoremName*: string
    functionName*: string
    modulePath*: FilePath
    fingerprint*: string
    currentFingerprint*: string
    structuralFingerprint*: string
    currentStructuralFingerprint*: string
    trusted*: bool
    status*: CertificateStatus
    reason*: string
    calls*: seq[string]
    accessedResources*: seq[string]
    mutatedResources*: seq[string]
    imports*: seq[string]
    constraints*: seq[string]
    selfHealingAsserts*: seq[string]
    recoveredDefects*: seq[string]
    retryCount*: int
    winningStrategy*: string
    globalGraphFingerprint*: string
    axiomId*: string              ## Referenced axiom identifier (for certVerifiedAxiom)
    axiomVersion*: string         ## Axiom version at certification time
    axiomHash*: string            ## SHA-256 of axiom definition at certification time
    leanArtifactHash*: string     ## SHA-256 of the .lean proof artifact
    linkageVerified*: bool         ## Whether hash-based linkage has been verified
    informationGain*: ASIRatio      ## Phase 3: entropy-based proof quality score
    verificationTier*: VerificationTier  ## Phase 4A: 2-stage pipeline tier
    irHash*: string

type
  PbtMetrics* = object
    passCount*: int
    failCount*: int
    discarded*: int
    seed*: int64
    durationMs*: NonNegativeDuration

# ─── Smart Constructor: Certificate Status Validation ──────────────

func isValidCertificateStatus*(s: string): bool =
  case s
  of "certGreen", "certRed", "certPending", "certYellow", "certNoObligation", "certStale",
     "certVerifiedAxiom", "certPseudoVerified", "certZ3Verified",
     "certLeanVerified", "certDualVerified", "certTypeLevelVerified",
     "certWellFormed", "certSafetyVerified", "certSoundnessDebt":
    true
  else:
    false

func isValidTransition*(fromSt, toSt: CertificateStatus): bool =
  let fromVal = cast[CertificateStatusBase](fromSt)
  let toVal = cast[CertificateStatusBase](toSt)
  case fromVal
  of csbPending:
    toVal in {csbWellFormed, csbRed, csbYellow, csbStale}
  of csbWellFormed:
    toVal in {csbSafetyVerified, csbRed, csbYellow, csbStale}
  of csbSafetyVerified:
    toVal in {csbGreen, csbRed, csbYellow, csbStale}
  of csbNotCurrent:
    toVal in {csbStale}   # legacy evidence is terminal; only staled
  of csbGreen:
    toVal in {csbStale, csbSoundnessDebt, csbYellow, csbNotCurrent}
  of csbYellow:
    toVal in {csbPending, csbStale, csbRed, csbGreen}
  of csbNoObligation:
    toVal in {csbPending, csbStale, csbRed, csbYellow}
  of csbStale:
    toVal in {csbPending, csbRed}
  of csbRed:
    toVal in {csbPending, csbStale}
  of csbZ3Verified:
    toVal in {csbLeanVerified, csbDualVerified, csbRed, csbStale}
  of csbZ3Candidate:
    toVal in {csbRed, csbStale}  # terminal candidate — never promotes to verified
  of csbLeanVerified:
    toVal in {csbStale, csbSoundnessDebt}
  of csbDualVerified:
    toVal in {csbStale, csbSoundnessDebt, csbGreen}
  of csbTypeLevelVerified:
    toVal in {csbGreen, csbStale}
  of csbVerifiedAxiom, csbPseudoVerified:
    toVal in {csbStale}
  of csbSoundnessDebt:
    toVal in {csbPending, csbRed}

func transitionStatus*(cert: var FunctionCertificate; newStatus: CertificateStatus): bool =
  if isValidTransition(cert.status, newStatus):
    cert.status = newStatus
    true
  else:
    false

func isValidCertificate*(cert: FunctionCertificate): bool =
  cert.modulePath.string.len > 0 and cert.functionName.len > 0

func newCertificate*(
  status: CertificateStatus;
  modulePath: FilePath;
  functionName: string;
  certificatePath: FilePath;
): Option[FunctionCertificate] =
  if not isValidCertificateStatus($status):
    return none(FunctionCertificate)
  if modulePath.string.len == 0 or functionName.len == 0:
    return none(FunctionCertificate)
  some(FunctionCertificate(
    certificatePath: certificatePath,
    modulePath: modulePath,
    functionName: functionName,
    status: status,
    fingerprint: "",
    currentFingerprint: "",
    structuralFingerprint: "",
    currentStructuralFingerprint: "",
    trusted: false,
    reason: "",
    verificationTier: vtNone
  ))

{.pop.}
