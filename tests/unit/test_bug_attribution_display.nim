## test_bug_attribution_display.nim — T4 acceptance: 2축 표시 투영 (T3, v3).
##
## SSOT: docs/spec/bug_verdict_glossary.md —
##   §2.2  공용 4요소 (shared quartet, 단일 정의)
##   §2.4  RULE/귀속 축 분리 + 정밀도 규칙 (canonical name ⇔ machine half ∧
##         claimOwnership.owner == axiom-defined-rule — never vrFail alone)
##   §2.4a Bug attribution — 귀속은 표시-층 순수 함수; 확정(E1-only)은
##         recordedBinding 요구 소스 + E1 present-and-effective (non-empty
##         refs + C-carried reproduction quartet)에서만; E2/E3는 결코
##         BUG_FOUND를 내지 않는다 (report-worthiness 표면으로만 발광)
##   §2.4b 전함수 우선순위 — BUG_FOUND > BUG_SUSPECTED > Unknown (상호 배타적
##         · 전체)
##   §2.4c kinds 유도 표 — Suspected 전용 (비결속/미확정 소스 → upstream-spec;
##         기계 불확실성 → verification-proof), 교차 유도 금지
##   §2.4d 스코프·표시 결속 규칙 — 유닛-스코프 전제 + 주체 커밋·blob 스코프 표;
##         블록 부재는 Unknown이 아니라 not-applicable이다
##
## v3 (bug-verdict-display-v3) measured here:
##   1. The satisfied unit-scoped machine half (§2.4d conjunction result)
##      grants the RULE label but NEVER attribution (Unknown, kinds empty).
##   2. BUG_FOUND ⟺ DISPROVED ∧ recordedBinding ∧ E1 present-and-effective
##      (present:true + non-empty refs + quartet-complete reproduction) ∧
##      quartet complete — measured over a VALIDATED synthesized record.
##      E2/E3 alone (even present-and-complete) → BUG_SUSPECTED, never
##      BUG_FOUND; recordedDisclaiming-without-A-essentials → Unknown.
##   3. BUG_SUSPECTED ⟺ DISPROVED ∧ validated record (A essentials) ∧ status
##      ∈ {recordedDisclaiming, unrecorded, unknown}.
##   4. propositionVerdict derivation (display layer, §2.2 conjunction,
##      fail-closed): DISPROVED ⟺ machineVerdict=="FAIL" (the machine
##      tuple's run verdict $-spelling — the §2.2 vrFail observation point)
##      ∧ clDisproved ∧ quartetComplete (the ce-replay counterexample
##      quartet lines); every other combination → UNKNOWN. NOT_DISPROVED is
##      UNREACHABLE — §2.1's vdVerified conjunct is never serialized into
##      wave/runResult/unitEvidence, so a bare clProved can never project a
##      positive proposition state (fail-closed UNKNOWN).
##   5. Per-unit schema: the report display block is the v3 container
##      (schemaVersion + units array), rendered one line per unit; the unit
##      block binds targetSymbol + adoptedSpecRef{specId, specRelPath}.
##   6. displayInputDigest: every perturbed slot moves the digest — including
##      the adoptedSpecRef.specRelPath link and the emitted requirement
##      source status (tamper-evidence for the unit↔overlay link).
##   Golden: the REAL data/bug_attribution/SPEC-B36-COUT.json + its overlay →
##   rule "Axiom-Defined Rule Violated", attribution "BUG_SUSPECTED", kinds
##   ["upstream-spec"] (recordedDisclaiming); the REAL
##   data/bug_attribution/SPEC-LIBP2P-BV-SLICE.json + its overlay → the live
##   bytesview entry projection (unrecorded → BUG_SUSPECTED / DISPROVED /
##   adoptedSpecRef binding).
import std/[json, options, os, sequtils, strutils, unittest]

import ../../src/core/results
import ../../src/core/utils/repo_root
import ../../src/core/trusted/bug_attribution_grounds
import ../../src/cli/verdict_display
import ../../src/cli/wf_render

proc committedSpec(name: string): JsonNode =
  parseJson(readFile(repoRootConst() / "config" / "spec" / name))

proc committedGrounds(): JsonNode =
  parseJson(readFile(repoRootConst() / "data" / "bug_attribution" /
    "SPEC-B36-COUT.json"))

proc committedBvGrounds(): JsonNode =
  parseJson(readFile(repoRootConst() / "data" / "bug_attribution" /
    "SPEC-LIBP2P-BV-SLICE.json"))

proc redigest(node: JsonNode): JsonNode =
  node["recordDigest"] = %computeRecordDigest(node)
  node

let
  axiomOwnership = parseJson(
    """{"owner":"axiom-defined-rule","contract":"docs/spec/x_contract.md","adoptionRef":"docs/evidence/x.md"}""")
  softwareOwnership = parseJson(
    """{"owner":"software-requirement","contract":"docs/spec/x_contract.md","adoptionRef":"docs/evidence/x.md"}""")
  noOwnership = parseJson("""{"owner":"unrecorded"}""")

proc mkInput(
  aValid: bool = false;
  cValid: bool = false;
  cClaimed: bool = false;
  cQuartetComplete: bool = false;
  dualUse: bool = false;
  e1Present: bool = false;
  e1Effective: bool = false;
  e2e3Present: bool = false;
  status: string = "";
  ownership: JsonNode = axiomOwnership;
  machineEstablished: bool = false;
  machineVerdict: string = "FAIL";
  quartetComplete: bool = false;
  machineStates: seq[string] = @[];
  groundsRawDigest: string = "absent";
  validationReason: string = "";
  claimOutcome: string = "";
  targetSymbol: string = "";
  specId: string = "";
  specRelPath: string = ""
): BugVerdictDisplayInput =
  # machineVerdict = the machine tuple's run verdict $-spelling — the §2.2
  # vrFail observation point ("FAIL", run_accounting.nim); quartetComplete =
  # the unit's observed ce-replay quartet record (the structured
  # icCounterexample conjunct). Both feed propositionVerdictOf.
  let machineTuple = %*{"verdict": machineVerdict, "recordComplete": true}
  for i in 0 ..< machineStates.len:
    machineTuple["m" & $i] = %machineStates[i]
  BugVerdictDisplayInput(
    machineEstablished: machineEstablished,
    machineTuple: machineTuple,
    ruleId: "external:stew/base36/out-sizing-cout",
    ownership: ownership,
    groundsRefs: @[],
    groundsRawDigest: groundsRawDigest,
    assessment: GroundsAssessment(
      aValid: aValid,
      cValid: cValid,
      cClaimed: cClaimed,
      cQuartetComplete: cQuartetComplete,
      dualUse: dualUse,
      e1Present: e1Present,
      e1Effective: e1Effective,
      e2e3Present: e2e3Present,
      requirementSourceStatus: status,
      validationReason: validationReason),
    claimOutcome: claimOutcome,
    quartetComplete: quartetComplete,
    targetSymbol: targetSymbol,
    specId: specId,
    specRelPath: specRelPath)

proc displayOf(input: BugVerdictDisplayInput): BugVerdictDisplay =
  displayBugVerdict(input)

# ---------------------------------------------------------------------------
# Suite 1 — unit-scoped machine half (§2.4d conjunction result): the machine
# half never grants attribution. The RULE label's premise is the §2.4d
# unit-scoped conjunction (selected row == the overlay's module::symbol ∧
# failed ∧ that unit's clDisproved ∧ that unit's quartet ∧ ownership ∧
# subject commit/blob match) — the display builder computes it display-side
# and hands the result in as `machineEstablished`; a run-scoped FAIL with
# complete records alone codifies nothing here.
# ---------------------------------------------------------------------------

suite "unit-scoped machine half (§2.4d) — never grants attribution alone":

  test "machine-half conjunction satisfied → canonical RULE label, attribution Unknown, kinds empty":
    let d = displayOf(mkInput(machineEstablished = true))
    check d.ruleJudgment == "Axiom-Defined Rule Violated"
    check d.bugAttribution == "Unknown"
    # absent claimOutcome → UNKNOWN (§2.3 fail-closed — never NOT_DISPROVED)
    check d.propositionVerdict == "UNKNOWN"
    check d.requirementSourceStatus == "unknown"
    check d.uncertaintyKinds.len == 0
    check d.groundsValidation.contains("grounds: absent")

  test "machine-half conjunction satisfied with a machine-uncertainty state still grants NO attribution":
    let d = displayOf(mkInput(machineEstablished = true,
      machineStates = @["clUnknown"]))
    check d.ruleJudgment == "Axiom-Defined Rule Violated"
    check d.bugAttribution == "Unknown"
    check d.uncertaintyKinds.len == 0

# ---------------------------------------------------------------------------
# Suite 2 — M ∧ A ∧ C-unproven (validated record, non-binding source) —
# BUG_SUSPECTED
# ---------------------------------------------------------------------------

suite "M ∧ A ∧ C-unproven — BUG_SUSPECTED":

  test "Suspected with at least one uncertainty kind":
    let d = displayOf(mkInput(aValid = true, status = "recordedDisclaiming",
      claimOutcome = "clDisproved", machineEstablished = true,
      quartetComplete = true, groundsRawDigest = "ab" & repeat("cd", 31)))
    check d.ruleJudgment == "Axiom-Defined Rule Violated"
    check d.bugAttribution == "BUG_SUSPECTED"
    check d.propositionVerdict == "DISPROVED"
    check d.requirementSourceStatus == "recordedDisclaiming"
    check d.uncertaintyKinds.len >= 1
    check d.uncertaintyKinds == @["upstream-spec"]

# ---------------------------------------------------------------------------
# Suite 3 — the E1-only confirmation truth table (v3 formula)
# ---------------------------------------------------------------------------

suite "E1-only confirmation — BUG_FOUND > BUG_SUSPECTED > Unknown":

  test "BUG_FOUND — validated record: recordedBinding + E1 present-and-effective + quartet":
    let spec = committedSpec("nim_stew_base36_cout_spec.json")
    var grounds = committedGrounds()
    # Synthesized BINDING requirement source + a present-and-complete E1
    # ground (the validator mechanically enforces refs + reproduction) — the
    # only shape that can confirm under the v3 formula.
    grounds["requirementSourceStatus"] = %"recordedBinding"
    grounds["requirementSourceRefs"] = %[
      "docs/spec/nim_stew_base36_cout_contract.md §3 — synthesized recorded " &
      "binding for the BUG_FOUND path (test only)"]
    grounds["confirmation"]["grounds"]["E1"] = %*{
      "present": true,
      "refs": ["docs/evidence/synthesized_binding_record.md"],
      "reproduction": grounds["anomaly"]["observationQuartet"]["reproduction"]}
    grounds = redigest(grounds)
    let assessment = assessGrounds(grounds, spec)
    check assessment.aValid
    check assessment.requirementSourceStatus == "recordedBinding"
    check assessment.e1Present
    check assessment.e1Effective          # not the disclaiming-voided shape
    check assessment.cQuartetComplete
    let d = displayOf(mkInput(aValid = true, cValid = assessment.cValid,
      cClaimed = assessment.cClaimed, cQuartetComplete = assessment.cQuartetComplete,
      dualUse = assessment.dualUse, e1Present = assessment.e1Present,
      e1Effective = assessment.e1Effective,
      status = assessment.requirementSourceStatus,
      claimOutcome = "clDisproved", machineEstablished = true,
      quartetComplete = true, groundsRawDigest = repeat("ab", 32)))
    check d.bugAttribution == "BUG_FOUND"
    check d.propositionVerdict == "DISPROVED"
    check d.requirementSourceStatus == "recordedBinding"
    check d.uncertaintyKinds.len == 0
    check d.ruleJudgment == "Axiom-Defined Rule Violated"

  test "BUG_FOUND is impossible without DISPROVED (M-free formula still needs the unit's disproved claim)":
    let d = displayOf(mkInput(aValid = true, e1Present = true,
      e1Effective = true, cClaimed = true, cQuartetComplete = true,
      status = "recordedBinding", machineEstablished = true,
      groundsRawDigest = repeat("ab", 32)))
    check d.bugAttribution == "Unknown"

  test "E2/E3 alone (present-and-complete) NEVER confirms — report-worthiness surface only":
    for status in ["recordedBinding", "recordedDisclaiming", "unrecorded"]:
      let d = displayOf(mkInput(aValid = true, cValid = true, cClaimed = true,
        cQuartetComplete = true, dualUse = true, e2e3Present = true,
        status = status, claimOutcome = "clDisproved",
        machineEstablished = true, quartetComplete = true,
        groundsRawDigest = repeat("ab", 32)))
      check d.bugAttribution != "BUG_FOUND"
      check d.groundsValidation.contains(
        "E2/E3 present: impact/corroboration evidence (not confirmation)")
    # recordedDisclaiming is suspect-eligible → BUG_SUSPECTED with the surface
    let suspected = displayOf(mkInput(aValid = true, cValid = true,
      cClaimed = true, cQuartetComplete = true, dualUse = true,
      e2e3Present = true, status = "recordedDisclaiming",
      claimOutcome = "clDisproved", machineEstablished = true,
      quartetComplete = true, groundsRawDigest = repeat("ab", 32)))
    check suspected.bugAttribution == "BUG_SUSPECTED"
    # a binding source without E1 confirms neither way → Unknown, fail-visible
    let binding = displayOf(mkInput(aValid = true, cValid = true,
      cClaimed = true, cQuartetComplete = true, dualUse = true,
      e2e3Present = true, status = "recordedBinding",
      claimOutcome = "clDisproved", machineEstablished = true,
      quartetComplete = true, groundsRawDigest = repeat("ab", 32)))
    check binding.bugAttribution == "Unknown"
    check binding.groundsValidation.contains(
      "DISPROVED without a BUG_FOUND E1 basis")

  test "recordedDisclaiming without the A-essentials (invalid/absent record) → Unknown":
    let d = displayOf(mkInput(aValid = false, status = "recordedDisclaiming",
      claimOutcome = "clDisproved", machineEstablished = true,
      validationReason = "grounds: unverified — recordDigest mismatch"))
    check d.bugAttribution == "Unknown"
    check d.groundsValidation.contains("grounds: unverified")

  test "E1 against unrecorded/unknown status cannot confirm (no recorded binding)":
    for status in ["unrecorded", "unknown"]:
      let d = displayOf(mkInput(aValid = true, e1Present = true,
        e1Effective = true, cClaimed = true, cQuartetComplete = true,
        status = status, claimOutcome = "clDisproved",
        quartetComplete = true, groundsRawDigest = repeat("ab", 32)))
      check d.bugAttribution == "BUG_SUSPECTED"

  test "priority — exactly one label, every valid combo":
    # All valid combos over the closed status set. The machine observation
    # (§2.2 conjunction inputs) gates BOTH axes: `machine` now drives
    # quartetComplete (the proposition's structured-record conjunct — the
    # machineVerdict is FAIL throughout) AND machineEstablished (the RULE
    # axis premise). E1 present+effective+complete rides together (a
    # validated record's E1 is complete by construction).
    let labels = ["BUG_FOUND", "BUG_SUSPECTED", "Unknown"]
    for disproved in [false, true]:
      for status in ["recordedBinding", "recordedDisclaiming", "unrecorded",
                     "unknown"]:
        for aValid in [false, true]:
          for e1 in [false, true]:
            for machine in [false, true]:
              let d = displayOf(mkInput(aValid = aValid,
                cClaimed = e1, cQuartetComplete = e1,
                e1Present = e1, e1Effective = e1,
                status = status, machineEstablished = machine,
                quartetComplete = machine,
                claimOutcome = (if disproved: "clDisproved" else: "")))
              # exactly one label — the label set is closed and total
              check d.bugAttribution in labels
              # the priority, verbatim (v3 formula over the §2.2
              # proposition): the proposition is DISPROVED only under the
              # FULL conjunction (clDisproved ∧ machineVerdict "FAIL" ∧
              # quartet record complete). With machine=false the conjunction
              # is unmet → proposition UNKNOWN → BUG_FOUND / BUG_SUSPECTED
              # can never fire. This TIGHTENS the machine=false ∧
              # recordedBinding ∧ e1 row's expectation from BUG_FOUND to
              # Unknown — an expectation STRICTENING (엄격화), not a
              # downgrade: glossary §2.2 requires the observed disproof
              # record, not the claim spelling alone.
              let proposition =
                if disproved and machine: "DISPROVED"
                else: "UNKNOWN"
              let expected =
                if proposition == "DISPROVED" and
                    status == "recordedBinding" and e1:
                  "BUG_FOUND"
                elif proposition == "DISPROVED" and aValid and
                    status in suspectEligibleStatuses:
                  "BUG_SUSPECTED"
                else:
                  "Unknown"
              check d.bugAttribution == expected
              # kinds invariants per label (§2.4c)
              case d.bugAttribution
              of "BUG_FOUND", "Unknown":
                check d.uncertaintyKinds.len == 0
              else:
                check d.uncertaintyKinds.len >= 1
                check d.uncertaintyKinds == @["upstream-spec"]

  test "propositionVerdictOf — the §2.2 conjunction, fail-closed (vdVerified never serialized)":
    # DISPROVED ⟺ machineVerdict=="FAIL" (the machine tuple's run verdict
    # $-spelling — the §2.2 observation point) ∧ claimOutcome=="clDisproved"
    # ∧ quartetComplete (the ce-replay counterexample quartet lines)
    check propositionVerdictOf("clDisproved", "FAIL", true) == "DISPROVED"
    # NOT_DISPROVED is unreachable in the display layer: §2.1's vdVerified
    # conjunct is never serialized into wave/runResult/unitEvidence, so
    # clProved can never project a positive proposition state — with the
    # machine half (even PASS) or bare it stays fail-closed UNKNOWN until
    # the serialization gap closes (glossary §2.2 note; follow-up)
    check propositionVerdictOf("clProved", "PASS", true) == "UNKNOWN"
    check propositionVerdictOf("clProved", "FAIL", true) == "UNKNOWN"
    # quartet missing → the structured icCounterexample record is absent →
    # UNKNOWN even with vrFail ∧ clDisproved
    check propositionVerdictOf("clDisproved", "FAIL", false) == "UNKNOWN"
    # machine verdict inconclusive or absent → UNKNOWN
    check propositionVerdictOf("clDisproved", "INCONCLUSIVE", true) == "UNKNOWN"
    check propositionVerdictOf("clDisproved", "", true) == "UNKNOWN"
    # absent/unrecognized claim outcomes never project a positive state
    check propositionVerdictOf("", "FAIL", true) == "UNKNOWN"
    for claim in ["clUnknown", "clUnsupported", "clNoSpecification",
                  "clInvalidEvidence", "clDependencyBlocked",
                  "clTotallyUnrecognized", "DISPROVED", "clDisproveD"]:
      check propositionVerdictOf(claim, "FAIL", true) == "UNKNOWN"
    let unknownD = displayOf(mkInput(aValid = true,
      status = "recordedDisclaiming", claimOutcome = "clUnknown",
      machineEstablished = true, quartetComplete = true))
    check unknownD.propositionVerdict == "UNKNOWN"
    check unknownD.bugAttribution == "Unknown"

  test "degrade — a status outside the closed set never suspects":
    let d = displayOf(mkInput(aValid = true, status = "someUnknownStatus",
      claimOutcome = "clDisproved"))
    check d.bugAttribution == "Unknown"
    check d.uncertaintyKinds.len == 0

# ---------------------------------------------------------------------------
# Suite 4 — §2.4c kinds decision table (Suspected-only) + 교차 유도 금지
# ---------------------------------------------------------------------------

suite "§2.4c kinds — Suspected-only derivation + 교차 유도 금지":

  test "recordedDisclaiming → [upstream-spec]":
    let d = displayOf(mkInput(aValid = true, status = "recordedDisclaiming",
      claimOutcome = "clDisproved", quartetComplete = true))
    check d.bugAttribution == "BUG_SUSPECTED"
    check d.uncertaintyKinds == @["upstream-spec"]

  test "unrecorded → [upstream-spec]":
    let d = displayOf(mkInput(aValid = true, status = "unrecorded",
      claimOutcome = "clDisproved", quartetComplete = true))
    check d.uncertaintyKinds == @["upstream-spec"]

  test "unknown (4th closed-set value) → [upstream-spec]":
    let d = displayOf(mkInput(aValid = true, status = "unknown",
      claimOutcome = "clDisproved", quartetComplete = true))
    check d.bugAttribution == "BUG_SUSPECTED"
    check d.uncertaintyKinds == @["upstream-spec"]

  test "a record-less assessment emits the 4th status (source determination incomplete)":
    let d = displayOf(mkInput(aValid = true, status = "",
      claimOutcome = "clDisproved", quartetComplete = true))
    check d.requirementSourceStatus == "unknown"
    check d.uncertaintyKinds == @["upstream-spec"]

  test "co-occurrence — non-binding source ∧ machine uncertainty → both kinds, fixed order":
    let d = displayOf(mkInput(aValid = true, status = "unrecorded",
      claimOutcome = "clDisproved", quartetComplete = true,
      machineStates = @["cvUnresolved"]))
    check d.uncertaintyKinds == @["upstream-spec", "verification-proof"]

  test "cross-derivation ban — machine states never yield upstream-spec":
    # even with machine uncertainty present, upstream-spec derives ONLY from
    # the non-binding source status; and machine uncertainty alone can never
    # suspect (the proposition still gates). `clNoSpecification` (an
    # absent-evidence spelling) is NOT machine uncertainty — the
    # verification-proof kind never derives from it.
    let d = displayOf(mkInput(aValid = true, status = "unrecorded",
      claimOutcome = "clDisproved", quartetComplete = true,
      machineStates = @["cvUnresolved"]))
    check d.uncertaintyKinds == @["upstream-spec", "verification-proof"]
    let dNoMachine = displayOf(mkInput(aValid = true, status = "unrecorded",
      claimOutcome = "clDisproved", quartetComplete = true,
      machineStates = @["clNoSpecification"]))
    check dNoMachine.uncertaintyKinds == @["upstream-spec"]
    let d2 = displayOf(mkInput(aValid = true, status = "",
      machineStates = @["clNoSpecification"]))
    check d2.bugAttribution == "Unknown"
    check d2.uncertaintyKinds.len == 0

  test "machine-uncertainty spellings — identifier and serialized forms both count":
    for spelling in ["clUnknown", "vrInconclusive", "vsInconclusive",
                     "cvUnresolved", "INCONCLUSIVE"]:
      let d = displayOf(mkInput(aValid = true, status = "unrecorded",
        claimOutcome = "clDisproved", quartetComplete = true,
        machineStates = @[spelling]))
      check d.uncertaintyKinds == @["upstream-spec", "verification-proof"]

# ---------------------------------------------------------------------------
# Suite 5 — Confirmed impossible without the E1 basis (record layer)
# ---------------------------------------------------------------------------

suite "E1 basis — record-layer rejections keep the v3 formula honest":

  test "M-replay-only (corroboration) never counts as E1 — the real record stays Suspected":
    let spec = committedSpec("nim_stew_base36_cout_spec.json")
    let grounds = committedGrounds()
    let assessment = assessGrounds(grounds, spec)
    check assessment.aValid
    check not assessment.cClaimed   # E1/E2/E3 all present:false
    check not assessment.e1Present
    check not assessment.e2e3Present
    check not assessment.cValid
    let d = displayOf(mkInput(aValid = true, status = "recordedDisclaiming",
      claimOutcome = "clDisproved", machineEstablished = true,
      quartetComplete = true, groundsRawDigest = repeat("ab", 32)))
    check d.bugAttribution != "BUG_FOUND"
    check d.bugAttribution == "BUG_SUSPECTED"

  test "maintainer-ack (E3) alone without the quartet is rejected fail-closed":
    let spec = committedSpec("nim_stew_base36_cout_spec.json")
    var grounds = committedGrounds()
    grounds["confirmation"]["grounds"]["E3"] = %*{
      "present": true,
      "refs": @["upstream maintainer acknowledgment thread"]}
    grounds = redigest(grounds)
    let assessment = assessGrounds(grounds, spec)
    check not assessment.aValid   # whole record rejected — fail closed
    check not assessment.cValid
    check assessment.validationReason.contains("grounds: unverified")
    check assessment.validationReason.contains("reproduction quartet")
    let d = displayOf(mkInput(status = "recordedDisclaiming",
      claimOutcome = "clDisproved", machineEstablished = true,
      validationReason = assessment.validationReason))
    check d.bugAttribution == "Unknown"
    check d.groundsValidation.contains("grounds: unverified")

  test "disclaimer-'conflict' reading of E1 is rejected (glossary §2.4a) — E1 voided, Suspected stands":
    let spec = committedSpec("nim_stew_base36_cout_spec.json")
    var grounds = committedGrounds()
    var e1Conflict = newJObject()
    e1Conflict["present"] = %true
    e1Conflict["refs"] = %["docstring says 'estimated' — a conflict with the expectation"]
    e1Conflict["reproduction"] =
      grounds["anomaly"]["observationQuartet"]["reproduction"]
    grounds["confirmation"]["grounds"]["E1"] = e1Conflict
    grounds = redigest(grounds)
    let assessment = assessGrounds(grounds, spec)
    check assessment.cClaimed          # E1 claimed present
    check assessment.e1Present
    check not assessment.e1Effective   # the basis is void — never E1
    check not assessment.cValid
    let d = displayOf(mkInput(aValid = true, cValid = assessment.cValid,
      cClaimed = assessment.cClaimed,
      cQuartetComplete = assessment.cQuartetComplete,
      dualUse = assessment.dualUse, e1Present = assessment.e1Present,
      e1Effective = assessment.e1Effective,
      status = "recordedDisclaiming", claimOutcome = "clDisproved",
      machineEstablished = true, quartetComplete = true,
      groundsRawDigest = repeat("ab", 32),
      validationReason = assessment.validationReason))
    check d.bugAttribution != "BUG_FOUND"
    check d.bugAttribution == "BUG_SUSPECTED"
    check d.groundsValidation.contains("conflict reading rejected")

  test "5-∂ — C-incomplete claimed confirmation keeps the fail-visible reason":
    let d = displayOf(mkInput(aValid = false, cValid = true, cClaimed = true,
      cQuartetComplete = false, status = "recordedBinding",
      claimOutcome = "clDisproved"))
    check d.bugAttribution == "Unknown"
    check d.groundsValidation.contains("C-carried quartet")
    check d.groundsValidation.contains("grounds: unverified")

# ---------------------------------------------------------------------------
# Suite 6 — ownership gate (fail-closed)
# ---------------------------------------------------------------------------

suite "ownership gate":

  test "software-requirement + M → RULE label is NOT the canonical name":
    let d = displayOf(mkInput(aValid = true, status = "recordedDisclaiming",
      claimOutcome = "clDisproved", ownership = softwareOwnership,
      machineEstablished = true))
    check d.ruleJudgment != "Axiom-Defined Rule Violated"
    check d.ruleJudgment.contains("software requirement")
    check d.ruleJudgment.contains("external:stew/base36/out-sizing-cout")

  test "missing ownership degrades even the full BUG_FOUND combo":
    let d = displayOf(mkInput(aValid = true, e1Present = true,
      e1Effective = true, cClaimed = true, cQuartetComplete = true,
      status = "recordedBinding", claimOutcome = "clDisproved",
      ownership = noOwnership, machineEstablished = true,
      groundsRawDigest = repeat("ab", 32)))
    check d.ruleJudgment == ""
    check d.bugAttribution == "Unknown"
    check d.groundsValidation.contains("ownership: unrecorded")
    check d.uncertaintyKinds.len == 0

  test "invalid ownership shape (typo'd owner) fails closed identically":
    let typo = parseJson(
      """{"owner":"axiom-defined-rules","contract":"docs/spec/x_contract.md","adoptionRef":"docs/evidence/x.md"}""")
    let d = displayOf(mkInput(aValid = true, status = "recordedDisclaiming",
      claimOutcome = "clDisproved", ownership = typo,
      machineEstablished = true))
    check d.ruleJudgment == ""
    check d.bugAttribution == "Unknown"
    check d.groundsValidation.contains("ownership: unrecorded")

  test "the registry-required provenance member no longer fails the closed key set":
    # bv/d2 overlays carry claimOwnership.provenance (the registry's
    # validateOwnershipObject requires it); the display gate accepts the
    # optional member while every OTHER extra key stays rejected.
    let withProvenance = parseJson(
      """{"owner":"axiom-defined-rule","contract":"docs/spec/x_contract.md","adoptionRef":"docs/evidence/x.md","provenance":"content authored by the investigation chain"}""")
    let d = displayOf(mkInput(aValid = true, status = "recordedDisclaiming",
      claimOutcome = "clDisproved", quartetComplete = true,
      ownership = withProvenance, machineEstablished = true))
    check d.ruleJudgment == "Axiom-Defined Rule Violated"
    check d.bugAttribution == "BUG_SUSPECTED"
    check (not d.groundsValidation.contains("ownership: unrecorded"))

# ---------------------------------------------------------------------------
# Suite 7 — displayInputDigest (provenance trace)
# ---------------------------------------------------------------------------

suite "displayInputDigest — provenance trace only":

  test "two identical runs are byte-identical (determinism)":
    let input = mkInput(aValid = true, status = "recordedDisclaiming",
      claimOutcome = "clDisproved", groundsRawDigest = repeat("ab", 32),
      specId = "SPEC-B36-COUT", specRelPath = "nim_stew_base36_cout_spec.json")
    let d1 = displayBugVerdict(input)
    let d2 = displayBugVerdict(input)
    check d1.displayInputDigest == d2.displayInputDigest
    check $displayToJson(d1) == $displayToJson(d2)
    check d1.displayInputDigest.len == 64

  test "perturbing each input slot moves the digest":
    let base = mkInput(aValid = true, status = "recordedDisclaiming",
      claimOutcome = "clDisproved", groundsRawDigest = repeat("ab", 32),
      specId = "SPEC-B36-COUT", specRelPath = "nim_stew_base36_cout_spec.json")
    let baseDigest = displayBugVerdict(base).displayInputDigest
    # machine tuple slot
    var perturbedMachine = base
    perturbedMachine.machineTuple["verdict"] = %"INCONCLUSIVE"
    check displayBugVerdict(perturbedMachine).displayInputDigest != baseDigest
    # ownership slot
    var perturbedOwnership = base
    perturbedOwnership.ownership = softwareOwnership
    check displayBugVerdict(perturbedOwnership).displayInputDigest != baseDigest
    # grounds component slot
    var perturbedGrounds = base
    perturbedGrounds.groundsRawDigest = repeat("cd", 32)
    check displayBugVerdict(perturbedGrounds).displayInputDigest != baseDigest
    # adoptedSpecRef.specRelPath slot — the unit↔overlay link's tamper-evidence
    var perturbedRelPath = base
    perturbedRelPath.specRelPath = "some_other_spec.json"
    check displayBugVerdict(perturbedRelPath).displayInputDigest != baseDigest
    # emitted requirement source status slot
    var perturbedStatus = base
    perturbedStatus.assessment.requirementSourceStatus = "unrecorded"
    check displayBugVerdict(perturbedStatus).displayInputDigest != baseDigest
    # quartet carrier slots — the §2.2 payload is bound ONLY via
    # quartetPayloadDigest (perturbed above); the derived completeness flag
    # and the verbatim lines are persistence-carrier observations, NOT
    # independent digest inputs. Measured against a FRESH base: the slot
    # perturbations above share one machineTuple JsonNode by reference, so
    # its verdict is no longer the base's — an equality pin must compare
    # against a clean build, not the contaminated original.
    let cleanBase = mkInput(aValid = true, status = "recordedDisclaiming",
      claimOutcome = "clDisproved", groundsRawDigest = repeat("ab", 32),
      specId = "SPEC-B36-COUT", specRelPath = "nim_stew_base36_cout_spec.json")
    let cleanDigest = displayBugVerdict(cleanBase).displayInputDigest
    check cleanDigest.len == 64
    var perturbedQuartetFlag = cleanBase
    perturbedQuartetFlag.quartetComplete = true
    check displayBugVerdict(perturbedQuartetFlag).displayInputDigest == cleanDigest
    var perturbedQuartetLines = cleanBase
    perturbedQuartetLines.quartetLines = @["replay.verdict=rvAgree"]
    check displayBugVerdict(perturbedQuartetLines).displayInputDigest == cleanDigest

  test "the unit block carries the v3 schema fields and the disclaimer purpose":
    let d = displayBugVerdict(mkInput(targetSymbol = "stew/base36.nim::decodedLength",
      specId = "SPEC-B36-COUT", specRelPath = "nim_stew_base36_cout_spec.json"))
    let node = displayToJson(d)
    check node{"targetSymbol"}.getStr() == "stew/base36.nim::decodedLength"
    check node{"adoptedSpecRef"}{"specId"}.getStr() == "SPEC-B36-COUT"
    check node{"adoptedSpecRef"}{"specRelPath"}.getStr() ==
      "nim_stew_base36_cout_spec.json"
    check node{"displayInputDigestPurpose"}.getStr() ==
      "provenance-trace-only — not a verdict legitimacy proof"
    # absent claimOutcome → UNKNOWN (§2.3 fail-closed)
    check node{"propositionVerdict"}.getStr() == "UNKNOWN"
    check node{"requirementSourceStatus"}.getStr() == "unknown"
    # namespaced keys only — never a guarded outcome key
    for guarded in ["verdict", "basis", "gateVerdict", "planComplete",
                    "executionComplete", "verificationComplete"]:
      check not node.hasKey(guarded)
    # findingEvidence is a state-document ROOT key (WP-B evidence carrier,
    # reporter-consumed) — never a display-unit key (LCD keys unchanged)
    check not node.hasKey("findingEvidence")

  test "the v3 container binds the schema version over the units array":
    let container = displayContainerJson(@[
      displayToJson(displayBugVerdict(mkInput())),
      displayToJson(displayBugVerdict(mkInput()))])
    check container{"schemaVersion"}.getStr() == "bug-verdict-display-v3"
    check container{"units"}.kind == JArray
    check container{"units"}.len == 2

# ---------------------------------------------------------------------------
# Golden — the live base36 reading
# ---------------------------------------------------------------------------

suite "golden — SPEC-B36-COUT live display projection":

  test "real grounds + real overlay → Rule Violated / BUG_SUSPECTED / [upstream-spec]":
    let spec = committedSpec("nim_stew_base36_cout_spec.json")
    let grounds = committedGrounds()
    let ownershipRes = validateClaimOwnership(spec)
    check ownershipRes.isOk()
    check ownershipRes.get() == "axiom-defined-rule"
    let assessment = assessGrounds(grounds, spec)
    check assessment.aValid
    check assessment.requirementSourceStatus == "recordedDisclaiming"
    # The machine tuple is ENGINE-SHAPED: "verdict" carries the RUN verdict
    # $-spelling ("FAIL" — $vrFail, the §2.2 vrFail observation point). The
    # record's machineRef.verdict is the vs* corroboration spelling, NOT the
    # run verdict — it rides as replayVerdict, never as the proposition's
    # machineVerdict input. quartetComplete=true mirrors the record's §2.2
    # shared quartet (the icCounterexample structured record).
    let machineTuple = %*{
      "verdict": "FAIL",
      "replayVerdict":
        grounds["corroboration"]["machineRef"]["replayVerdict"].getStr(),
      "recordComplete": true}
    let input = BugVerdictDisplayInput(
      machineEstablished: true,
      machineTuple: machineTuple,
      ruleId: spec{"ruleId"}.getStr(""),
      ownership: spec{"claimOwnership"}.copy(),
      groundsRefs: groundsRefEntries(grounds),
      groundsRawDigest: repeat("3a", 32),
      assessment: assessment,
      targetSymbol: "stew/base36.nim::decodedLength",
      claimOutcome: "clDisproved",
      quartetComplete: true,
      specId: "SPEC-B36-COUT",
      specRelPath: "nim_stew_base36_cout_spec.json")
    let d = displayBugVerdict(input)
    check d.ruleJudgment == "Axiom-Defined Rule Violated"
    check d.bugAttribution == "BUG_SUSPECTED"
    check d.propositionVerdict == "DISPROVED"
    check d.requirementSourceStatus == "recordedDisclaiming"
    check d.uncertaintyKinds == @["upstream-spec"]
    check d.machineStates == @["FAIL", "rvAgree"]
    check d.groundsRefs.len == 2
    for refEntry in d.groundsRefs:
      check refEntry.contains("#" &
        grounds["recordDigest"].getStr())
    check d.groundsValidation == ""
    let node = displayToJson(d)
    check node{"ruleJudgment"}.getStr() == "Axiom-Defined Rule Violated"
    check node{"bugAttribution"}.getStr() == "BUG_SUSPECTED"
    check node{"uncertaintyKinds"} == %*["upstream-spec"]
    check node{"displayInputDigest"}.getStr().len == 64

  test "renderAxReportLines projects ONE line per v3 unit (and the legacy v2 block)":
    let spec = committedSpec("nim_stew_base36_cout_spec.json")
    let grounds = committedGrounds()
    let assessment = assessGrounds(grounds, spec)
    let input = BugVerdictDisplayInput(
      machineEstablished: true,
      machineTuple: %*{"verdict": "FAIL", "recordComplete": true},
      ruleId: spec{"ruleId"}.getStr(""),
      ownership: spec{"claimOwnership"}.copy(),
      groundsRefs: groundsRefEntries(grounds),
      groundsRawDigest: repeat("3a", 32),
      assessment: assessment,
      claimOutcome: "clDisproved",
      quartetComplete: true)
    let unitBlock = displayToJson(displayBugVerdict(input))
    let reportWith = %*{
      "summary": {"totalNodes": 1},
      "display": displayContainerJson(@[unitBlock, unitBlock])}
    let reportLegacy = %*{
      "summary": {"totalNodes": 1},
      "display": unitBlock}
    let reportWithout = %*{"summary": {"totalNodes": 1}}
    let linesWith = renderAxReportLines(reportWith)
    let linesLegacy = renderAxReportLines(reportLegacy)
    let linesWithout = renderAxReportLines(reportWithout)
    let verdictLines = linesWith.filterIt(it.startsWith("bugVerdict="))
    check verdictLines.len == 2   # one line-group per unit
    for line in verdictLines:
      check line.startsWith("bugVerdict=BUG_SUSPECTED")
      check line.contains("rule=Axiom-Defined Rule Violated")
      check line.contains("upstream-spec")
    check linesLegacy.anyIt(it.startsWith("bugVerdict=BUG_SUSPECTED"))
    check not linesWithout.anyIt(it.startsWith("bugVerdict="))

# ---------------------------------------------------------------------------
# §2.4d subject-scoped projection — mixed-failure, scope table, digest
# ---------------------------------------------------------------------------
## Dual-state activation (compile-time fact, never an observed outcome — the
## §0.9 anti-theater rule): the suites below drive the subject-scoped display
## builder over the per-unit 4-arg seam (ONE registry entry → its governed
## units' v3 container). On a tree without them the block compiles out —
## the activation key is the presence of the contracted implementation, not a
## pass/fail observation, so nothing is masked. The seeded harness fixture is
## tests/specs/bug_verdict_scope_mixed_failure.json.
when declared(BugVerdictSubjectIdentity):
  import ../../src/cli/axiom_engine
  import ../../src/cli/external_subject_registry
  import ../../src/verification/accounting/run_accounting
  import ../../src/verification/obligation/verification_decision_authority

  const scopeFixturePath = currentSourcePath().parentDir().parentDir() /
    "specs" / "bug_verdict_scope_mixed_failure.json"
  const coutSpecRelPath = "nim_stew_base36_cout_spec.json"
  const bvSpecRelPath = "nim_libp2p_bytesview_slice.json"
  const bvUnitKey = "libp2p/utils/bytesview.nim::toOpenArray"

  proc scopeFixture(): JsonNode =
    parseJson(readFile(scopeFixturePath))

  proc findEntry(specRelPath: string): Option[RegistryEntry] =
    ## The live registry entry (one deterministic load — the §2.8 registry
    ## seam), resolved by the normalized document identity.
    let reg = loadExternalSubjectRegistry()
    if reg.isOk():
      for entry in reg.get().entries:
        if entry.specRelPath == specRelPath:
          return some(entry)
    none(RegistryEntry)

  proc pinnedProbe(specName: string): BugVerdictSubjectIdentity =
    ## A probe value matching the committed overlay's pinned subject — the
    ## scope classifier's verifiedMatch input (the raw `git` probe itself is
    ## measured end-to-end in the commitUnverifiable case below).
    let spec = committedSpec(specName)
    BugVerdictSubjectIdentity(
      probeOk: true,
      commit: spec{"subject"}{"commit"}.getStr(),
      blob: spec{"subject"}{"blobSha256"}.getStr())

  proc scopedRunResult(unitEvidence: JsonNode;
      statusA = ""): CanonicalRunResult =
    ## Two-candidate ENGINE-BOUNDARY harness: candidate A (the overlay's
    ## governed unit) + candidate B (an unrelated failing mutant) — the same
    ## reducer + VDA the engine drives (test_bug_verdict_projection pattern).
    ## `statusA` overrides the governed unit's observed row status (the
    ## converse case: A itself carries the counterexample → its row failed).
    let fixture = scopeFixture()
    let unitA = fixture{"candidateA"}{"unit"}.getStr()
    let unitB = fixture{"candidateB"}{"unit"}.getStr()
    let statusAEffective = if statusA.len > 0: statusA
                           else: fixture{"candidateA"}{"rowStatus"}.getStr()
    let statusB = fixture{"candidateB"}{"rowStatus"}.getStr()
    let wave = %*{"nodeReports": @[
      %*{"nodeId": unitA, "status": statusAEffective, "cacheHit": false,
         "dependencyDepth": 0},
      %*{"nodeId": unitB, "status": statusB, "cacheHit": false,
         "dependencyDepth": 0}]}
    let elig = %*{unitA: "elProofCandidate", unitB: "elProofCandidate"}
    var crr = buildCanonicalRunResult(@[wave], elig,
      @[@[unitA, unitB]])
    crr.runOutcome = evaluateRunOutcome(crr.runAccounting,
      NoObligationProvenance(universeEnumerated: true,
                             source: "canonical_ogr_eligibility"),
      false)
    crr

  suite "§2.4d mixed-failure — the governed unit's pass never yields the rule name":

    test "candidate B fails globally (vrFail) while governed candidate A verifies → NO base36 rule name":
      let fixture = scopeFixture()
      var unitEvidence = newJObject()
      if not fixture{"candidateB"}{"claim"}.isNil:
        unitEvidence[fixture{"candidateB"}{"unit"}.getStr()] = %*{
          "claimId": fixture{"candidateB"}{"claim"}{"claimId"}.getStr(),
          "claimOutcome": fixture{"candidateB"}{"claim"}{"claimOutcome"}.getStr(),
          "evidenceId": fixture{"candidateB"}{"claim"}{"evidenceId"}.getStr(),
          "obligationId": fixture{"candidateB"}{"claim"}{"obligationId"}.getStr(),
          "specificationId": fixture{"candidateB"}{"claim"}{"specificationId"}.getStr(),
          "counterExample": fixture{"candidateB"}{"counterExample"}}
      let crr = scopedRunResult(unitEvidence)
      check crr.runOutcome.verdict == vrFail
      let entryOpt = findEntry(coutSpecRelPath)
      check entryOpt.isSome
      let node = buildBugVerdictDisplayJson(crr, unitEvidence,
        pinnedProbe(coutSpecRelPath), entryOpt.get())
      check node.isNil.not
      check node{"schemaVersion"}.getStr() == "bug-verdict-display-v3"
      check node{"units"}.kind == JArray
      # v3: ONE block per GOVERNED unit of the adopted entry (both
      # disproof-carrying and evidence-less governed units project); the
      # ungoverned failing mutant (candidate B, encodedLength) never gets a
      # block — its global vrFail cannot leak into the display.
      let governed = entryOpt.get().governedSymbols
      check node{"units"}.len == governed.len
      var targetSymbols: seq[string] = @[]
      for i in 0 ..< node{"units"}.len:
        let unitNode = node{"units"}[i]
        targetSymbols.add(unitNode{"targetSymbol"}.getStr())
        check unitNode{"ruleJudgment"}.getStr() == ""
      check targetSymbols.len == targetSymbols.deduplicate().len
      for symbol in governed:
        check (entryOpt.get().governedModule & "::" & symbol) in targetSymbols
      check fixture{"candidateB"}{"unit"}.getStr() notin targetSymbols
      # candidate A's row passed but its unit evidence carries NO claim
      # outcome → absent outcome projects UNKNOWN (§2.3 fail-closed) →
      # attribution can never confirm
      for i in 0 ..< node{"units"}.len:
        let unitNode = node{"units"}[i]
        if unitNode{"targetSymbol"}.getStr() ==
            fixture{"candidateA"}{"unit"}.getStr():
          check unitNode{"propositionVerdict"}.getStr() == "UNKNOWN"
          check unitNode{"bugAttribution"}.getStr() == "Unknown"

    test "converse — the governed unit itself carries the counterexample → the name appears only after all conjuncts pass":
      let fixture = scopeFixture()
      var unitEvidence = newJObject()
      unitEvidence[fixture{"candidateA"}{"unit"}.getStr()] = %*{
        "claimId": "seededgovernedclaim0000000000000000000000000000000000000000",
        "claimOutcome": "clDisproved",
        "evidenceId": "seededgovernedevide000000000000000000000000000000000000000",
        "obligationId": "seededgovernedoblig00000000000000000000000000000000000000",
        "specificationId": "seededgovernedspec0000000000000000000000000000000000000",
        "counterExample": fixture{"candidateB"}{"counterExample"}}
      let crr = scopedRunResult(unitEvidence, statusA = "failed")
      let entryOpt = findEntry(coutSpecRelPath)
      check entryOpt.isSome
      let node = buildBugVerdictDisplayJson(crr, unitEvidence,
        pinnedProbe(coutSpecRelPath), entryOpt.get())
      check node.isNil.not
      let unit0 = node{"units"}[0]
      check unit0{"targetSymbol"}.getStr() ==
        fixture{"candidateA"}{"unit"}.getStr()
      check unit0{"adoptedSpecRef"}{"specId"}.getStr() == "SPEC-B36-COUT"
      check unit0{"adoptedSpecRef"}{"specRelPath"}.getStr() == coutSpecRelPath
      check unit0{"ruleJudgment"}.getStr() == "Axiom-Defined Rule Violated"
      check unit0{"propositionVerdict"}.getStr() == "DISPROVED"
      check unit0{"bugAttribution"}.getStr() == "BUG_SUSPECTED"

  suite "§2.4d scope table — block absence is not-applicable, never Unknown":

    test "commit mismatch → no display block":
      var probe = pinnedProbe(coutSpecRelPath)
      probe.commit = repeat("ab", 20)
      let crr = scopedRunResult(newJObject())
      let entryOpt = findEntry(coutSpecRelPath)
      check entryOpt.isSome
      check buildBugVerdictDisplayJson(crr, newJObject(), probe,
        entryOpt.get()).isNil

    test "blob mismatch → no display block":
      var probe = pinnedProbe(coutSpecRelPath)
      probe.blob = repeat("cd", 32)
      let crr = scopedRunResult(newJObject())
      let entryOpt = findEntry(coutSpecRelPath)
      check entryOpt.isSome
      check buildBugVerdictDisplayJson(crr, newJObject(), probe,
        entryOpt.get()).isNil

    test "commitUnverifiable (real probe against a non-git tempdir with identical blob bytes) → no display block":
      let tmp = getTempDir() / ("ax_scope_probe_" & $getCurrentProcessId())
      createDir(tmp / "stew")
      copyFile(currentSourcePath().parentDir().parentDir() /
               "fixtures" / "bug_verdict_scope" / "base36_pinned_subject.nim",
               tmp / "stew" / "base36.nim")
      defer:
        try:
          removeDir(tmp)
        except CatchableError:
          discard  # axiom:best-effort(tempdir cleanup — the probe result is already consumed)
      let rawOpt = loadRegistryEntryRaw(coutSpecRelPath)
      check rawOpt.isSome
      let probe = probeSubjectIdentity(tmp, rawOpt.get)
      check probe.probeOk.not          # no .git → the exact-commit binding is unverifiable
      let crr = scopedRunResult(newJObject())
      let entryOpt = findEntry(coutSpecRelPath)
      check entryOpt.isSome
      check buildBugVerdictDisplayJson(crr, newJObject(), probe,
        entryOpt.get()).isNil

    test "exact-match → RULE axis follows the run's unit evidence; scope rides the digest":
      # The committed grounds record is present in-repo, so the record-missing
      # degradation (attribution Unknown + "grounds: absent" reason) is
      # measured at the display layer (Suite 1, machine-half + absent
      # grounds). At the builder boundary the exact-match row shows the RULE
      # axis following the run's unit evidence while the attribution axis
      # follows the record (A valid, C unproven → BUG_SUSPECTED); the scope
      # status itself is a digest-bound slot (measured in the digest suite
      # below).
      let fixture = scopeFixture()
      var unitEvidence = newJObject()
      unitEvidence[fixture{"candidateA"}{"unit"}.getStr()] = %*{
        "claimId": "seededgovernedclaim0000000000000000000000000000000000000000",
        "claimOutcome": "clDisproved",
        "evidenceId": "seededgovernedevide000000000000000000000000000000000000000",
        "obligationId": "seededgovernedoblig00000000000000000000000000000000000000",
        "specificationId": "seededgovernedspec0000000000000000000000000000000000000",
        "counterExample": fixture{"candidateB"}{"counterExample"}}
      let crr = scopedRunResult(unitEvidence, statusA = "failed")
      let entryOpt = findEntry(coutSpecRelPath)
      check entryOpt.isSome
      let node = buildBugVerdictDisplayJson(crr, unitEvidence,
        pinnedProbe(coutSpecRelPath), entryOpt.get())
      check node.isNil.not
      let unit0 = node{"units"}[0]
      check unit0{"ruleJudgment"}.getStr() == "Axiom-Defined Rule Violated"
      check unit0{"bugAttribution"}.getStr() == "BUG_SUSPECTED"
      check unit0{"groundsValidation"}.getStr() == ""

  suite "§2.4d digest — every decision-input slot moves the digest":

    proc digestBase(): BugVerdictDisplayInput =
      mkInput(aValid = true, status = "recordedDisclaiming",
        claimOutcome = "clDisproved", machineEstablished = true,
        groundsRawDigest = repeat("ab", 32),
        specId = "SPEC-B36-COUT", specRelPath = coutSpecRelPath)

    test "perturbing each new decision-input slot moves the digest":
      let baseDigest = displayBugVerdict(digestBase()).displayInputDigest
      check baseDigest.len == 64
      var v: BugVerdictDisplayInput
      # target symbol
      v = digestBase(); v.targetSymbol = "stew/base36.nim::decodedLength"
      check displayBugVerdict(v).displayInputDigest != baseDigest
      # selected row status
      v = digestBase(); v.rowStatus = "failed"
      check displayBugVerdict(v).displayInputDigest != baseDigest
      # scope status enum string
      v = digestBase(); v.scopeStatus = "verifiedMatch"
      check displayBugVerdict(v).displayInputDigest != baseDigest
      # claim machine verdict
      v = digestBase(); v.claimOutcome = "clProved"
      check displayBugVerdict(v).displayInputDigest != baseDigest
      # quartet payload digest
      v = digestBase(); v.quartetPayloadDigest = repeat("11", 32)
      check displayBugVerdict(v).displayInputDigest != baseDigest
      # subject commit
      v = digestBase(); v.subjectCommit = pinnedProbe(coutSpecRelPath).commit
      check displayBugVerdict(v).displayInputDigest != baseDigest
      # subject blob
      v = digestBase(); v.subjectBlob = pinnedProbe(coutSpecRelPath).blob
      check displayBugVerdict(v).displayInputDigest != baseDigest
      # specId
      v = digestBase(); v.specId = "SPEC-OTHER"
      check displayBugVerdict(v).displayInputDigest != baseDigest
      # adoptedSpecRef.specRelPath (the unit↔overlay link)
      v = digestBase(); v.specRelPath = "some_other_spec.json"
      check displayBugVerdict(v).displayInputDigest != baseDigest
      # emitted requirement source status
      v = digestBase(); v.assessment.requirementSourceStatus = "unrecorded"
      check displayBugVerdict(v).displayInputDigest != baseDigest

    test "identical scoped runs are byte-identical and the disclaimer rides the block":
      let d1 = displayBugVerdict(digestBase())
      let d2 = displayBugVerdict(digestBase())
      check d1.displayInputDigest == d2.displayInputDigest
      check displayToJson(d1){"displayInputDigestPurpose"}.getStr() ==
        "provenance-trace-only — not a verdict legitimacy proof"

# ---------------------------------------------------------------------------
# Golden — the live bytesview lane reading (units array, per-unit seam)
# ---------------------------------------------------------------------------

suite "golden — SPEC-LIBP2P-BV-SLICE live display projection":

  proc committedBvSpec(): JsonNode =
    committedSpec(bvSpecRelPath)

  proc bvRunResult(unitEvidence: JsonNode): CanonicalRunResult =
    let wave = %*{"nodeReports": @[
      %*{"nodeId": bvUnitKey, "status": "failed", "cacheHit": false,
         "dependencyDepth": 0}]}
    let elig = %*{bvUnitKey: "elProofCandidate"}
    var crr = buildCanonicalRunResult(@[wave], elig, @[@[bvUnitKey]])
    crr.runOutcome = evaluateRunOutcome(crr.runAccounting,
      NoObligationProvenance(universeEnumerated: true,
                             source: "canonical_ogr_eligibility"),
      false)
    crr

  proc bvUnitEvidence(): JsonNode =
    ## The seeded §2.2 quartet payload for the pinned bytesview observation —
    ## the same S6 record shape the counterexample adapter folds (the live
    ## replay observation: len(bv.toOpenArray(1, 4)) == 3, law demands 4).
    %*{bvUnitKey: {
      "claimId": "seededbvclaim0000000000000000000000000000000000000000000000",
      "claimOutcome": "clDisproved",
      "evidenceId": "seededbvevidence00000000000000000000000000000000000000000",
      "obligationId": "seededbvobligation0000000000000000000000000000000000000",
      "specificationId": "seededbvspeccommit00000000000000000000000000000000000",
      "counterExample": [
        "replay.subjectGitRef=a130a7f32219909bdcda14b7f1e64d0804fc832c",
        "replay.moduleSha256=b205c969ba04f4199d8fd4a121d4b6fccdc82c426e336add0e1e9fd0e961e5ee",
        "replay.treeMerkle=seededbytesviewtreemerkle0000000000000000000000",
        "input.e=4",
        "input.b=1",
        "propertyViolated=len(bv.toOpenArray(1, 4)) == 4 (inclusive view-relative slice-length law)",
        "replay.verdict=rvAgree"]}}

  test "the live record + overlay assess: validated, unrecorded, no confirmation claimed":
    let spec = committedBvSpec()
    let grounds = committedBvGrounds()
    let checked = validateGroundsFile(grounds, spec)
    check checked.isOk()
    check checked.get().requirementSourceStatus == "unrecorded"
    let assessment = assessGrounds(grounds, spec)
    check assessment.aValid
    check not assessment.cClaimed
    check not assessment.e1Present
    check not assessment.e2e3Present
    check assessment.requirementSourceStatus == "unrecorded"

  test "the pure projection reads BUG_SUSPECTED [upstream-spec] with the specId binding":
    let spec = committedBvSpec()
    let grounds = committedBvGrounds()
    let ownershipRes = validateClaimOwnership(spec)
    check ownershipRes.isOk()
    check ownershipRes.get() == "axiom-defined-rule"
    let assessment = assessGrounds(grounds, spec)
    let input = BugVerdictDisplayInput(
      machineEstablished: true,
      machineTuple: %*{"verdict": "FAIL", "recordComplete": true},
      ruleId: spec{"ruleId"}.getStr(""),
      ownership: spec{"claimOwnership"}.copy(),
      groundsRefs: groundsRefEntries(grounds),
      groundsRawDigest: repeat("3a", 32),
      assessment: assessment,
      targetSymbol: bvUnitKey,
      claimOutcome: "clDisproved",
      quartetComplete: true,
      specId: "SPEC-LIBP2P-BV-SLICE",
      specRelPath: bvSpecRelPath)
    let d = displayBugVerdict(input)
    check d.ruleJudgment == "Axiom-Defined Rule Violated"
    check d.bugAttribution == "BUG_SUSPECTED"
    check d.propositionVerdict == "DISPROVED"
    check d.requirementSourceStatus == "unrecorded"
    check d.uncertaintyKinds == @["upstream-spec"]
    check d.groundsRefs.len == 2
    for refEntry in d.groundsRefs:
      check refEntry.contains("#" & grounds["recordDigest"].getStr())
    check d.groundsValidation == ""
    check d.displayInputDigest.len == 64

  test "the live bv entry projects ONE v3 unit block over the per-unit seam":
    let entryOpt = findEntry(bvSpecRelPath)
    check entryOpt.isSome
    let entry = entryOpt.get()
    check entry.specId == "SPEC-LIBP2P-BV-SLICE"
    check entry.governedModule == "libp2p/utils/bytesview.nim"
    check entry.governedSymbols == @["toOpenArray"]
    let unitEvidence = bvUnitEvidence()
    let crr = bvRunResult(unitEvidence)
    check crr.runOutcome.verdict == vrFail
    let node = buildBugVerdictDisplayJson(crr, unitEvidence,
      pinnedProbe(bvSpecRelPath), entry)
    check node.isNil.not
    check node{"schemaVersion"}.getStr() == "bug-verdict-display-v3"
    let units = node{"units"}
    check units.kind == JArray
    check units.len == 1
    let unit0 = units[0]
    check unit0{"targetSymbol"}.getStr() == bvUnitKey
    check unit0{"adoptedSpecRef"}{"specId"}.getStr() == "SPEC-LIBP2P-BV-SLICE"
    check unit0{"adoptedSpecRef"}{"specRelPath"}.getStr() == bvSpecRelPath
    check unit0{"ruleJudgment"}.getStr() == "Axiom-Defined Rule Violated"
    check unit0{"bugAttribution"}.getStr() == "BUG_SUSPECTED"
    check unit0{"propositionVerdict"}.getStr() == "DISPROVED"
    check unit0{"requirementSourceStatus"}.getStr() == "unrecorded"
    check unit0{"uncertaintyKinds"} == %*["upstream-spec"]
    check unit0{"groundsRefs"}.len == 2
    for refEntry in unit0{"groundsRefs"}:
      check refEntry.getStr().contains("#")
    check unit0{"groundsValidation"}.getStr() == ""
    check unit0{"displayInputDigest"}.getStr().len == 64
    check unit0{"displayInputDigestPurpose"}.getStr() ==
      "provenance-trace-only — not a verdict legitimacy proof"

  test "the bv unit with a clProved claim → block with UNKNOWN / Unknown (NOT_DISPROVED unobservable)":
    let entryOpt = findEntry(bvSpecRelPath)
    check entryOpt.isSome
    var unitEvidence = bvUnitEvidence()
    unitEvidence[bvUnitKey]["claimOutcome"] = %"clProved"
    let crr = bvRunResult(unitEvidence)
    let node = buildBugVerdictDisplayJson(crr, unitEvidence,
      pinnedProbe(bvSpecRelPath), entryOpt.get())
    check node.isNil.not
    let unit0 = node{"units"}[0]
    # NOT_DISPROVED is unreachable in the display layer: §2.1's vdVerified
    # conjunct is never serialized into wave/runResult/unitEvidence, so a
    # bare clProved can never complete the NOT_DISPROVED conjunction —
    # fail-closed UNKNOWN (glossary §2.2 note; the serialization gap is a
    # follow-up)
    check unit0{"propositionVerdict"}.getStr() == "UNKNOWN"
    check unit0{"bugAttribution"}.getStr() == "Unknown"
    check unit0{"ruleJudgment"}.getStr() == ""

  # -------------------------------------------------------------------------
  # WP-B — the findingEvidence state-document root evidence carrier
  # -------------------------------------------------------------------------
  # appendDisplayAndPersist is module-private (its composition is verified
  # end-to-end by a real prove run in the integration step); the persistence
  # PATH it uses is the EXPORTED renderPersist — pinned here over synthetic
  # documents: the block lands at the state document ROOT with the fixed
  # reporter-consumed field spellings (upstream_reporting_contract.md).
  suite "findingEvidence — the state-document root evidence carrier":

    test "renderPersist persists the findingEvidence block at the state document root (fixed reporter interface)":
      let fixture = scopeFixture()
      let unitKey = fixture{"candidateB"}{"unit"}.getStr()
      let wave = %*{"nodeReports": @[
        %*{"nodeId": unitKey, "status": "failed", "cacheHit": false,
           "dependencyDepth": 0}]}
      let elig = %*{unitKey: "elProofCandidate"}
      var crr = buildCanonicalRunResult(@[wave], elig, @[@[unitKey]])
      crr.runOutcome = evaluateRunOutcome(crr.runAccounting,
        NoObligationProvenance(universeEnumerated: true,
                               source: "canonical_ogr_eligibility"),
        false)
      check crr.runOutcome.verdict == vrFail
      let quartetLines = fixture{"candidateB"}{"counterExample"}
      let findingEvidence = %*{unitKey: {
        "claimOutcome": "clDisproved",
        "rowStatus": "failed",
        "machineVerdict": "FAIL",
        "machineEstablished": true,
        "counterExample": quartetLines,
        "quartetPayloadDigest": repeat("5a", 32),
        "subjectCommit": repeat("ab", 20),
        "subjectBlob": repeat("cd", 32)}}
      let statePath = getTempDir() / ("ax_finding_evidence_" &
        $getCurrentProcessId() & ".json")
      defer:
        try:
          removeFile(statePath)
        except CatchableError:
          discard  # axiom:best-effort(tempfile cleanup — assertions already ran)
      let persisted = renderPersist(statePath, crr,
        %*{"summary": {"totalNodes": 1}}, %*{"scopeObservability": {}},
        nil, findingEvidence)
      check persisted.isOk()
      let stateDoc = parseJson(readFile(statePath))
      check stateDoc.hasKey("findingEvidence")
      let entry = stateDoc{"findingEvidence"}{unitKey}
      check entry{"claimOutcome"}.getStr() == "clDisproved"
      check entry{"rowStatus"}.getStr() == "failed"
      check entry{"machineVerdict"}.getStr() == "FAIL"
      check entry{"machineEstablished"}.getBool()
      check entry{"counterExample"} == quartetLines
      check entry{"quartetPayloadDigest"}.getStr() == repeat("5a", 32)
      check entry{"subjectCommit"}.getStr() == repeat("ab", 20)
      check entry{"subjectBlob"}.getStr() == repeat("cd", 32)
      # a state-document ROOT key — never a display-unit key (LCD keys unchanged)
      check stateDoc{"display"}.isNil

    test "renderPersist without the carrier writes no findingEvidence key (absence, never fabricated)":
      let fixture = scopeFixture()
      let unitKey = fixture{"candidateB"}{"unit"}.getStr()
      let wave = %*{"nodeReports": @[
        %*{"nodeId": unitKey, "status": "verified", "cacheHit": false,
           "dependencyDepth": 0}]}
      let elig = %*{unitKey: "elProofCandidate"}
      var crr = buildCanonicalRunResult(@[wave], elig, @[@[unitKey]])
      crr.runOutcome = evaluateRunOutcome(crr.runAccounting,
        NoObligationProvenance(universeEnumerated: true,
                               source: "canonical_ogr_eligibility"),
        false)
      let statePath = getTempDir() / ("ax_finding_absent_" &
        $getCurrentProcessId() & ".json")
      defer:
        try:
          removeFile(statePath)
        except CatchableError:
          discard  # axiom:best-effort(tempfile cleanup — assertions already ran)
      let persisted = renderPersist(statePath, crr,
        %*{"summary": {"totalNodes": 1}}, %*{"scopeObservability": {}},
        nil, nil)
      check persisted.isOk()
      let stateDoc = parseJson(readFile(statePath))
      check not stateDoc.hasKey("findingEvidence")

# ---------------------------------------------------------------------------
# §3 two-axis state model — display.propositions[] capability rollup
# (machine-verification verdicts stay the closed 3-value set; the capability
# axis is a sibling projection of intake/dispatch-decided facts)
# ---------------------------------------------------------------------------

suite "proposition capability rollup — two-axis display projection":
  test "CAPABLE entry serializes without a reason and with the attempted verdict":
    let rollup = @[
      PropositionRollupDisplay(id: "p1",
        capabilityStatus: propositionCapabilityCapableSpelling,
        capabilityReason: "", attempted: true,
        verdict: propositionDisprovedSpelling)]
    let j = propositionsToJson(rollup)
    check j.len == 1
    check j[0]{"id"}.getStr("") == "p1"
    check j[0]{"capability"}{"status"}.getStr("") == "CAPABLE"
    check not j[0]{"capability"}.hasKey("reason")
    check j[0]{"verification"}{"attempted"}.getBool() == true
    check j[0]{"verification"}{"verdict"}.getStr("") == "DISPROVED"
  test "INCAPABLE entry carries the reason and a null verdict":
    let rollup = @[
      PropositionRollupDisplay(id: "p2",
        capabilityStatus: propositionCapabilityIncapableSpelling,
        capabilityReason: "UNKNOWN_SPEC", attempted: false,
        verdict: "")]
    let j = propositionsToJson(rollup)
    check j[0]{"capability"}{"status"}.getStr("") == "INCAPABLE"
    check j[0]{"capability"}{"reason"}.getStr("") == "UNKNOWN_SPEC"
    check j[0]{"verification"}{"attempted"}.getBool() == false
    check j[0]{"verification"}{"verdict"}.kind == JNull
  test "round-trip: the serialized entry parses back to the documented shape":
    let rollup = @[
      PropositionRollupDisplay(id: "cap",
        capabilityStatus: propositionCapabilityCapableSpelling,
        capabilityReason: "", attempted: true,
        verdict: propositionUnknownSpelling),
      PropositionRollupDisplay(id: "incap",
        capabilityStatus: propositionCapabilityIncapableSpelling,
        capabilityReason: "UNSUPPORTED_LOGIC", attempted: false,
        verdict: "")]
    let j = parseJson($propositionsToJson(rollup))
    check j.kind == JArray and j.len == 2
    for entry in j:
      check entry.kind == JObject
      check entry{"capability"}{"status"}.getStr("") in [
        propositionCapabilityCapableSpelling, propositionCapabilityIncapableSpelling]
      let verdict = entry{"verification"}{"verdict"}
      check verdict.kind == JNull or verdict.getStr("") in [
        propositionDisprovedSpelling, propositionNotDisprovedSpelling,
        propositionUnknownSpelling]
      if entry{"capability"}{"status"}.getStr("") ==
          propositionCapabilityIncapableSpelling:
        check entry{"verification"}{"attempted"}.getBool() == false
        check verdict.kind == JNull
  test "container carries the rollup under its own version key only when non-empty":
    let units = @[%*{"targetSymbol": "m::f"}]
    let bare = displayContainerJson(units)
    check bare{"schemaVersion"}.getStr("") == "bug-verdict-display-v3"
    check not bare.hasKey("propositions")
    check not bare.hasKey("propositionRollupSchemaVersion")
    let rollup = @[
      PropositionRollupDisplay(id: "p3",
        capabilityStatus: propositionCapabilityIncapableSpelling,
        capabilityReason: "LANE_NOT_EQUIPPED", attempted: false,
        verdict: "")]
    let withRollup = displayContainerJson(units, rollup)
    check withRollup{"propositionRollupSchemaVersion"}.getStr("") ==
      propositionRollupSchemaVersion
    check withRollup{"propositions"}.len == 1
    check withRollup{"propositions"}[0]{"capability"}{"reason"}.getStr("") ==
      "LANE_NOT_EQUIPPED"
    check withRollup{"units"}.len == 1
  test "attempted verdict values stay inside the closed proposition set (never PASS/FAIL)":
    let rollup = @[
      PropositionRollupDisplay(id: "p4",
        capabilityStatus: propositionCapabilityCapableSpelling,
        capabilityReason: "", attempted: true,
        verdict: propositionVerdictOf("clProved", "PASS", true)),
      PropositionRollupDisplay(id: "p5",
        capabilityStatus: propositionCapabilityCapableSpelling,
        capabilityReason: "", attempted: true,
        verdict: propositionVerdictOf("clDisproved", "FAIL", true))]
    for entry in propositionsToJson(rollup):
      check entry{"verification"}{"verdict"}.getStr("") in [
        propositionDisprovedSpelling, propositionNotDisprovedSpelling,
        propositionUnknownSpelling]
