import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
import std/[options, strutils]
import core/trusted/axiom_pragmas
import core/trusted/axiom_ir
import core/trusted/verification_model_types

## Backend capability layer — the single SSOT for "can backend B SOUNDLY
## REPRESENT obligation O?". This is a *representation-capability* question
## (expressibility), NOT a *provability* question ("can the solver discharge
## it?"). It answers whether the obligation's required semantic features are
## statically expressible in the backend's target logic, independently of any
## solver run.
##
## Capability vs execution-availability separation:
##   `canEncode` answers representability (sound encoding exists).
##   `availableToRun` answers whether the backend has a wired execution path
##   today. A backend may be representable but not runnable (bkBmc is
##   representable but has no BMC executor wired; it is a future capability
##   axis). `isRunnable` resolves routing targets — only backends that are
##   both representable AND available to run should be used as execution
##   targets.
##
## Backend model:
##   * CHC  — transition-system / constrained-Horn-Clause encoding (Spacer).
##   * BMC  — depth-bounded unrolling (requires a resolved static loop bound).
##   * Lean — FUTURE (no encoder exists today; intentionally NOT a member of
##     `Backend`). Lean is reserved for a later capability axis once a Lean
##     encoder is wired; see P2 note in the design record.
##
## Capability is modelled as a feature-set comparison:
##   RequiredProfile  = theories ∪ control × contracts
##   canEncode = required ⊆ backend_capabilities
##
## It is deliberately NOT a hardcoded "QF_BV vs QF_AUFBV" boolean, because
## those theories are *derived consequences* of the feature set, and a future
## backend (or a finer encoding) should be able to trade theories without
## changing the obligation model.

type
  Backend* = enum
    bkChc  ## transition-system CHC encoding (VerificationModel → HORN script)
    bkBmc  ## depth-bounded unrolling; needs a resolved static loop bound

  TheoryKind* = enum
    thBitVec   ## fixed-width bit-vector arithmetic (QF_BV)
    thArray    ## array / seq sorts (QF_AUFBV)
    thString   ## string sorts (representable by NO current backend — I2 territory)
    thUF       ## uninterpreted functions

  ControlKind* = enum
    ctBoundedLoop    ## for-loop with a statically resolvable bound
    ctTransitionSys  ## loop encoded as an init/trans relation (phase machines)
    ctRecursive      ## structural recursion / self-recursion

  CapabilityContractKind* = enum
    ccPrecondition
    ccPostcondition
    ccInvariant

  BackendCapability* = object
    backend*: Backend
    theories*: set[TheoryKind]
    controls*: set[ControlKind]
    contracts*: set[CapabilityContractKind]
    availableToRun*: bool

  ContractProfile* = object
    theories*: set[TheoryKind]
    control*: ControlKind
    contracts*: set[CapabilityContractKind]

# ── Per-backend capability table (SSOT) ────────────────────────────────────
func capabilitiesOf*(backend: Backend): BackendCapability {.axiomDecision(
  id = "DECISION-0612",
  reason = "Per-backend capability table — the SSOT that maps a backend to its representable feature set (theories × control × contracts); Lean is future/absent",
  adr = "docs/spec/verification_result_types.md",
  introduced = "v37").} =
  case backend
  of bkChc:
    BackendCapability(
      backend: bkChc,
      theories: {thBitVec, thArray},
      controls: {ctTransitionSys, ctBoundedLoop},
      contracts: {ccPostcondition, ccInvariant},
      availableToRun: true
    )
  of bkBmc:
    BackendCapability(
      backend: bkBmc,
      theories: {thBitVec, thArray},
      controls: {ctBoundedLoop},
      contracts: {ccPostcondition},
      availableToRun: false
    )

func profileOf*(model: VerificationModel): ContractProfile {.axiomDecision(
  id = "DECISION-0613",
  reason = "Derive a VerificationModel's required-representation profile (theories × control × contracts) from its semantic fields",
  adr = "docs/spec/verification_result_types.md",
  introduced = "v37").} =
  ## Compute the feature-set the obligation REQUIRES the backend to represent.
  let sem = model.semantic
  var profile = ContractProfile(
    theories: {},
    control: ctTransitionSys,
    contracts: {}
  )
  for st in sem.states:
    if st.irType == nil: continue
    case st.irType.kind
    of irtList: profile.theories.incl(thArray)
    of irtString: profile.theories.incl(thString)
    else: profile.theories.incl(thBitVec)
  # contracts — obligation KIND is the contract axis: user contracts are
  # postconditions; implicit/derived safety are loop invariants.
  if sem.property.isSome and sem.property.get != nil:
    profile.contracts.incl(ccPostcondition)
  for ob in sem.obligations:
    case ob.kind
    of okUserContract: profile.contracts.incl(ccPostcondition)
    of okImplicitSafety, okDerivedSafety: profile.contracts.incl(ccInvariant)
  # control: prefer bounded-loop when loop facts are bounded; else transition system.
  if sem.loopFacts.isSome and sem.loopFacts.get.kind == lfkBounded:
    profile.control = ctBoundedLoop
  elif sem.states.len > 0:
    profile.control = ctTransitionSys
  if profile.theories == {}:
    profile.theories = {thBitVec}
  profile

# ── The capability gate ────────────────────────────────────────────────────
func canEncode*(profile: ContractProfile; capability: BackendCapability): bool {.axiomDecision(
  id = "DECISION-0614",
  reason = "canEncode — true iff the obligation's required features are a subset of the backend's capabilities (sound-representation, not provability)",
  adr = "docs/spec/verification_result_types.md",
  introduced = "v37").} =
  ## The single sound-representation predicate: required ⊆ capability.
  profile.theories <= capability.theories and
  (profile.control in capability.controls) and
  profile.contracts <= capability.contracts

func canEncode*(profile: ContractProfile; backend: Backend): bool {.axiomDecision(
  id = "DECISION-0615",
  reason = "Convenience overload — canEncode(profile, backend) resolves the backend's capability table",
  adr = "docs/spec/verification_result_types.md",
  introduced = "v37").} =
  canEncode(profile, capabilitiesOf(backend))

func canEncode*(model: VerificationModel; backend: Backend): bool {.axiomDecision(
  id = "DECISION-0616",
  reason = "canEncode(model, backend) — derives the model profile then consults the capability table",
  adr = "docs/spec/verification_result_types.md",
  introduced = "v37").} =
  canEncode(profileOf(model), backend)

func compatibilityReason*(profile: ContractProfile; backend: Backend): string {.axiomDecision(
  id = "DECISION-0617",
  reason = "Deterministic human-readable explanation of WHY an obligation is (un)encodable for a backend; aids diagnostics without weakening decisions",
  adr = "docs/spec/verification_result_types.md",
  introduced = "v37").} =
  let cap = capabilitiesOf(backend)
  if profile.contracts <= cap.contracts and
     profile.theories <= cap.theories and
     profile.control in cap.controls:
    "encodable"
  else:
    var missing: seq[string] = @[]
    for th in profile.theories:
      if th notin cap.theories: missing.add($th)
    if not (profile.control in cap.controls):
      missing.add("control:" & $profile.control)
    for ck in profile.contracts:
      if ck notin cap.contracts: missing.add("contract:" & $ck)
    "not-encodable-for-" & $backend & ": missing " & missing.join(",")

# ── Execution-availability gate ────────────────────────────────────
func isRunnable*(backend: Backend): bool {.axiomDecision(
  id = "DECISION-0618",
  reason = "Execution-availability predicate — true only for backends that have a wired execution path today; routes routing targets through a single source of truth (capabilitiesOf)",
  adr = "docs/spec/verification_result_types.md",
  introduced = "v37").} =
  capabilitiesOf(backend).availableToRun

{.pop.}