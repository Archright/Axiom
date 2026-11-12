import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

## Obligation types — canonical obligation IR layer.
##
## These types are backend-independent and self-contained.
## They form the SSOT for obligation identity, generation results,
## proof state, and the LightNonEmptySeq wrapper.
##
## Design decisions:
## - ObligationKind uses `ok` prefix per existing repo convention
##   (cf. verification_model_types.nim: okUserContract, okImplicitSafety).
## - VerificationObligation carries a typed proposition: IRExpr plus a
##   predicate: string that is the deterministic, information-preserving
##   canonical serialization of the proposition, used for identity.
##   assumptions is a string.
## - LightNonEmptySeq uses `distinct seq[T]` so that the compiler enforces
##   non-emptiness at the type level; the constructor doAssert-guards len >= 1.
## - computeObligationId uses a single canonicalizePredicate path and
##   sha256Hex from core/crypto/hash_kernel for deterministic identity.

import std/[options, sequtils, strutils, algorithm]
import core/trusted/axiom_ir
import core/crypto/hash_kernel

# ---------------------------------------------------------------------------
# ObligationKind — canonical obligation categories
# ---------------------------------------------------------------------------

type
  ObligationKind* = enum
    ## Safety obligations — runtime errors that must be prevented.
    okSafetyDiv          ## division-by-zero safety
    okSafetyIndex        ## index-out-of-bounds safety
    okSafetyLoopBound    ## loop-bound safety (variant / termination)
    ## Contract obligations — user-annotated or synthesised contracts.
    okContractInvariant  ## class / object invariant
    okContractPost       ## postcondition
    okContractPre        ## precondition
    ## General invariant obligation (not tied to a class).
    okInvariant
    ## Placeholder — effect obligations are not yet modelled.
    okEffect
    ## Placeholder — domain obligations are not yet modelled.
    okDomain

# ---------------------------------------------------------------------------
# UnsupportedReason — closed list of scope-out reasons
# ---------------------------------------------------------------------------

type
  UnsupportedReason* = enum
    usScopedRecursiveHeapNotModeled
    usScopedHigherOrderEffectNotModeled
    usScopedLanguageConstructNotModeled

  ## Note: postcondition absence, CHC encoding gaps, backend unavailability,
  ## and code-path incompleteness are NOT valid UnsupportedReason values.
  ## Those are backend failures and must surface as ProofTerminal.ptInconclusive.

# ---------------------------------------------------------------------------
# IllFormedReason — mirrors semantic_validator error categories
# ---------------------------------------------------------------------------

type
  IllFormedReason* = enum
    ifUnknownSymbol       ## unresolved symbol reference (semantic layer 1)
    ifTypeMismatch        ## type validation failure (semantic layer 3)
    ifScopeViolation      ## duplicate symbol / scope issue (semantic layer 2)
    ifDefUseViolation     ## use of undeclared variable (semantic layer 4)
    ifAssignmentViolation ## assignment to non-state symbol (semantic layer 5)

# ---------------------------------------------------------------------------
# ProofPhase — workflow stage (progress indicator)
# ---------------------------------------------------------------------------

type
  ProofPhase* = enum
    ppCandidate          ## raw IR input, not yet analysed
    ppAnalyzed           ## analysis complete, obligations identified
    ppObligationDecision ## 4-way decision (Generated / NoApplicable / Unsupported / IllFormed)
    ppProofAttempted     ## proof attempt in progress
    ppTerminal           ## terminal state reached

# ---------------------------------------------------------------------------
# ProofTerminal — final verdict
# ---------------------------------------------------------------------------

type
  ProofTerminal* = enum
    ptProved                    ## obligation proved
    ptRefuted                   ## obligation refuted (counterexample found)
    ptNoApplicableObligation    ## no obligation applicable (proven)
    ptUnsupported               ## semantic scope out of model
    ptIllFormed                 ## semantic validation failure
    ptInvalidArtifact           ## backend artifact (e.g. generated Lean) was
                                ## structurally invalid: parse/elaboration/kernel
                                ## rejection; distinct from ptInconclusive
                                ## (backend unavailable/timeout/unknown)
    ptInconclusive              ## backend failure / internal error

# ---------------------------------------------------------------------------
# Terminal reason codes — typed reasons for artifact/inconclusive verdicts
# ---------------------------------------------------------------------------

type
  ArtifactReason* = enum
    arParseError        ## generated artifact failed parsing
    arElaborationError  ## generated artifact failed Lean elaboration
    arKernelRejected    ## artifact compiled but was rejected by the kernel

  InconclusiveReason* = enum
    irUnknown            ## no finer reason available
    irTimeout            ## backend timed out
    irBackendUnavailable ## backend executable unavailable
    irExecutionFailure   ## backend crashed / failed to execute

  TerminalReason* = object
    ## Typed reason carried by ObligationOutcome.reason.  Exactly one Option
    ## field is set, matching the terminal value: ptInvalidArtifact →
    ## artifact; ptInconclusive → inconclusive; all other terminals → none.
    artifact*: Option[ArtifactReason]
    inconclusive*: Option[InconclusiveReason]

# ---------------------------------------------------------------------------
# ObligationOutcome — phase and terminal are separate fields
# ---------------------------------------------------------------------------

type
  ObligationOutcome* = object
    phase*: ProofPhase
    terminal*: Option[ProofTerminal]
    detail*: string
    reason*: Option[TerminalReason]  ## typed reason; set for ptInvalidArtifact (artifact)
                                    ## and ptInconclusive (inconclusive), none otherwise
    conditionalGuarantee*: bool = false
      ## Reporting surface for a CONDITIONAL guarantee: true when the verdict
      ## holds only under assumptions that were assumed rather than discharged
      ## (e.g. the `a + b < 256` caller obligation of the Rust u8 `+` slice).
      ## No ProofTerminal value was added for this: the verdict space is a
      ## closed list and conditionality is report metadata, not a verdict.
    undischargedAssumptions*: seq[string] = @[]
      ## Canonical assumption strings carried as hypotheses, not proven.
      ## Non-empty iff conditionalGuarantee is true.

func withConditionalGuarantee*(outcome: ObligationOutcome;
    undischargedAssumptions: seq[string]): ObligationOutcome {.raises: [].} =
  ## Mark `outcome` as a conditional guarantee over the given undischarged
  ## assumptions. Pure reporting transform: phase, terminal, detail and reason
  ## are carried through unchanged, so callers cannot use it to alter a
  ## verdict — only to say under what assumptions it holds.
  ObligationOutcome(
    phase: outcome.phase,
    terminal: outcome.terminal,
    detail: outcome.detail,
    reason: outcome.reason,
    conditionalGuarantee: undischargedAssumptions.len > 0,
    undischargedAssumptions: undischargedAssumptions)

# ---------------------------------------------------------------------------
# LightNonEmptySeq — seq[T] wrapper with len >= 1 enforced by constructor
# ---------------------------------------------------------------------------

type
  LightNonEmptySeq*[T] = object
    value*: seq[T]

func makeLightNonEmpty*[T](xs: seq[T]): LightNonEmptySeq[T] =
  doAssert xs.len > 0, "LightNonEmptySeq requires non-empty sequence"
  LightNonEmptySeq[T](value: xs)

func items*[T](seq: LightNonEmptySeq[T]): seq[T] {.inline, raises: [].} =
  seq.value

func len*[T](seq: LightNonEmptySeq[T]): int {.inline, raises: [].} =
  seq.value.len

func toSeq*[T](seq: LightNonEmptySeq[T]): seq[T] {.inline, raises: [].} =
  seq.value

# ---------------------------------------------------------------------------
# Canonical predicate normalisation — single path for C4 identity
# ---------------------------------------------------------------------------
#
# Framing scheme.  Every value read out of the IR (identifier, literal, enum
# tag, type) is emitted as a length-prefixed atom `<byteLen>:<text>`; the
# characters `(`, `)`, `,`, `[`, `]` are structural punctuation and `~`
# denotes an absent (nil) child.  That token set is uniquely decodable: at a
# token boundary a reader consumes either one structural character / `~`, or
# the digits up to the mandatory `:` followed by exactly that many bytes.
# The output therefore determines the IR, and an identifier may contain `,`,
# `)`, `[` or `:` freely — `a,b` frames to `3:a,b`, which cannot collide with
# the two identifiers `a` and `b` framed as `1:a,1:b`.

const
  CanonNil = "~"   ## Marker for an absent (nil) IR child.

func canonAtom(s: string): string {.raises: [].} =
  $s.len & ":" & s

func canonInt(v: int64): string {.raises: [].} =
  canonAtom($v)

func canonBool(b: bool): string {.raises: [].} =
  if b: "1" else: "0"

func canonAtoms(xs: openArray[string]): string {.raises: [].} =
  ## Comma-joined framed atoms inside a bracketed group.
  result = "["
  for i, x in xs:
    if i > 0: result.add(",")
    result.add(x)
  result.add("]")

func canonInts(xs: openArray[int64]): string {.raises: [].} =
  var parts: seq[string] = newSeqOfCap[string](xs.len)
  for x in xs:
    parts.add(canonInt(x))
  canonAtoms(parts)

func canonNames(xs: openArray[string]): string {.raises: [].} =
  var parts: seq[string] = newSeqOfCap[string](xs.len)
  for x in xs:
    parts.add(canonAtom(x))
  canonAtoms(parts)

func canonType(t: IRType): string {.raises: [].} =
  ## Nil-safe canonical form of an IRType.  Frames every name so that an enum
  ## or variant whose name contains `,` cannot shift the field boundaries.
  if t == nil:
    return CanonNil
  case t.kind
  of irtBitVec64:
    "BV64"
  of irtBool:
    "BOOL"
  of irtString:
    "STR"
  of irtList:
    "LIST(" & canonType(t.elemType) & ")"
  of irtEnum:
    "ENUM(" & canonAtom(t.enumName) & "," & canonNames(t.enumValues) & "," &
      canonInts(t.enumOrdinals) & ")"
  of irtVariant:
    var payloads: seq[string] = newSeqOfCap[string](t.variantPayloadTypes.len)
    for pt in t.variantPayloadTypes:
      payloads.add(canonType(pt))
    "VARIANT(" & canonAtom(t.variantName) & "," & canonNames(t.variantTags) &
      "," & canonInts(t.variantOrdinals) & "," & canonAtoms(payloads) & "," &
      canonInt(t.tagBitWidth.int64) & ")"

func canonicalizePredicate*(e: IRExpr): string {.raises: [].}

func canonicalizeLoop(e: IRExpr): string {.raises: [].}

func canonExprs(xs: openArray[IRExpr]): string {.raises: [].} =
  var parts: seq[string] = newSeqOfCap[string](xs.len)
  for x in xs:
    parts.add(canonicalizePredicate(x))
  canonAtoms(parts)

func canonicalizePredicate*(e: IRExpr): string {.raises: [].} =
  ## Deterministic, information-preserving string representation of an IRExpr
  ## for identity hashing.  Every field and every child that can differ
  ## between two IRs contributes to the output, so two materially different
  ## obligations cannot collapse onto the same id.
  ##
  ## Uses alpha-equivalent naming (variables are preserved as-is; the
  ## identity is scoped to a single subject so alpha-renaming is not
  ## required within one obligation).  Children are sorted only where the
  ## operation is commutative (AND, OR, EQ); every other sequence keeps
  ## source order, which is stable for a given IR.
  if e == nil:
    return CanonNil
  case e.kind
  of irLit:
    # Two-part literal form: the u64-domain representation is a DISTINCT
    # canonical atom ("litU64(...)") — it must never collide with the signed
    # "lit(0)" its zeroed litVal would otherwise produce.
    if e.litU64 != 0'u64:
      result = "litU64(" & canonAtom($e.litU64) & ")"
    else:
      result = "lit(" & canonInt(e.litVal) & ")"
  of irFloatLit:
    result = "floatLit(" & canonAtom($e.floatVal) & ")"
  of irVar:
    result = "var(" & canonAtom(e.varName) & "," & canonType(e.varType) & ")"
  of irLet:
    result = "let(" & canonAtom(e.letName) & "," & canonBool(e.isCompileTime) &
             "," & canonicalizePredicate(e.letVal) & "," &
             canonicalizePredicate(e.letBody) & ")"
  of irIf:
    result = "if(" & canonicalizePredicate(e.ifCond) & "," &
             canonicalizePredicate(e.ifThen) & "," &
             canonicalizePredicate(e.ifElse) & ")"
  of irCase:
    var branches: seq[string] = newSeqOfCap[string](e.caseBranches.len)
    for br in e.caseBranches:
      branches.add(canonInt(br.pattern) & "=>" & canonicalizePredicate(br.body))
    result = "case(" & canonicalizePredicate(e.caseScrutinee) & "," &
             canonAtoms(branches) & "," &
             canonicalizePredicate(e.caseDefault) & ")"
  of irCall:
    result = "call(" & canonAtom(e.callName) & "," & canonExprs(e.callArgs) & ")"
  of irBinOp:
    let lhs = canonicalizePredicate(e.binLhs)
    let rhs = canonicalizePredicate(e.binRhs)
    case e.binOp
    of boAnd, boOr, boEq:
      # Commutative — sort children for canonical order.
      let sorted = [lhs, rhs].sorted
      result = canonAtom($e.binOp) & "(" & sorted[0] & "," & sorted[1] & ")"
    else:
      result = canonAtom($e.binOp) & "(" & lhs & "," & rhs & ")"
  of irUnaryOp:
    result = canonAtom($e.unaryOp) & "(" &
             canonicalizePredicate(e.unaryArg) & ")"
  of irRecCall:
    result = "recCall(" & canonExprs(e.recArgs) & ")"
  of irLoop:
    result = canonicalizeLoop(e)
  of irStringLit:
    result = "str(" & canonAtom(e.stringVal) & ")"
  of irCast:
    result = "cast(" & canonicalizePredicate(e.castExpr) & "," &
             canonType(e.castFrom) & "," & canonType(e.castTo) & ")"

func canonicalizeLoop(e: IRExpr): string {.raises: [].} =
  ## Every loop field contributes, in a fixed order, so two loops that differ in
  ## any of them cannot share a canonical predicate.
  "loop(" & canonAtom($e.loopKind) & "," &
  canonNames(e.loopVars) & "," & canonExprs(e.loopInits) & "," &
  canonicalizePredicate(e.loopCond) & "," &
  canonicalizePredicate(e.loopStep) & "," &
  canonicalizePredicate(e.loopBody) & "," &
  canonExprs(e.loopInvariants) & "," &
  canonicalizePredicate(e.loopVariant) & ")"

# ---------------------------------------------------------------------------
# AssumptionOrigin — provenance discriminator for the assumption channel
# ---------------------------------------------------------------------------

type
  AssumptionOrigin* = enum
    ## Where an obligation's assumption / precondition hypothesis comes from.
    ## The two width conditions of the Rust u8 `+` slice show why the channel
    ## must be discriminated: `0 ≤ a,b < 256` is derived MECHANICALLY from the
    ## source type's value range, while `a + b < 256` is a SEPARATE caller
    ## obligation discharging the overflow condition of plain `+`
    ## (docs/spec/rust_certified_subset.md, "Width precondition"). Axiom IR has
    ## no u8 (irtBitVec64 only), so the derivation source cannot be re-derived
    ## from the IR — it must be carried explicitly. Conflating the origins
    ## would launder a caller duty into a type fact (and vice versa).
    aoUserDeclared      ## user-declared hypothesis; the legacy channel — every
                        ## obligation produced before this discriminator existed
                        ## carries this value
    aoTypeDerived       ## derived mechanically from a source-language type's
                        ## value range (e.g. u8 → 0 ≤ a,b < 256)
    aoCallerObligation  ## declared to discharge an overflow / behavior
                        ## condition (e.g. a + b < 256 guarding plain `+`)

# ---------------------------------------------------------------------------
# C4 identity — deterministic obligation ID
# ---------------------------------------------------------------------------

func computeObligationId*(
  subject: string,
  kind: ObligationKind,
  canonicalAssumptions: string,
  canonicalPredicate: string,
  derivationRule: string,
  assumptionOrigin: AssumptionOrigin = aoUserDeclared
): string {.raises: [].} =
  ## Deterministic obligation identity from the plan's 5-tuple extended with
  ## assumptionOrigin. Uses a single canonicalization path
  ## (canonicalizePredicate) and SHA-256.
  ## This id names WHAT is claimed but not WHICH lowered subject semantics the
  ## claim is about; the evidence-facing identity is computeBoundObligationId.
  ##
  ## IDENTITY CHANGE (documented): assumptionOrigin is ALWAYS part of the
  ## payload, so every obligation id computed before the discriminator existed
  ## changes value exactly once — a generation cutover; stale evidence must
  ## re-seal (same discipline as the composition note on
  ## ObligationSubjectBinding below). The origin is appended unconditionally
  ## because any scheme that preserves the legacy digest for the default value
  ## is forgeable: the free-string fields may contain `|`, so a conditional
  ## suffix could be smuggled into a derivationRule, collapsing two origins
  ## onto one id. The enum-name suffixes have distinct lengths and distinct
  ## final characters, so two payloads with different origins can never be
  ## equal. Existing call sites compile unchanged via the default parameter;
  ## recomputation is uniform, so internal consistency (equal tuples ⇔ equal
  ## ids) is preserved.
  let payload = subject & "|" & $kind & "|" & canonicalAssumptions & "|" &
                canonicalPredicate & "|" & derivationRule & "|" &
                $assumptionOrigin
  sha256Hex(payload)

# ---------------------------------------------------------------------------
# Subject-bound obligation identity — I1 minimum binding set
# ---------------------------------------------------------------------------
## Two funcDefs that share name/kind/assumptions/predicate/derivationRule
## while differing in body produce the same 5-tuple id, so evidence sealed
## under one id can attach to the other's shadow (independent re-derivation
## of the same proposition over different lowering). The bound identity folds
## the subject-side measurements of the canonical pipeline into the digest so
## the id itself names the subject bytes, the IR, the extraction agreement,
## the completeness record, the rendered Lean source and the measured
## toolchain. Composition is fixed by docs/spec/obligation_semantics.md §2.1a;
## any change there is a generation cutover (stale evidence must re-seal).

type
  ObligationSubjectBinding* = object
    obligationTupleId*: string        ## computeObligationId over the 5-tuple
    subjectTreeMerkleRoot*: string    ## computeSourceMerkleRoot over the subject tree
    subjectModuleSha256*: string      ## §6a sourceHash — sha256 of subject module bytes
    subjectGitRef*: string            ## git commit-or-tree hash pinning the subject
    pnodeCanonicalV2Digest*: string   ## computeCanonicalAstHash of the funcDef source
    irDigest*: string                 ## sha256Hex(serializeIRFuncDef(funcDef))
    eaNimDigest*: string              ## ExtractionAgreementResult.nimDigest
    eaLeanDigest*: string             ## ExtractionAgreementResult.leanDigest
    eaIrcheckBinaryDigest*: string    ## sha256 of the ircheck worker binary
    eaAgreed*: bool                   ## ExtractionAgreement verdict == eaAgree
    completenessRecordDigest*: string ## digest of the CompletenessEvidence for irDigest
    leanSourceHash*: string           ## sha256 of the rendered Lean source
    toolchainFingerprint*: string     ## measured toolchain/bundle fingerprint
    # Synthesized-subject extension (base36 sizing binding contract §2.1a +
    # base32 rem-range binding contract §3 D2): when the subject is a
    # synthesized composite, the single-symbol EA cannot apply to it literally
    # — the binding carries BOTH original symbols' extraction agreements plus
    # the digest of the recorded deterministic β-splice derivation rule. When
    # `claimCarrierSingleOrigin` is set, the subject is a synthesized claim
    # CARRIER derived from ONE original symbol: exactly one EA leg, the
    # derivation digest, and an EMPTY ea2 slot (a filled second leg is a
    # fabricated measurement). Empty derivation digest = the subject is a
    # plain single symbol and the second leg must be empty.
    synthesisDerivationDigest*: string ## composite/claim-carrier mode marker+rule record digest
    claimCarrierSingleOrigin*: bool    ## single-origin claim-carrier mode: ea2 slot MUST be empty
    ea2NimDigest*: string              ## second original's EA nimDigest
    ea2LeanDigest*: string             ## second original's EA leanDigest
    ea2IrcheckBinaryDigest*: string    ## second original's EA ircheck binary digest
    ea2Agreed*: bool                   ## second original's ExtractionAgreement verdict

func isSha256Hex(s: string): bool {.raises: [].} =
  if s.len != 64:
    return false
  for ch in s:
    if ch notin {'0'..'9', 'a'..'f'}:
      return false
  true

func isGitRef(s: string): bool {.raises: [].} =
  ## Commit-or-tree hash: 40 hex (sha1 repos) or 64 hex (sha256 repos).
  if s.len != 40 and s.len != 64:
    return false
  for ch in s:
    if ch notin {'0'..'9', 'a'..'f'}:
      return false
  true

type
  BoundBindingMode* = enum
    ## Which synthesized-subject shape the binding carries. Determined by the
    ## binding's own fields — never by caller-supplied state.
    bbmSingleSymbol                 ## plain single-symbol subject (no derivation rule)
    bbmComposite                    ## two-leg synthesized composite (base36 §2.1a)
    bbmClaimCarrierSingleOrigin     ## one-leg claim carrier (base32 rem §3 D2)

func boundBindingMode(binding: ObligationSubjectBinding): BoundBindingMode {.
  raises: [].} =
  if binding.claimCarrierSingleOrigin:
    bbmClaimCarrierSingleOrigin
  elif binding.synthesisDerivationDigest.len > 0:
    bbmComposite
  else:
    bbmSingleSymbol

func bindingModeComponents(binding: ObligationSubjectBinding;
                           mode: BoundBindingMode): seq[bool] {.raises: [].} =
  ## Mode-specific canonical-form checks appended to the base component set:
  ## composite mode requires a canonical SECOND leg; single-origin mode
  ## requires a canonical derivation digest and an EMPTY ea2 slot; plain
  ## single-symbol mode requires the ea2 slot to be empty.
  case mode
  of bbmComposite:
    @[
      isSha256Hex(binding.synthesisDerivationDigest),
      isSha256Hex(binding.ea2NimDigest),
      isSha256Hex(binding.ea2LeanDigest),
      isSha256Hex(binding.ea2IrcheckBinaryDigest)
    ]
  of bbmClaimCarrierSingleOrigin:
    @[
      isSha256Hex(binding.synthesisDerivationDigest),
      binding.ea2NimDigest.len == 0,
      binding.ea2LeanDigest.len == 0,
      binding.ea2IrcheckBinaryDigest.len == 0
    ]
  of bbmSingleSymbol:
    @[
      binding.ea2NimDigest.len == 0,
      binding.ea2LeanDigest.len == 0,
      binding.ea2IrcheckBinaryDigest.len == 0
    ]

func computeBoundObligationId*(binding: ObligationSubjectBinding): string {.
  raises: [].} =
  ## SHA-256 over the labeled minimum binding set. Fail-closed: any absent or
  ## non-canonical component yields "" — "" is not an identity, and callers
  ## must refuse to issue or bind evidence under it. Measured digests are
  ## lowercase sha256 hex (the canonical form of hash_kernel output); no
  ## wall-clock, run id or path enters the payload.
  ##
  ## Composite mode (§2.1a of the base36 sizing binding contract): a non-empty
  ## `synthesisDerivationDigest` with `claimCarrierSingleOrigin == false` marks
  ## a synthesized relational composite — the payload then additionally folds
  ## the recorded derivation rule and the SECOND original symbol's extraction
  ## agreement (both legs are required and both must be canonical). Composite
  ## mode with a malformed second leg yields "", and non-composite mode with
  ## any second-leg content set is itself malformed and yields "" — the two
  ## modes are never conflated.
  ##
  ## Single-origin claim-carrier mode (§3 D2 of the base32 rem-range binding
  ## contract): `claimCarrierSingleOrigin == true` marks a synthesized claim
  ## carrier derived from ONE original symbol — the derivation digest is
  ## required (canonical), the ea2 slot is required EMPTY (there is no second
  ## original; a filled one is a fabricated measurement), and the payload folds
  ## the derivation rule next to the single EA leg. This mode never produced an
  ## id before its introduction (the composite two-leg gate always rejected it),
  ## so its payload composition is additive: no previously sealed identity is
  ## affected.
  let mode = boundBindingMode(binding)
  var components: seq[bool] = @[
    isSha256Hex(binding.obligationTupleId),
    isSha256Hex(binding.subjectTreeMerkleRoot),
    isSha256Hex(binding.subjectModuleSha256),
    isGitRef(binding.subjectGitRef),
    binding.pnodeCanonicalV2Digest.len > 0,
    isSha256Hex(binding.irDigest),
    isSha256Hex(binding.eaNimDigest),
    isSha256Hex(binding.eaLeanDigest),
    isSha256Hex(binding.eaIrcheckBinaryDigest),
    binding.completenessRecordDigest.len > 0,
    isSha256Hex(binding.leanSourceHash),
    isSha256Hex(binding.toolchainFingerprint)
  ]
  components &= bindingModeComponents(binding, mode)
  for ok in components:
    if not ok:
      return ""
  var payload =
    "obligation-bound-v1" &
    "|tuple=" & binding.obligationTupleId &
    "|treeMerkle=" & binding.subjectTreeMerkleRoot &
    "|module=" & binding.subjectModuleSha256 &
    "|git=" & binding.subjectGitRef &
    "|pnodeV2=" & binding.pnodeCanonicalV2Digest &
    "|ir=" & binding.irDigest &
    "|ea=" & (if binding.eaAgreed: "agree:" else: "disagree:") &
      binding.eaNimDigest & "," & binding.eaLeanDigest & "," &
      binding.eaIrcheckBinaryDigest
  case mode
  of bbmComposite:
    payload &=
      "|derivation=" & binding.synthesisDerivationDigest &
      "|ea2=" & (if binding.ea2Agreed: "agree:" else: "disagree:") &
        binding.ea2NimDigest & "," & binding.ea2LeanDigest & "," &
        binding.ea2IrcheckBinaryDigest
  of bbmClaimCarrierSingleOrigin:
    payload &=
      "|derivation=" & binding.synthesisDerivationDigest
  of bbmSingleSymbol:
    discard
  payload &=
    "|completeness=" & binding.completenessRecordDigest &
    "|leanSource=" & binding.leanSourceHash &
    "|toolchain=" & binding.toolchainFingerprint
  sha256Hex(payload)

# ---------------------------------------------------------------------------
# ObligationSkipReason — canonical pipeline skip classification (DEBT#422)
# ---------------------------------------------------------------------------
## Canonical classification for batch-UAP nodes that terminate without a
## normal verification verdict.  Supersedes the string-literal skipReason
## mapping that previously lived in loop_driver.nim; the `$` renderer keeps
## the legacy serialized values ("no_obligation", "bmc_skipped",
## "obligation_terminal") so downstream consumers stay byte-identical.

type
  ObligationSkipReason* = enum
    osrNone                ## no skip — normal termination (verified / failed / timeout)
    osrNoObligation        ## proven absence of obligations (rkNoObligation / ogrNoApplicableObligation)
    osrBmcSkipped          ## BMC skipped — type not representable in QF_BV (vpBmcSkipped)
    osrObligationTerminal  ## obligation generator terminal (ogrUnsupported / ogrIllFormed)
    osrDroppedOutsideScope ## obligation generated but dropped outside verification scope (non-golden ids)
    osrDroppedNoPlan       ## obligation generated but no plan was created (no golden obligation executed)

func `$`*(reason: ObligationSkipReason): string {.raises: [].} =
  ## Serialization invariant (DEBT#422): renders the exact legacy literals.
  case reason
  of osrNone: ""
  of osrNoObligation: "no_obligation"
  of osrBmcSkipped: "bmc_skipped"
  of osrObligationTerminal: "obligation_terminal"
  of osrDroppedOutsideScope: "dropped_outside_scope"
  of osrDroppedNoPlan: "dropped_no_plan"

{.pop.}
