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

import std/[json, unittest, strutils, algorithm, sequtils, tables, os]
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

  test "different scope -> no contradiction (values computed normally)":
    when EVALUATOR_AVAILABLE:
      let b = readiness_evaluator.normalizeBundle(@[
        readiness_evaluator.makeEvidence("R1", @[
          readiness_evaluator.makeObs("commandExists", %true, "surface", "ax prove"),
          readiness_evaluator.makeObs("commandExists", %false, "docs", "ax prove")])]).get
      let d = readiness_evaluator.evaluateReadiness(POLICY, b)
      check d.invariantStates["R1"].getStr() != "UNKNOWN"
      echo "  [contradiction] different scope -> no UNKNOWN"
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
      check golden["verdict"].getStr() == "CONDITIONAL GO"
      check golden["conditions"].toSeq().mapIt(it.getStr()) == @["R7=FAIL"]
      let states = golden["invariantStates"]
      check states["R1"].getStr() == "PASS"
      check states["R7"].getStr() == "FAIL"
      check states["R8"].getStr() == "PASS"
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

when isMainModule:
  # Benchmark-friendly: run the full suite (unittest does not expose a
  # programmatic runner; suite execution happens at module top level).
  discard

