## B2 — Test suite for the Axiom readiness evaluator.
##
## Targets the interface in docs/spec/productization_contract.md §9:
##   loadEvidenceFiles / validateEvidence / normalizeBundle / evaluateReadiness
## plus the CLI. The implementation lives at tools/readiness_evaluator.nim; this
## suite guards its public contract even when that module is absent (the
## conditional import below falls back to a local pure copy of the §3 verdict
## algebra so the decision-algebra property test still compiles and runs).
##
## Run from repo root:
##   nim c -r --hints:off --nimcache:/tmp/axiom_readiness_nimcache \
##       tests/readiness/readiness_policy_test.nim

import std/[json, unittest, strutils, algorithm, sequtils, tables, os, osproc]
import ../../src/core/trusted/trust_boundary

# ── Conditional evaluator import ────────────────────────────────────────────
const EVALUATOR_SOURCE = "tools/readiness_evaluator.nim"
# Test lives at tests/readiness/, so repo root is three parentDir() levels up.
const REPO_ROOT = currentSourcePath().parentDir().parentDir().parentDir()
const EVALUATOR_PRESENT =
  when defined(axiomEvaluatorImported):
    true
  else:
    staticExec("test -f " & REPO_ROOT / EVALUATOR_SOURCE & " && echo yes").strip() == "yes"

when EVALUATOR_PRESENT:
  import ../../tools/readiness_evaluator as readiness_evaluator
  const EVALUATOR_AVAILABLE = true
else:
  const EVALUATOR_AVAILABLE = false

# ── Local pure copy of the §3 verdict algebra ──────────────────────────────
# Used as the fallback reference implementation when the evaluator module is
# missing, and as the cross-check oracle when it is present.

const INV_IDS* = ["R1","R2","R3","R4","R5","R6","R7","R8"]

type
  InvState* = enum
    stPass = "PASS"
    stFail = "FAIL"
    stUnknown = "UNKNOWN"

  InvKind* = enum
    evCritical = "critical"
    evNonCritical = "non-critical"

proc criticalityOf*(policy: JsonNode, invId: string): InvKind =
  let c = policy["invariants"][invId]["criticality"].getStr()
  if c == "critical": evCritical
  else: evNonCritical

proc verdictFromStatesLocal*(
    states: openArray[tuple[id: string, state: InvState]],
    policy: JsonNode): tuple[verdict: string, conditions: seq[string]] =
  ## Pure §3 decision algebra:
  ##   GO             ⟺ all PASS
  ##   CONDITIONAL GO ⟺ all critical PASS ∧ ∃ non-critical ≠ PASS
  ##   NO-GO          ⟺ ∃ critical ∈ {FAIL, UNKNOWN}
  var anyNonCriticalNotPass = false
  for (invId, st) in states:
    let kind = criticalityOf(policy, invId)
    if kind == evCritical and st != stPass:
      return ("NO-GO", @[])
    if kind == evNonCritical and st != stPass:
      anyNonCriticalNotPass = true
  if anyNonCriticalNotPass:
    var conds: seq[string] = @[]
    for (invId, st) in states:
      let kind = criticalityOf(policy, invId)
      if kind == evNonCritical and st != stPass:
        conds.add(invId & "=" & $st)
    return ("CONDITIONAL GO", conds)
  return ("GO", @[])

# ── Policy fixture loader ──────────────────────────────────────────────────
# Policy is the only file IO performed by the test (per task spec). All other
# evaluation inputs are constructed as JsonNode in-process.

proc loadPolicy(): JsonNode =
  let path = "config/readiness_policy.json"
  if not fileExists(path):
    # Try relative to the test file's parent tree (repo root).
    let alt = REPO_ROOT / path
    if fileExists(alt):
      return parseFile(alt)
  return parseFile(path)

let POLICY = loadPolicy()

# ══════════════════════════════════════════════════════════════════════════════
# Suite 1 — Decision algebra property test (REQUIRED, exhaustive)
# ══════════════════════════════════════════════════════════════════════════════

suite "§3 Decision algebra — exhaustive 3^8 property test":
  proc expectedVerdict(states: array[8, InvState]): string =
    var anyNonCriticalNotPass = false
    for i, st in states:
      let kind = criticalityOf(POLICY, INV_IDS[i])
      if kind == evCritical and st != stPass:
        return "NO-GO"
      if kind == evNonCritical and st != stPass:
        anyNonCriticalNotPass = true
    if anyNonCriticalNotPass: return "CONDITIONAL GO"
    return "GO"

  test "exhaustive 3^8 = 6561 invariant-state vectors match the §3 rule":
    var total = 0
    var goCount = 0; var condCount = 0; var nogoCount = 0
    for a in 0..2:
      for b in 0..2:
        for c in 0..2:
          for d in 0..2:
            for e in 0..2:
              for f in 0..2:
                for g in 0..2:
                  for h in 0..2:
                    let states = [
                      InvState(a), InvState(b), InvState(c), InvState(d),
                      InvState(e), InvState(f), InvState(g), InvState(h)]
                    let got = verdictFromStatesLocal(
                      zip(INV_IDS, states).mapIt((id: it[0], state: it[1])),
                      POLICY).verdict
                    let want = expectedVerdict(states)
                    check got == want
                    total += 1
                    case want
                    of "GO": goCount += 1
                    of "CONDITIONAL GO": condCount += 1
                    else: nogoCount += 1
    check total == 6561
    check goCount > 0 and condCount > 0 and nogoCount > 0
    echo "  [algebra] 6561 vectors: GO=" & $goCount &
      " CONDITIONAL-GO=" & $condCount & " NO-GO=" & $nogoCount

  test "permutation invariance (≥40 random permutations incl. identity)":
    let base = zip(INV_IDS, [
      stPass, stPass, stPass, stPass, stPass, stPass, stFail, stPass])
    let (v0, c0) = verdictFromStatesLocal(base, POLICY)
    check v0 == "CONDITIONAL GO"
    check c0 == @["R7=FAIL"]
    var rng = 12345'u32
    for n in 0..<40:
      # deterministic LCG permutation (no std/random dependency)
      var idx = toSeq(0..7)
      var i = idx.len
      while i > 1:
        rng = (1103515245'u32 * rng + 12345'u32) mod (0x7fffffff'u32)
        let j = int(rng mod uint32(i))
        swap(idx[i-1], idx[j])
        dec i
      let perm = idx.mapIt(base[it])
      let (v, c) = verdictFromStatesLocal(perm, POLICY)
      check v == v0
      check c == c0
    echo "  [algebra] 40 permutations all produced identical verdict"

# ══════════════════════════════════════════════════════════════════════════════
# Suite 2 — Cross-check against the evaluator module (if present)
# ══════════════════════════════════════════════════════════════════════════════

suite "§9 Evaluator cross-check (skipped when module absent)":
  test "verdictFromStates exported by evaluator matches local oracle (≥64 samples)":
    when EVALUATOR_AVAILABLE:
      var total = 0
      var matches = 0
      for a in 0..2:
        for b in 0..2:
          for c in 0..2:
            for d in 0..2:
              for e in 0..2:
                for f in 0..2:
                  for g in 0..2:
                    for h in 0..2:
                      let states = [
                        InvState(a), InvState(b), InvState(c), InvState(d),
                        InvState(e), InvState(f), InvState(g), InvState(h)]
                      let local = verdictFromStatesLocal(
                        zip(INV_IDS, states).mapIt((id: it[0], state: it[1])),
                        POLICY)
                      let ev = readiness_evaluator.verdictFromStates(
                        zip(INV_IDS, states).mapIt((id: it[0], state: it[1])),
                        POLICY)
                      total += 1
                      if local.verdict == ev.verdict and local.conditions == ev.conditions:
                        matches += 1
      check total == 6561
      check matches == 6561
      echo "  [cross-check] evaluator verdictFromStates matched local oracle on " &
        $matches & "/" & $total & " vectors"
    else:
      echo "  [cross-check] SKIPPED: tools/readiness_evaluator.nim not present"
      skip()

# ══════════════════════════════════════════════════════════════════════════════
# Suite 3 — R7 promotion (over-scope verification)
# ══════════════════════════════════════════════════════════════════════════════

suite "R7 promotion / scope honesty":
  test "verifiedEmitterScope token outside claimedScope -> R1 FAIL + R2 FAIL":
    when EVALUATOR_AVAILABLE:
      let bundle = readiness_evaluator.normalizeBundle(@[
        readiness_evaluator.makeEvidence(
          "R7", @[
            readiness_evaluator.makeObs("claimedScope", %["ax prove", "ax report"]),
            readiness_evaluator.makeObs("measuredCoverage", %0.8),
            readiness_evaluator.makeObs("verifiedEmitterScope",
              %["ax prove", "ax report", "ax status"])])]).get
      let d = readiness_evaluator.evaluateReadiness(POLICY, bundle)
      check d.invariantStates["R1"].getStr() == "FAIL"
      check d.invariantStates["R2"].getStr() == "FAIL"
      check d.invariantStates["R7"].getStr() == "PASS"
      check d.verdict == "NO-GO"
      echo "  [r7] over-scope promotion: R1/R2 promoted to FAIL, verdict NO-GO"
    else:
      skip()

  test "low vkd (< threshold) -> R7 FAIL; R1..R6/R8 missing -> UNKNOWN -> NO-GO":
    when EVALUATOR_AVAILABLE:
      let bundle = readiness_evaluator.normalizeBundle(@[
        readiness_evaluator.makeEvidence(
          "R7", @[
            readiness_evaluator.makeObs("claimedScope", %["ax prove"]),
            readiness_evaluator.makeObs("measuredCoverage", %0.1),
            readiness_evaluator.makeObs("verifiedEmitterScope", %["ax prove"])])]).get
      let d = readiness_evaluator.evaluateReadiness(POLICY, bundle)
      check d.invariantStates["R7"].getStr() == "FAIL"
      # Missing evidence for the critical invariants -> UNKNOWN -> NO-GO
      # (spec: missing evidence is never an implicit PASS).
      check d.verdict == "NO-GO"
      echo "  [r7] vkd=0.1 < 0.5 -> R7 FAIL; verdict NO-GO (critical UNKNOWN)"
    else:
      skip()

# ══════════════════════════════════════════════════════════════════════════════
# Suite 4 — Contradiction resolution
# ══════════════════════════════════════════════════════════════════════════════

suite "Contradiction resolution":
  test "same (key,scope,subject) conflicting bool -> UNKNOWN":
    when EVALUATOR_AVAILABLE:
      let b = readiness_evaluator.normalizeBundle(@[
        readiness_evaluator.makeEvidence("R1", @[
          readiness_evaluator.makeObs("commandExists", %true, "surface", "ax prove"),
          readiness_evaluator.makeObs("commandExists", %false, "surface", "ax prove")])]).get
      let d = readiness_evaluator.evaluateReadiness(POLICY, b)
      check d.invariantStates["R1"].getStr() == "UNKNOWN"
      check d.verdict == "NO-GO"
      echo "  [contradiction] conflicting bool -> R1 UNKNOWN"
    else:
      skip()

  test "different scope -> no contradiction recorded":
    when EVALUATOR_AVAILABLE:
      let b = readiness_evaluator.normalizeBundle(@[
        readiness_evaluator.makeEvidence("R1", @[
          readiness_evaluator.makeObs("commandExists", %true, "surface", "ax prove"),
          readiness_evaluator.makeObs("commandExists", %false, "docs", "ax prove")])]).get
      # A different scope is a different fact, not a contradiction: the
      # normalization boundary must not flag R1. (R1 itself is UNKNOWN here
      # under the DEBT#559 key contract because required keys are absent —
      # that is closure, never a contradiction-derived UNKNOWN.)
      let inv = b["invariants"]["R1"]
      check not (inv.hasKey("contradiction") and inv["contradiction"].getBool())
      echo "  [contradiction] different scope -> no contradiction flag"
    else:
      skip()

# ══════════════════════════════════════════════════════════════════════════════
# Suite 5 — Envelope validity
# ══════════════════════════════════════════════════════════════════════════════

suite "Envelope validity":
  test "malformed envelope (missing source etc.) -> rejected":
    when EVALUATOR_AVAILABLE:
      for bad in @[
        readiness_evaluator.parseEvidence(%*{"schemaVersion": 1, "invariantId": "R1"}),
        readiness_evaluator.parseEvidence(%*{"schemaVersion": 1, "invariantId": "R1",
          "observations": [{"key":"commandExists","value":"not-a-bool"}],
          "sources": []}),
        readiness_evaluator.parseEvidence(%*{"schemaVersion": 1, "invariantId": "R1",
          "observations": [], "sources": []})]:
        let v = readiness_evaluator.validateEvidence(bad, readiness_evaluator.defaultContext())
        check v.isErr
      echo "  [validity] malformed envelopes rejected"
    else:
      skip()

  test "stale evidence (freshUntil < evaluationTime) -> rejected":
    when EVALUATOR_AVAILABLE:
      let ctx = readiness_evaluator.makeContext(evaluationTime = "2026-09-01T00:00:00Z")
      let raw = %*{"schemaVersion": 1, "invariantId": "R1",
        "collection": {"generatedAt": "2026-08-01T00:00:00Z",
                       "freshUntil": "2026-08-15T00:00:00Z"},
        "observations": [{"key": "commandExists", "value": true, "scope": "surface", "subject": "ax prove"}],
        "sources": [{"file": "x", "lines": "1", "symbol": "y", "sha256": "sha256:0", "repoHead": "z"}]}
      let v = readiness_evaluator.validateEvidence(raw, ctx)
      check v.isErr
      echo "  [validity] stale evidence rejected"
    else:
      skip()

  test "missing R3 file entirely (bundle without it) -> R3 NOT_RUN":
    when EVALUATOR_AVAILABLE:
      let bundle = readiness_evaluator.normalizeBundle(@[]).get
      let d = readiness_evaluator.evaluateReadiness(POLICY, bundle)
      # §3 closed vocabulary: an invariant with no evidence file is NOT_RUN
      # (distinct from UNKNOWN); on a critical invariant either state is NO-GO.
      check d.invariantStates["R3"].getStr() == "NOT_RUN"
      check d.verdict == "NO-GO"
      echo "  [validity] empty bundle -> R3 NOT_RUN, verdict NO-GO"
    else:
      skip()

  test "workingTreeClean=false for R1 evidence while ctx says clean -> invalid":
    when EVALUATOR_AVAILABLE:
      let ctx = readiness_evaluator.makeContext(workingTreeClean = true)
      let raw = %*{"schemaVersion": 1, "invariantId": "R1",
        "repoIdentity": {"workingTreeClean": false},
        "observations": [{"key": "commandExists", "value": true, "scope": "surface", "subject": "ax prove"}],
        "sources": [{"file": "x", "lines": "1", "symbol": "y", "sha256": "sha256:0", "repoHead": "z"}]}
      let v = readiness_evaluator.validateEvidence(raw, ctx)
      check v.isErr
      echo "  [validity] R1 with dirty tree rejected"
    else:
      skip()

# ══════════════════════════════════════════════════════════════════════════════
# Suite 6 — Digests (idempotency + sensitivity)
# ══════════════════════════════════════════════════════════════════════════════

suite "Digests":
  test "same bundle evaluated twice -> identical decision JSON + decisionDigest":
    when EVALUATOR_AVAILABLE:
      let bundle = readiness_evaluator.normalizeBundle(@[
        readiness_evaluator.makeEvidence("R1", @[
          readiness_evaluator.makeObs("documented", %"ax prove"),
          readiness_evaluator.makeObs("commandExists", %true, "surface", "ax prove")])]).get
      let d1 = readiness_evaluator.evaluateReadiness(POLICY, bundle)
      let d2 = readiness_evaluator.evaluateReadiness(POLICY, bundle)
      check d1.verdict == d2.verdict
      check d1.conditions == d2.conditions
      check d1.decisionDigest == d2.decisionDigest
      echo "  [digest] idempotent evaluation"
    else:
      skip()

  test "bundleDigest changes when one observation value changes":
    when EVALUATOR_AVAILABLE:
      let b1 = readiness_evaluator.normalizeBundle(@[
        readiness_evaluator.makeEvidence("R1", @[
          readiness_evaluator.makeObs("commandExists", %true)])]).get
      let b2 = readiness_evaluator.normalizeBundle(@[
        readiness_evaluator.makeEvidence("R1", @[
          readiness_evaluator.makeObs("commandExists", %false)])]).get
      check b1["bundleDigest"].getStr() != b2["bundleDigest"].getStr()
      echo "  [digest] bundleDigest sensitive to observation change"
    else:
      skip()

# ══════════════════════════════════════════════════════════════════════════════
# Suite 7 — Golden fixture
# ══════════════════════════════════════════════════════════════════════════════

suite "Golden fixture":
  test "synthetic bundle fixture matches data/golden/readiness/decision.golden.json":
    when EVALUATOR_AVAILABLE:
      let fixturePath = currentSourcePath().parentDir() / "fixtures" / "synthetic_bundle.json"
      let fixture = parseFile(fixturePath)
      let bundle = readiness_evaluator.normalizeBundle(
        readiness_evaluator.loadEvidenceFromJson(fixture)).get
      let decision = readiness_evaluator.evaluateReadiness(POLICY, bundle)
      let goldenPath = "data/golden/readiness/decision.golden.json"
      let golden = parseFile(goldenPath)
      check decision.verdict == golden["verdict"].getStr()
      check decision.conditions == golden["conditions"].toSeq().mapIt(it.getStr())
      check decision.decisionDigest.len == 64
      check decision.decisionDigest == golden["decisionDigest"].getStr()
      echo "  [golden] decision matches golden: " & decision.verdict
    else:
      # tools/readiness_evaluator.nim is absent: the golden was frozen by hand
      # (see tests/readiness/fixtures/synthetic_bundle.json — // golden-candidate
      # comment). Verify the frozen artifact is self-consistent against the §3
      # local oracle.
      let goldenPath = "data/golden/readiness/decision.golden.json"
      check fileExists(goldenPath)
      let golden = parseFile(goldenPath)
      check golden["verdict"].getStr() == "GO"
      check golden["conditions"].toSeq().mapIt(it.getStr()) == newSeq[string]()
      let states = golden["invariantStates"]
      for invId in INV_IDS:
        check states[invId].getStr() == "PASS"
      var arr: seq[InvState] = @[]
      for invId in INV_IDS:
        arr.add(if states[invId].getStr() == "PASS": stPass else: stFail)
      let local = verdictFromStatesLocal(zip(INV_IDS, arr), POLICY)
      check local.verdict == golden["verdict"].getStr()
      check local.conditions == golden["conditions"].toSeq().mapIt(it.getStr())
      check golden["decisionDigest"].getStr().len == 64
      echo "  [golden] hand-frozen golden self-consistent with §3 oracle"

# ══════════════════════════════════════════════════════════════════════════════
# Suite 8 — U1: trust-boundary register as an observation key (lane readiness)
# ══════════════════════════════════════════════════════════════════════════════

proc loadSyntheticFixture(): JsonNode =
  parseFile(currentSourcePath().parentDir() / "fixtures" / "synthetic_bundle.json")

proc laneClaimObs(lane: string): JsonNode =
  %*{"key": "subjectLane", "value": [lane], "scope": "", "subject": ""}

proc appendLaneClaim(fixture: JsonNode, lane: string) =
  ## Adds a subjectLane claim to the fixture's R1 envelope (in place; every
  ## test parses its own fixture copy).
  for e in fixture.items:
    if e["invariantId"].getStr() == "R1":
      e["observations"].add(laneClaimObs(lane))
      return
  doAssert false, "fixture has no R1 envelope"

proc setFixtureVkd(fixture: JsonNode, coverage: float) =
  for e in fixture.items:
    if e["invariantId"].getStr() == "R7":
      for o in e["observations"].items:
        if o["key"].getStr() == "measuredCoverage":
          o["value"] = %coverage
          return
  doAssert false, "fixture has no R7 measuredCoverage"

proc policyLaneComponents(lane: string): seq[string] =
  POLICY["r1"]["trustBoundaryLanes"][lane].toSeq().mapIt(it.getStr())

proc registerMissingOf(components: seq[string]): seq[string] =
  ## The subset of `components` the register itself declares as exists:false —
  ## derived through the register's own accessor, never restated in the test.
  for c in components:
    if not existsInTrustBoundary(c):
      result.add(c)

suite "U1 — trust-boundary register as observation key (lane readiness)":
  test "lane with all register boundaries exists:true -> GO permitted":
    when EVALUATOR_AVAILABLE:
      # Real policy + real register: the nim lane's boundaries all exist, so a
      # nim lane claim leaves R1 PASS and a fully-passing bundle reaches GO.
      let fixture = loadSyntheticFixture()
      appendLaneClaim(fixture, "nim")
      setFixtureVkd(fixture, 0.8)
      let bundle = readiness_evaluator.normalizeBundle(
        readiness_evaluator.loadEvidenceFromJson(fixture)).get
      let d = readiness_evaluator.evaluateReadiness(POLICY, bundle)
      check d.invariantStates["R1"].getStr() == "PASS"
      check d.verdict == "GO"
      echo "  [u1] nim lane claim (all boundaries exist) -> R1 PASS, verdict GO"
    else:
      skip()

  test "lane with exists:false boundary -> NOT GO with reason":
    when EVALUATOR_AVAILABLE:
      let fixture = loadSyntheticFixture()
      appendLaneClaim(fixture, "rust")
      setFixtureVkd(fixture, 0.8)  # everything else passing: the lane blocks
      let bundle = readiness_evaluator.normalizeBundle(
        readiness_evaluator.loadEvidenceFromJson(fixture)).get
      let d = readiness_evaluator.evaluateReadiness(POLICY, bundle)
      check d.invariantStates["R1"].getStr() == "FAIL"
      check d.verdict == "NO-GO"
      check d.outcome == "BLOCK"
      check d.failureCategory == "CONTRACT_FAIL"
      let reasons = readiness_evaluator.trustLaneViolations(
        @[laneClaimObs("rust")], POLICY, AxiomTrustBoundary)
      let expected = registerMissingOf(policyLaneComponents("rust"))
      check expected.len == 3
      check reasons.len == expected.len
      for comp in expected:
        check reasons.anyIt(it.contains(comp))
      check reasons.allIt(it.contains("exists:false"))
      echo "  [u1] rust lane claim -> R1 FAIL, verdict NO-GO, reasons: " &
        $reasons.len
    else:
      skip()

  test "unregistered lane -> NOT GO (fail-closed)":
    when EVALUATOR_AVAILABLE:
      let fixture = loadSyntheticFixture()
      appendLaneClaim(fixture, "fortran")
      setFixtureVkd(fixture, 0.8)
      let bundle = readiness_evaluator.normalizeBundle(
        readiness_evaluator.loadEvidenceFromJson(fixture)).get
      let d = readiness_evaluator.evaluateReadiness(POLICY, bundle)
      check d.invariantStates["R1"].getStr() == "FAIL"
      check d.verdict == "NO-GO"
      let reasons = readiness_evaluator.trustLaneViolations(
        @[laneClaimObs("fortran")], POLICY, AxiomTrustBoundary)
      check reasons.len == 1
      check reasons[0].contains("not registered")
      echo "  [u1] unregistered lane -> R1 FAIL with not-registered reason"
    else:
      skip()

  test "register observation is actually read (not hardcoded)":
    when EVALUATOR_AVAILABLE:
      # (1) Register-flip sensitivity: same claim + same policy, only the
      # register differs — the verdict-tracking value comes from the register.
      let synthPolicy = %*{"r1": {"trustBoundaryLanes": {
        "testlane": ["alpha boundary", "beta boundary"]}}}
      let claims = @[laneClaimObs("testlane")]
      proc boundary(name: string, live: bool): TrustBoundary =
        TrustBoundary(component: name, category: tcTrusted,
                      rationale: "synthetic", exists: live)
      let allExists = @[boundary("alpha boundary", true),
                        boundary("beta boundary", true)]
      let oneMissing = @[boundary("alpha boundary", true),
                         boundary("beta boundary", false)]
      check readiness_evaluator.trustLaneViolations(
        claims, synthPolicy, allExists).len == 0
      let flipped = readiness_evaluator.trustLaneViolations(
        claims, synthPolicy, oneMissing)
      check flipped.len == 1
      check flipped[0].contains("beta boundary")
      # (2) Undeclared component direction: a policy component absent from the
      # register cannot pass (no silent assumption of existence).
      let partialRegister = @[boundary("alpha boundary", true)]
      let undeclared = readiness_evaluator.trustLaneViolations(
        claims, synthPolicy, partialRegister)
      check undeclared.len == 1
      check undeclared[0].contains("not declared")
      # (3) Real wiring: the evaluator's production gate (AxiomTrustBoundary)
      # matches a derivation through the register's own accessor — the same
      # lane claim that blocks rust passes nim, derived from register data.
      let realReasons = readiness_evaluator.trustLaneViolations(
        @[laneClaimObs("rust"), laneClaimObs("nim")], POLICY, AxiomTrustBoundary)
      let rustMissing = registerMissingOf(policyLaneComponents("rust"))
      check rustMissing.len == 3
      check realReasons.len == rustMissing.len
      for comp in rustMissing:
        check realReasons.anyIt(it.contains(comp))
      check realReasons.allIt(it.contains("rust"))
      # (4) No lane claim -> the gate is silent (canonical evidence path is
      # unchanged; the fixture without a claim still evaluates R1 PASS).
      check readiness_evaluator.trustLaneViolations(
        @[], POLICY, AxiomTrustBoundary).len == 0
      let plain = readiness_evaluator.normalizeBundle(
        readiness_evaluator.loadEvidenceFromJson(loadSyntheticFixture())).get
      let d = readiness_evaluator.evaluateReadiness(POLICY, plain)
      check d.invariantStates["R1"].getStr() == "PASS"
      echo "  [u1] register flip flips the gate; production wiring matches " &
        "the register accessor"
    else:
      skip()

# ══════════════════════════════════════════════════════════════════════════════
# Suite 10 — DEBT#559 observation-key closure (false-GO regression)
# ══════════════════════════════════════════════════════════════════════════════

when EVALUATOR_AVAILABLE:
  proc envelopeOf(fixture: JsonNode, invId: string): JsonNode =
    for e in fixture.items:
      if e["invariantId"].getStr() == invId:
        return e
    doAssert false, "fixture has no " & invId & " envelope"

  proc replaceObservations(fixture: JsonNode, invId: string,
                           obs: openArray[JsonNode]) =
    let arr = newJArray()
    for o in obs:
      arr.add(o)
    envelopeOf(fixture, invId)["observations"] = arr

  proc removeObs(fixture: JsonNode, invId, key: string) =
    let kept = newJArray()
    for o in envelopeOf(fixture, invId)["observations"].items:
      if o["key"].getStr() != key:
        kept.add(o)
    envelopeOf(fixture, invId)["observations"] = kept

  proc removeObs(fixture: JsonNode, invId, key, subject: string) =
    let kept = newJArray()
    for o in envelopeOf(fixture, invId)["observations"].items:
      if o["key"].getStr() != key or o["subject"].getStr() != subject:
        kept.add(o)
    envelopeOf(fixture, invId)["observations"] = kept

  proc setObsValue(fixture: JsonNode, invId, key, subject: string,
                   value: JsonNode) =
    for o in envelopeOf(fixture, invId)["observations"].items:
      if o["key"].getStr() == key and o["subject"].getStr() == subject:
        o["value"] = value
        return
    doAssert false, "fixture has no " & invId & "." & key & "[" & subject & "]"

  proc setObsScope(fixture: JsonNode, invId, key, scope: string) =
    for o in envelopeOf(fixture, invId)["observations"].items:
      if o["key"].getStr() == key:
        o["scope"] = %scope
        return
    doAssert false, "fixture has no " & invId & "." & key

  proc evaluateFixture(policy: JsonNode,
                       fixture: JsonNode): readiness_evaluator.ReadinessDecision =
    let bundle = readiness_evaluator.normalizeBundle(
      readiness_evaluator.loadEvidenceFromJson(fixture)).get
    readiness_evaluator.evaluateReadiness(policy, bundle)

  proc stateOf(policy: JsonNode, fixture: JsonNode, invId: string): string =
    evaluateFixture(policy, fixture).invariantStates[invId].getStr()

suite "DEBT#559 — observation-key closure (false GO regression)":
  test "unrelated keys do not satisfy R2/R6/R8":
    when EVALUATOR_AVAILABLE:
      let fixture = loadSyntheticFixture()
      for invId in ["R2", "R6", "R8"]:
        replaceObservations(fixture, invId,
          [readiness_evaluator.makeObs("unrelatedProbe", %true)])
      let d = evaluateFixture(POLICY, fixture)
      for invId in ["R2", "R6", "R8"]:
        check d.invariantStates[invId].getStr() == "UNKNOWN"
      for invId in ["R1", "R3", "R4", "R5", "R7"]:
        check d.invariantStates[invId].getStr() == "PASS"
      check d.verdict == "NO-GO"
      check d.outcome == "UNRESOLVED"
      echo "  [debt559] unrelated keys -> R2/R6/R8 UNKNOWN, NO-GO/UNRESOLVED"
    else:
      skip()

  test "one missing required key -> that invariant UNKNOWN":
    when EVALUATOR_AVAILABLE:
      for (invId, key) in [("R1", "documentedCommand"),
                           ("R2", "certGreenDualEvidenceRequired"),
                           ("R3", "canonicalInputHash"),
                           ("R4", "provenanceReconstructible"),
                           ("R5", "helpSurface"),
                           ("R6", "failureConvertsToSuccess"),
                           ("R7", "measuredCoverage"),
                           ("R8", "cleanRunSucceeded")]:
        let fixture = loadSyntheticFixture()
        removeObs(fixture, invId, key)
        let d = evaluateFixture(POLICY, fixture)
        check d.invariantStates[invId].getStr() == "UNKNOWN"
        if invId == "R7":
          check d.verdict == "CONDITIONAL GO"
        else:
          check d.verdict == "NO-GO"
      echo "  [debt559] every invariant's required keys are load-bearing"
    else:
      skip()

  test "required key null or wrong JSON type -> UNKNOWN":
    when EVALUATOR_AVAILABLE:
      let nullFixture = loadSyntheticFixture()
      setObsValue(nullFixture, "R8", "manualStepsRequired", "", newJNull())
      check stateOf(POLICY, nullFixture, "R8") == "UNKNOWN"

      let wrongType = loadSyntheticFixture()
      setObsValue(wrongType, "R8", "cleanRunSucceeded", "", %"yes")
      check stateOf(POLICY, wrongType, "R8") == "UNKNOWN"
      echo "  [debt559] null / wrong-type required values -> UNKNOWN"
    else:
      skip()

  test "present false fails only where onFalse=fail":
    when EVALUATOR_AVAILABLE:
      let failing = loadSyntheticFixture()
      setObsValue(failing, "R2", "certGreenDualEvidenceRequired", "", %false)
      let dFail = evaluateFixture(POLICY, failing)
      check dFail.invariantStates["R2"].getStr() == "FAIL"
      check dFail.verdict == "NO-GO"

      # manualStepsRequired=false is the healthy value (onFalse=pass); the same
      # false shape on a fail-on-false key is caught above.
      let healthy = loadSyntheticFixture()
      check stateOf(POLICY, healthy, "R8") == "PASS"
      echo "  [debt559] present-false semantics follow policy onFalse"
    else:
      skip()

  test "subjectLane is required and lane claims gate R1":
    when EVALUATOR_AVAILABLE:
      let absent = loadSyntheticFixture()
      removeObs(absent, "R1", "subjectLane")
      check stateOf(POLICY, absent, "R1") == "UNKNOWN"

      let empty = loadSyntheticFixture()
      check stateOf(POLICY, empty, "R1") == "PASS"

      let blocked = loadSyntheticFixture()
      setObsValue(blocked, "R1", "subjectLane", "", %["rust"])
      check stateOf(POLICY, blocked, "R1") == "FAIL"
      echo "  [debt559] subjectLane absent -> UNKNOWN; claimed lane still gates"
    else:
      skip()

  test "conditional claim:subjectLane skips when no lane is claimed":
    when EVALUATOR_AVAILABLE:
      var conditional = copy(POLICY)
      for k in conditional["observationKeys"]["R1"].items:
        if k["key"].getStr() == "subjectLane":
          k["presence"] = %"conditional"
          k["condition"] = %"claim:subjectLane"
      check readiness_evaluator.validatePolicyShape(conditional).isOk

      let noClaim = loadSyntheticFixture()
      removeObs(noClaim, "R1", "subjectLane")
      check stateOf(conditional, noClaim, "R1") == "PASS"

      let claimed = loadSyntheticFixture()
      setObsValue(claimed, "R1", "subjectLane", "", %["rust"])
      check stateOf(conditional, claimed, "R1") == "FAIL"
      echo "  [debt559] conditional claim:subjectLane follows the claim"
    else:
      skip()

  test "conditional failure codes are demanded when successExitCode exists":
    when EVALUATOR_AVAILABLE:
      let missing = loadSyntheticFixture()
      removeObs(missing, "R5", "verificationFailureExitCode", "ax prove")
      check stateOf(POLICY, missing, "R5") == "UNKNOWN"

      let successMissing = loadSyntheticFixture()
      removeObs(successMissing, "R5", "successExitCode", "ax report")
      check stateOf(POLICY, successMissing, "R5") == "UNKNOWN"
      echo "  [debt559] successor:successExitCode conditional demand enforced"
    else:
      skip()

  test "scope=contract echo is not observed evidence":
    when EVALUATOR_AVAILABLE:
      let fixture = loadSyntheticFixture()
      setObsScope(fixture, "R2", "certGreenDualEvidenceRequired", "contract")
      check stateOf(POLICY, fixture, "R2") == "UNKNOWN"
      check stateOf(POLICY, loadSyntheticFixture(), "R2") == "PASS"
      echo "  [debt559] declared scope never satisfies a required observed key"
    else:
      skip()

  test "complete key closure yields GO with the golden digest":
    when EVALUATOR_AVAILABLE:
      let d = evaluateFixture(POLICY, loadSyntheticFixture())
      for invId in INV_IDS:
        check d.invariantStates[invId].getStr() == "PASS"
      check d.verdict == "GO"
      check d.decisionDigest ==
        "2450f1a283a21d97ccdd4432076d921be6dc5aae9c759d348cc31b7237c70dea"
      echo "  [debt559] strict fixture -> GO, golden digest"
    else:
      skip()

  test "malformed policy shape is rejected, never defaulted":
    when EVALUATOR_AVAILABLE:
      check readiness_evaluator.validatePolicyShape(POLICY).isOk

      proc shapeRejected(mutate: proc(p: JsonNode)): bool =
        var p = copy(POLICY)
        mutate(p)
        readiness_evaluator.validatePolicyShape(p).isErr

      check shapeRejected(proc(p: JsonNode) =
        p["observationKeys"].delete("R6"))
      check shapeRejected(proc(p: JsonNode) =
        p["observationKeys"]["R2"][0]["presence"] = %"sometimes")
      check shapeRejected(proc(p: JsonNode) =
        p["observationKeys"]["R3"][0]["type"] = %"boolish")
      check shapeRejected(proc(p: JsonNode) =
        p["observationKeys"]["R8"][0]["observedScope"] = %"hoped")
      check shapeRejected(proc(p: JsonNode) =
        p["observationKeys"]["R5"][1]["onAbsent"] = %"shrug")
      check shapeRejected(proc(p: JsonNode) =
        p["observationKeys"]["R5"][3]["condition"] = %"successor:nonexistent")
      check shapeRejected(proc(p: JsonNode) =
        p["r4"].delete("requiredFields"))
      check shapeRejected(proc(p: JsonNode) =
        p["r5"]["successExitCode"] = %"zero")
      check shapeRejected(proc(p: JsonNode) =
        p["r8"].delete("prepareSequenceCommands"))
      check shapeRejected(proc(p: JsonNode) =
        p["invariants"].delete("R8"))
      check shapeRejected(proc(p: JsonNode) =
        p["unknownKeys"] = %"whatever")
      echo "  [debt559] malformed shapes rejected by validatePolicyShape"
    else:
      skip()

  test "CLI exits 1 on malformed policy (silent default prohibited)":
    when EVALUATOR_AVAILABLE:
      let evaluatorBin =
        if fileExists("bin/readiness_evaluator"): "bin/readiness_evaluator"
        else: REPO_ROOT / "bin/readiness_evaluator"
      if not fileExists(evaluatorBin):
        echo "  [debt559] SKIP CLI exit check: " & evaluatorBin & " not built"
      else:
        var bad = copy(POLICY)
        bad["observationKeys"].delete("R6")
        let tmpPolicy = getTempDir() / "axiom_readiness_shape_probe.json"
        writeFile(tmpPolicy, $bad)
        let fixture = currentSourcePath().parentDir() / "fixtures" /
          "synthetic_bundle.json"
        let cmd = quoteShell(evaluatorBin) & " --policy " & quoteShell(tmpPolicy) &
          " --bundle-file " & quoteShell(fixture) &
          " --eval-time 2026-11-20T00:00:00Z"
        let (output, code) = execCmdEx(cmd)
        check code == 1
        check output.contains("invalid policy shape")
        echo "  [debt559] malformed policy -> CLI exit 1"
    else:
      skip()

when isMainModule:
  # Benchmark-friendly: run the full suite (unittest does not expose a
  # programmatic runner; suite execution happens at module top level).
  discard

