import core/trusted/layer_declaration
axiomLayer "presentation"
{.push raises: [].}

import std/[json, strutils]
import core/crypto/hash_kernel
import core/types/results
import core/utils/decision_algebra
import core/trusted/bug_attribution_grounds

## Bug verdict display projection — 2축 표시 투영 (display labels ONLY).
##
## SSOT: docs/spec/bug_verdict_glossary.md — §2.2 (공용 4요소 shared quartet),
## §2.4 (RULE/귀속 축 분리 + 정밀도 규칙), §2.4a (Bug Confirmed — {A, C}의
## 순수 함수, M은 입력이 아님), §2.4b (전함수 우선순위 — 상호 배타적 · 전체),
## §2.4c (requirementSourceStatus → 불확실성 플래그 유도 + 교차 유도 금지),
## §2.4d (스코프·표시 결속 규칙 — 유닛-스코프 전제 + 주체 커밋·blob 스코프 표;
## 전제 자체는 표시 빌더가 계산하며 이 모듈은 그 결과와 디제스트 슬롯을 소비).
##
## v3 (bug-verdict-display-v3): the projection is PER-UNIT (the report block
## carries a `units` array, one entry per adopted governed unit) and the
## attribution labels are the reporter-facing spellings BUG_FOUND /
## BUG_SUSPECTED / UNKNOWN. Confirmation is E1-ONLY: a recorded-binding
## requirement source whose E1 ground is present-and-effective (non-empty
## refs + the C-carried reproduction quartet) confirms; E2/E3 are
## report-worthiness evidence surfaced via `groundsValidation` and can NEVER
## produce BUG_FOUND. BUG_SUSPECTED requires a validated record (A
## essentials) against a non-binding or undetermined requirement source
## (recordedDisclaiming | unrecorded | unknown). The adoptedSpecRef
## (specId + specRelPath) is bound into the display input digest —
## tamper-evidence for the unit↔overlay link.
##
## Hard rules honored here (glossary §1):
##   - No enum, no producer, no gate, no required check is introduced. Every
##     label below is a DISPLAY STRING projected from already-decided machine
##     spellings (received as parameters — the vr*/vd*/cl* identifiers are
##     never named here) and validated record fields.
##   - The attribution function is a PURE function of the display-layer
##     inputs {proposition, source status, E1 effectiveness, A validity}.
##     The machine half (M) is never an input to attribution — it only
##     premises the RULE-axis label, rides along as co-displayed machine
##     states, and feeds the verification-proof uncertainty flag (§2.4c,
##     one direction only).
##   - Fail closed: missing/invalid ownership or an unverified grounds record
##     degrades the attribution to Unknown and surfaces a fail-visible reason
##     in `groundsValidation` — it never fabricates a name.
##
## Scoping note (honest boundary): A-essential structure (contrast via
## violationStatement, external reproduction source, role independence) is
## enforced mechanically at the record layer by `validateGroundsFile` (closed
## schema), so a validated record is A-valid by construction; the display
## layer never re-derives A from machine content.

const
  ruleViolatedLabel* = "Axiom-Defined Rule Violated"
  bugConfirmedLabel* = "BUG_FOUND"
  bugSuspectedLabel* = "BUG_SUSPECTED"
  attributionUnknownLabel* = "Unknown"
  upstreamSpecKind* = "upstream-spec"
  verificationProofKind* = "verification-proof"
  displayInputDigestPurpose* = "provenance-trace-only — not a verdict legitimacy proof"
  unrecordedOwnerSpelling* = "unrecorded"
  bugVerdictDisplaySchemaVersion* = "bug-verdict-display-v3"
    ## §2.4d projection schema version — bound into the display input digest
    ## and carried by the report block's top-level `schemaVersion` key.
  requirementSourceUnknownSpelling* = "unknown"
    ## The 4th closed-set status: source determination incomplete. Emitted
    ## when the record layer left no status (absent/rejected record) and
    ## declarable by a record whose source determination is itself
    ## incomplete; never confirms and never records a binding.

  ## Subject-scope status spellings (closed string set — glossary §2.4d scope
  ## table). Deliberately NOT an enum: display-only, closed by the classifier.
  scopeVerifiedMatch* = "verifiedMatch"
  scopeCommitMismatch* = "commitMismatch"
  scopeCommitUnverifiable* = "commitUnverifiable"
  scopeBlobMismatch* = "blobMismatch"

  ## Machine-uncertainty spellings (glossary §2.4c): the four machine states in
  ## their identifier spelling AND their $-serialized spelling (only
  ## vrInconclusive serializes differently — "INCONCLUSIVE"). String
  ## comparison only — consumption, never production (glossary §1).
  machineUncertaintySpellings* = [
    "clUnknown", "vrInconclusive", "vsInconclusive", "cvUnresolved",
    "INCONCLUSIVE"]

  ## The proposition-verdict spellings (display layer, derived from the
  ## unit's machine claim spelling — never produced from a literal of the
  ## guarded vocabulary).
  propositionDisprovedSpelling* = "DISPROVED"
  propositionNotDisprovedSpelling* = "NOT_DISPROVED"
  propositionUnknownSpelling* = "UNKNOWN"

  ## Per-proposition capability rollup spellings (byo_agent_proposition_contract
  ## §3 two-axis state model). The rollup entries are DISPLAY STRINGS projected
  ## from decisions already made at intake/dispatch — this module never decides
  ## capability and never writes a guarded-vocabulary literal (glossary §1,
  ## evidence_truth_boundary gate [T4-b]).
  propositionCapabilityCapableSpelling* = "CAPABLE"
  propositionCapabilityIncapableSpelling* = "INCAPABLE"
  propositionRollupSchemaVersion* = "proposition-rollup-v1"
    ## The capability rollup's own projection schema version — the container's
    ## `bug-verdict-display-v3` asserts the per-unit blocks, not the rollup.

  ## The suspect-eligible requirement-source statuses (non-binding or
  ## undetermined source — a binding source is either confirmed via E1 or
  ## stays Unknown, never Suspected).
  suspectEligibleStatuses* = [
    "recordedDisclaiming", "unrecorded", requirementSourceUnknownSpelling]

type
  BugVerdictSubjectIdentity* = object
    ## The caller's §2.4d subject probe result (I/O lives at the caller — this
    ## is a pure value). probeOk=false ⇒ the exact-commit binding is
    ## unverifiable; block absence follows (not-applicable), never Unknown.
    probeOk*: bool
    commit*: string  ## `git rev-parse HEAD` at the subject root ("" when the probe failed)
    blob*: string    ## sha256 of the overlay module bytes ("" when unreadable)

  GroundsAssessment* = object
    ## Pure per-axis A/C assessment over one grounds-record attempt.
    ## Derived ONLY from the record (never from M) — see assessGrounds.
    aValid*: bool              ## A essentials valid (shared quartet + external source + contrast + role independence)
    cValid*: bool              ## some confirmation category effective AND every present category quartet-complete
    cClaimed*: bool            ## some confirmation category claimed present (even when incomplete/voided — never confirms alone)
    cQuartetComplete*: bool    ## every effective present category carries the C-carried reproduction quartet
    dualUse*: bool             ## C dual-satisfies A's elements (dual ⇒ C exists — glossary §2.4b)
    e1Present*: bool           ## E1 claimed present (before any voiding) — the ONLY confirmation basis
    e1Effective*: bool         ## E1 present AND not voided (a validated record's E1 reproduction is quartet-complete by the validator)
    e2e3Present*: bool         ## E2/E3 claimed present — report-worthiness evidence ONLY, never confirms
    requirementSourceStatus*: string  ## closed-set status from the validated view ("" when the record is absent/rejected)
    validationReason*: string  ## fail-visible record-layer reason ("" when the record validated)

  BugVerdictDisplayInput* = object
    ## Everything the pure projection consumes. The caller owns the I/O:
    ## machine spellings arrive as parameters (verdict enums are never named
    ## here), the ownership block and grounds record arrive as parsed JSON.
    machineEstablished*: bool    ## §2.4d unit-scoped conjunction result (display builder) — RULE-axis premise only
    machineTuple*: JsonNode      ## machine spellings actually consumed (e.g. verdict/basis/recordComplete) — digest input
    ruleId*: string              ## spec overlay ruleId (non-canonical descriptive text)
    ownership*: JsonNode         ## parsed claimOwnership object, or {"owner":"unrecorded"} on parse failure
    groundsRefs*: seq[string]    ## "ref#recordDigest" entries rendered by the caller
    groundsRawDigest*: string    ## sha256Hex of the raw grounds bytes, or "absent"
    assessment*: GroundsAssessment
    ## §2.4d decision inputs — every slot is bound into displayInputDigest.
    targetSymbol*: string = ""          ## the governed unit key (overlay modulePath::symbol)
    rowStatus*: string = ""             ## selected observedRows row status ("" = no row)
    scopeStatus*: string = ""           ## §2.4d closed-set classification (verifiedMatch …)
    claimOutcome*: string = ""          ## the unit's claim verdict spelling ("" = absent — never fabricated)
    quartetPayloadDigest*: string = ""  ## sha256 over the unit's §2.2 payload lines ("" when absent)
    quartetComplete*: bool = false      ## the observed §2.2 quartet completeness (g1–g4 all present) — the structured icCounterexample record conjunct of propositionVerdictOf
    quartetLines*: seq[string] = @[]    ## raw counterexample payload lines — persistence carrier ONLY; NOT a digest input (quartetPayloadDigest already binds the payload)
    subjectCommit*: string = ""         ## probe commit bound into the digest
    subjectBlob*: string = ""           ## probe blob bound into the digest
    specId*: string = ""                ## overlay specId
    specRelPath*: string = ""           ## the adoptedSpecRef's registry document identity

  BugVerdictDisplay* = object
    ## One unit's 2축 display block. Every field is a projection label — none
    ## of them is a machine verdict value and none is consumed by any gate.
    targetSymbol*: string          ## the governed unit key this block projects
    adoptedSpecId*: string         ## adoptedSpecRef.specId — the unit's overlay identity
    adoptedSpecRelPath*: string    ## adoptedSpecRef.specRelPath — the registry document identity
    ruleJudgment*: string          ## "Axiom-Defined Rule Violated" | "" | non-canonical descriptive
    bugAttribution*: string        ## "BUG_FOUND" | "BUG_SUSPECTED" | "Unknown"
    propositionVerdict*: string    ## "DISPROVED" | "NOT_DISPROVED" | "UNKNOWN" (display layer)
    requirementSourceStatus*: string  ## closed-set status; "unknown" when the record left none
    uncertaintyKinds*: seq[string] ## fixed order [upstream-spec, verification-proof] — only when Suspected
    machineStates*: seq[string]    ## $-rendered existing enum spellings (co-display)
    groundsRefs*: seq[string]      ## "ref#recordDigest" form
    groundsValidation*: string     ## validation surface (fail-visible reasons)
    displayInputDigest*: string    ## provenance trace over the consumed inputs

  PropositionRollupDisplay* = object
    ## One proposition's two-axis rollup entry (contract §3). The
    ## machine-verification axis is unchanged — `verdict` is a
    ## propositionVerdictOf spelling (closed 3-value set) or "" (JSON null);
    ## the capability axis is a NEW sibling projected from intake/dispatch
    ## facts (INCAPABLE seeds from intake, LANE_NOT_EQUIPPED from the
    ## dispatch-winner record's absence). Display strings only — never a
    ## verdict production, never a gate input.
    id*: string
    capabilityStatus*: string  ## "CAPABLE" | "INCAPABLE"
    capabilityReason*: string  ## INCAPABLE reason spelling ("" on CAPABLE)
    attempted*: bool           ## an engine lane actually attempted this proposition
    verdict*: string           ## "DISPROVED" | "NOT_DISPROVED" | "UNKNOWN" ("" = null)

# ---------------------------------------------------------------------------
# Record-layer assessment (pure — {A, C} axis only)
# ---------------------------------------------------------------------------

func groundsRefEntries*(grounds: JsonNode): seq[string] =
  ## "ref#recordDigest" entries — each requirement source reference joined
  ## with the record's self-describing digest.
  let digest = grounds{"recordDigest"}.getStr("")
  let refs = grounds{"requirementSourceRefs"}
  result = @[]
  if not refs.isNil and refs.kind == JArray:
    for r in refs:
      if r.kind == JString and r.getStr("").len > 0:
        result.add(r.getStr() & "#" & digest)

func propositionVerdictOf*(claimOutcome: string; machineVerdict: string;
    quartetComplete: bool): string {.raises: [].} =
  ## The display-layer proposition verdict — the §2.2 conjunction observed at
  ## its operational points, projected CONSERVATIVELY (fail-closed):
  ## DISPROVED ⟺ machineVerdict == "FAIL" (the machine tuple's run verdict
  ## spelling, $vrFail — run_accounting.nim) ∧ claimOutcome == "clDisproved"
  ## ∧ quartetComplete (the ce-replay counterexample quartet lines — the
  ## structured icCounterexample record). Every other combination yields
  ## UNKNOWN — never a positive state.
  ##
  ## NOT_DISPROVED is UNREACHABLE here (fail-closed): §2.1's vdVerified
  ## conjunct is never serialized into wave/runResult/unitEvidence, so the
  ## display layer can never observe it — a bare clProved (with or without
  ## the machine half) must not project a positive proposition state. Every
  ## non-conjunction input — the §2.3 remaining states, an absent outcome,
  ## and any unrecognized spelling — degrades to UNKNOWN. The serialization
  ## gap is a follow-up; until it closes, NOT_DISPROVED stays an
  ## unobservable state (glossary §2.2 note). rowStatus is NEVER a fallback
  ## for any conjunct (§2.4d RULE-axis premise only — the equivalence does
  ## not hold in either direction).
  if machineVerdict == "FAIL" and claimOutcome == "clDisproved" and
      quartetComplete:
    propositionDisprovedSpelling
  else:
    propositionUnknownSpelling

func assessGrounds*(grounds: JsonNode; spec: JsonNode): GroundsAssessment =
  ## Assess one grounds record against its cited spec overlay, purely.
  ## Fail closed: any record-layer rejection yields an all-false assessment
  ## with the validator's reason ("grounds: unverified") — no axis is salvaged
  ## from a rejected record.
  let checked = validateGroundsFile(grounds, spec)
  if checked.isErr:
    return GroundsAssessment(
      validationReason: "grounds: unverified — " & checked.error)
  let view = checked.get()
  var claimed = 0        # categories claiming present (incl. voided ones)
  var effective = 0      # present AND not voided
  var e1Present = false
  var e1Effective = false
  var e2e3Present = false
  var quartetComplete = true
  var reason = ""
  let groundsMap = grounds{"confirmation"}{"grounds"}
  for cat in groundsCategories:
    let ground = groundsMap{cat}
    let present = ground{"present"}
    if ground.isNil or present.kind != JBool or not present.getBool():
      continue
    inc claimed
    case cat
    of "E1":
      e1Present = true
    of "E2", "E3":
      e2e3Present = true
    else:
      discard
    if cat == "E1" and view.requirementSourceStatus == "recordedDisclaiming":
      # Glossary §2.4a: the ground ① is a promise VIOLATION, never a
      # "conflict" — a disclaiming requirement source can never supply E1.
      reason = "groundsValidation: E1 recorded against a disclaiming " &
        "requirement source — a disclaimer is never a promise violation " &
        "(glossary §2.4a); conflict reading rejected"
      continue
    inc effective
    if cat == "E1":
      e1Effective = true
    let repro = ground{"reproduction"}
    if repro.isNil or repro.kind != JObject or repro.len == 0:
      quartetComplete = false
  let cValid = effective > 0 and quartetComplete
  GroundsAssessment(
    aValid: true,
      # validated record: the T2 validator mechanically enforces the shared
      # quartet (exact commit / exact input / violation statement / replay
      # observation with an external source) over the closed schema — A's
      # essentials hold by construction, and A never reads M here.
    cValid: cValid,
    cClaimed: claimed > 0,
    cQuartetComplete: quartetComplete,
    dualUse: cValid,
      # The C-carried quartet IS the shared quartet (glossary §2.2 single
      # definition): a quartet-complete C dual-satisfies A's elements. The
      # explicit marking is this field — dual ⇒ C exists.
    e1Present: e1Present,
    e1Effective: e1Effective,
    e2e3Present: e2e3Present,
    requirementSourceStatus: view.requirementSourceStatus,
    validationReason: reason)

func unrecordedOwnership*(): JsonNode =
  ## The constant unrecorded-ownership marker (parse-failure fallback).
  %*{"owner": unrecordedOwnerSpelling}

func displaySubjectNode*(overlay: JsonNode): JsonNode {.raises: [].} =
  ## `subject ?: adoption.subject` — the overlay's subject-pin node wherever
  ## the document keeps it. Plain overlays pin a `subject` object; adoption
  ## records (sidecar) pin under `adoption.subject` with a singular symbol.
  ## nil = the document names no subject node — probe fail-closed / display
  ## block absence is the correct posture for pin-less overlays (never
  ## fabricated).
  let subject = overlay{"subject"}
  if not subject.isNil and subject.kind == JObject:
    return subject
  let adopted = overlay{"adoption"}{"subject"}
  if not adopted.isNil and adopted.kind == JObject:
    return adopted
  nil

func classifySubjectScope*(pinnedCommit, pinnedBlob: string;
    probe: BugVerdictSubjectIdentity): string {.raises: [].} =
  ## Glossary §2.4d scope table (pure). verifiedMatch requires the exact
  ## commit AND blob; any unmet binding is NOT Unknown — the display block is
  ## simply absent (not-applicable for this run's subject).
  if not probe.probeOk:
    return scopeCommitUnverifiable
  if probe.commit != pinnedCommit:
    return scopeCommitMismatch
  if probe.blob != pinnedBlob:
    return if probe.blob.len == 0: scopeCommitUnverifiable else: scopeBlobMismatch
  scopeVerifiedMatch

func machineUncertaintyPresent*(machineStates: seq[string]): bool =
  ## A machine-uncertainty state among the co-displayed spellings (§2.4c).
  for s in machineStates:
    if s in machineUncertaintySpellings:
      return true
  false

func machineStatesOf*(machineTuple: JsonNode): seq[string] =
  ## $-rendered spellings actually consumed — the string members of the
  ## machine tuple, insertion order. Non-string members (the records-complete
  ## flag) are not enum spellings and never co-display.
  result = @[]
  if machineTuple.isNil or machineTuple.kind != JObject:
    return
  for _, v in pairs(machineTuple):
    if v.kind == JString and v.getStr("").len > 0:
      result.add(v.getStr())

# ---------------------------------------------------------------------------
# The pure 2-axis projection
# ---------------------------------------------------------------------------

func displayBugVerdict*(input: BugVerdictDisplayInput): BugVerdictDisplay {.raises: [].} =
  ## The total 2-axis projection for ONE unit (glossary §2.4/§2.4a–§2.4c —
  ## exact priority ordering, fail-closed degradations, and the §2.4c kinds
  ## table), v3: confirmation is E1-only against a recorded-binding source.
  var reasons: seq[string] = @[]

  # ── ownership gate (fail-closed) ──
  # The additive claimOwnership block must validate (closed owner set,
  # contract-path agreement, non-empty adoptionRef). Missing/typo'd/invalid
  # ⇒ "ownership: unrecorded": no canonical names, attribution degrades to
  # Unknown (the display never attributes a bug to an unowned claim).
  var ownershipValid = false
  var owner = ""
  if not input.ownership.isNil and input.ownership.kind == JObject:
    var wrapper = newJObject()
    wrapper["claimOwnership"] = input.ownership
    let checked = validateClaimOwnership(wrapper)
    if checked.isOk:
      ownershipValid = true
      owner = checked.get
  if not ownershipValid:
    reasons.add("ownership: unrecorded")

  # ── proposition + source status (display layer) ──
  # machineVerdict is the machine tuple's run verdict spelling ($vr* — the
  # §2.2 vrFail observation point); quartetComplete rides the input's
  # observed ce-replay quartet record.
  let machineVerdict =
    if input.machineTuple.isNil: ""
    else: input.machineTuple{"verdict"}.getStr("")
  let propositionVerdict = propositionVerdictOf(input.claimOutcome,
    machineVerdict, input.quartetComplete)
  let sourceStatus =
    if input.assessment.requirementSourceStatus.len > 0:
      input.assessment.requirementSourceStatus
    else:
      requirementSourceUnknownSpelling

  # ── fail-visible surfaces (never verdict inputs beyond what they void) ──
  # A claimed confirmation without the C-carried quartet (5-∂) never
  # confirms — fail visible. A rejected record's reason rides through. E2/E3
  # presence is report-worthiness evidence for the reporter — it NEVER feeds
  # the confirmation branch.
  if input.assessment.cClaimed and not input.assessment.cQuartetComplete:
    reasons.add("groundsValidation: confirmation claimed without the " &
      "C-carried quartet (glossary §2.4a) — grounds: unverified")
  if input.assessment.validationReason.len > 0:
    reasons.add(input.assessment.validationReason)
  if input.assessment.e2e3Present:
    reasons.add("E2/E3 present: impact/corroboration evidence (not confirmation)")

  # ── attribution — priority ordering verbatim ──
  # BUG_FOUND ⟺ DISPROVED ∧ recordedBinding ∧ E1 present-and-effective
  # (non-empty refs + the C-carried reproduction quartet — the validator
  # enforces both on a validated record) ∧ the quartet complete. DISPROVED
  # here is the §2.2 conjunction observed via propositionVerdictOf (run
  # verdict FAIL ∧ clDisproved ∧ quartet record complete). E2/E3 can
  # never produce BUG_FOUND, even present-and-complete. E1 against a
  # disclaiming source is already voided at the record layer, and E1 with a
  # non-binding/undetermined status cannot confirm (no recorded binding).
  # BUG_SUSPECTED ⟺ DISPROVED ∧ A essentials valid (a VALIDATED record) ∧
  # the source status is non-binding/undetermined. UNKNOWN otherwise
  # (NOT_DISPROVED / UNKNOWN proposition, unvalidated or absent grounds, a
  # binding source without E1, ownership-gate failure).
  let e1ConfirmationReady = input.assessment.e1Present and
    input.assessment.e1Effective and input.assessment.cQuartetComplete
  var attribution =
    if propositionVerdict == propositionDisprovedSpelling and
        sourceStatus == "recordedBinding" and e1ConfirmationReady:
      bugConfirmedLabel
    elif propositionVerdict == propositionDisprovedSpelling and
        input.assessment.aValid and sourceStatus in suspectEligibleStatuses:
      bugSuspectedLabel
    else:
      attributionUnknownLabel
  if propositionVerdict == propositionDisprovedSpelling and
      attribution == attributionUnknownLabel and ownershipValid and
      input.assessment.aValid:
    # Fail-visible: a disproof with a validated record that settles neither
    # way (a binding source without effective E1, or a status outside the
    # suspect-eligible set) stays Unknown — never silently dropped.
    reasons.add("groundsValidation: DISPROVED without a BUG_FOUND E1 basis " &
      "and without a suspect-eligible requirement source status")
  if not ownershipValid:
    attribution = attributionUnknownLabel

  # ── uncertainty kinds (display layer only — glossary §2.4c) ──
  # Derivable ONLY while Suspected. Suspected requires a non-binding or
  # undetermined source, so upstream-spec always derives; verification-proof
  # derives from a machine-uncertainty state among the co-displayed
  # spellings. Machine states never yield upstream-spec and record fields
  # never yield verification-proof beyond this rule (교차 유도 금지). The
  # flags may co-occur.
  let machineStates = machineStatesOf(input.machineTuple)
  var kinds: seq[string] = @[]
  if attribution == bugSuspectedLabel:
    if sourceStatus != "recordedBinding":
      kinds.add(upstreamSpecKind)
    if machineUncertaintyPresent(machineStates):
      kinds.add(verificationProofKind)
    # Fixed order + closed kind set — any unknown kind literal is rejected.
    var ordered: seq[string] = @[]
    for kind in [upstreamSpecKind, verificationProofKind]:
      if kind in kinds:
        ordered.add(kind)
    if ordered.len == 0:
      # The §2.4c table is total over the closed status set, so a Suspected
      # with zero kinds means the status sits outside the closed set — the
      # A record cannot be trusted. Fail closed to Unknown.
      attribution = attributionUnknownLabel
      reasons.add("groundsValidation: suspected without an uncertainty " &
        "kind — requirementSourceStatus outside the closed set")
    else:
      kinds = ordered
  else:
    kinds = @[]  # BUG_FOUND / Unknown ⇒ kinds empty

  # ── RULE axis (precision rule — glossary §2.4) ──
  # The canonical name needs the machine half AND axiom-defined-rule
  # ownership, both fail-closed. A software-requirement-owned rule gets a
  # non-canonical descriptive line with the ruleId — never the canonical
  # name. Machine-half absent ⇒ no canonical names at all.
  var rule = ""
  if input.machineEstablished:
    if ownershipValid and owner == "axiom-defined-rule":
      rule = ruleViolatedLabel
    elif ownershipValid and owner == "software-requirement":
      rule = "rule linked to software requirement (" & input.ruleId &
        ") — no canonical Axiom-defined rule name"

  # ── grounds surface ──
  if input.groundsRawDigest.len == 0 or input.groundsRawDigest == "absent":
    reasons.add("grounds: absent")

  # ── provenance digest over the consumed inputs (deterministic) ──
  # §2.4d: ONE normalized JObject hashed via canonicalJson + canonicalSha256 —
  # keys sorted at every level (JCS-equivalent determinism) — binding ALL
  # decision inputs: machine tuple, ownership, grounds, the §2.4d scope row,
  # the unit's claim verdict and quartet payload digest, the subject probe
  # identity, the adoptedSpecRef (specId + specRelPath — the unit↔overlay
  # link's tamper-evidence), the emitted requirement source status, and the
  # projection schema version.
  let groundsComponent =
    if input.groundsRawDigest.len > 0: input.groundsRawDigest else: "absent"
  let digestInput = %*{
    "schemaVersion": bugVerdictDisplaySchemaVersion,
    "machineTuple": input.machineTuple,
    "ownership": input.ownership,
    "grounds": groundsComponent,
    "groundsRefs": input.groundsRefs,
    "targetSymbol": input.targetSymbol,
    "rowStatus": input.rowStatus,
    "scopeStatus": input.scopeStatus,
    "claimOutcome": input.claimOutcome,
    "quartetPayloadDigest": input.quartetPayloadDigest,
    "subjectCommit": input.subjectCommit,
    "subjectBlob": input.subjectBlob,
    "specId": input.specId,
    "specRelPath": input.specRelPath,
    "requirementSourceStatus": sourceStatus}
  let digest = canonicalSha256(digestInput)

  BugVerdictDisplay(
    targetSymbol: input.targetSymbol,
    adoptedSpecId: input.specId,
    adoptedSpecRelPath: input.specRelPath,
    ruleJudgment: rule,
    bugAttribution: attribution,
    propositionVerdict: propositionVerdict,
    requirementSourceStatus: sourceStatus,
    uncertaintyKinds: kinds,
    machineStates: machineStates,
    groundsRefs: input.groundsRefs,
    groundsValidation: reasons.join("; "),
    displayInputDigest: digest)

func displayToJson*(d: BugVerdictDisplay): JsonNode =
  ## ONE unit's namespaced display block — every key is display-owned
  ## ("display" namespace), never a guarded outcome key, and no guarded
  ## vocabulary value is ever written from a literal here (glossary §1;
  ## evidence_truth_boundary gate [T4-b] — the machine spellings arrive as
  ## consumed parameters). The report assembles these under the v3
  ## `units` array via displayContainerJson.
  %*{
    "targetSymbol": d.targetSymbol,
    "adoptedSpecRef": {
      "specId": d.adoptedSpecId,
      "specRelPath": d.adoptedSpecRelPath},
    "ruleJudgment": d.ruleJudgment,
    "bugAttribution": d.bugAttribution,
    "propositionVerdict": d.propositionVerdict,
    "requirementSourceStatus": d.requirementSourceStatus,
    "uncertaintyKinds": d.uncertaintyKinds,
    "machineStates": d.machineStates,
    "groundsRefs": d.groundsRefs,
    "groundsValidation": d.groundsValidation,
    "displayInputDigest": d.displayInputDigest,
    "displayInputDigestPurpose": displayInputDigestPurpose,
  }

func propositionsToJson*(rollup: seq[PropositionRollupDisplay]): JsonNode =
  ## The display.propositions[] rollup array. `reason` is present ONLY on an
  ## INCAPABLE entry; `verdict` is JSON null exactly when `attempted` is
  ## false. Every value arrives as a parameter — the display layer projects
  ## intake/dispatch decisions, it never re-derives or fabricates one.
  result = newJArray()
  for r in rollup:
    let capability =
      if r.capabilityStatus == propositionCapabilityIncapableSpelling:
        %*{"status": r.capabilityStatus, "reason": r.capabilityReason}
      else:
        %*{"status": r.capabilityStatus}
    let verdictNode =
      if r.attempted and r.verdict.len > 0: newJString(r.verdict)
      else: newJNull()
    result.add(%*{
      "id": r.id,
      "capability": capability,
      "verification": {"attempted": r.attempted, "verdict": verdictNode}})

func displayContainerJson*(units: seq[JsonNode];
    propositions: seq[PropositionRollupDisplay] = @[]): JsonNode =
  ## The report `display` value (v3): the schema version plus the per-unit
  ## blocks, in the caller's unit order (the run's unit-evidence key order —
  ## deterministic). `propositions` rides the SAME container node (the
  ## two-axis rollup, contract §3) under its own schema-version key, and is
  ## emitted only when non-empty — a units-only container stays
  ## byte-identical to the v3 shape.
  var container = %*{
    "schemaVersion": bugVerdictDisplaySchemaVersion,
    "units": units,
  }
  if propositions.len > 0:
    container["propositionRollupSchemaVersion"] =
      %propositionRollupSchemaVersion
    container["propositions"] = propositionsToJson(propositions)
  container

{.pop.}
