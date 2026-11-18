## test_fresh_prove_verdict.nim — the four-state projection contract
## (VS-AUTH-FRESH observation lane).
##
## These tests pin the honest mapping: a bare `failed` row is UNKNOWN, never
## REFUTED; NOT_REQUIRED alone is UNKNOWN, never OUT_OF_SCOPE; reuse can never
## satisfy a required unit; and PROVED additionally requires a complete
## closure, a declared scope classification, and a subject SHA.

import std/[json, strutils, unittest]
import tools/ci/fresh_prove_verdict

const
  SubjectSha = "0123456789abcdef0123456789abcdef01234567"
  UnitId = "m.nim::f"

proc freshMarker(fresh = true): JsonNode =
  var bypass = newJArray()
  if fresh:
    bypass.add(%"vault-verified-set")
  %*{"contract": "axiom.fresh-prove.v1", "fresh": fresh,
     "reuseBypass": bypass, "authoritative": false}

proc unit(decision = "REQUIRED"; outcome = "SATISFIED";
          source = "FRESH"; consistency = "CONSISTENT";
          unitId = UnitId): JsonNode =
  %*{"unitId": unitId, "requirementDecision": decision,
     "verificationOutcome": outcome, "consistency": consistency,
     "executionEvidence": "ATTEMPTED", "satisfactionSource": source}

proc makeState(units: seq[JsonNode]; marker: JsonNode;
               closureComplete = true; runVerdict = "PASS";
               verificationComplete = true;
               declared: seq[string] = @[UnitId];
               candidates: seq[JsonNode] = @[];
               eligibility: JsonNode = nil;
               nodeReports: JsonNode = nil;
               scopeContract: JsonNode = nil): JsonNode =
  var accounting = newJObject()
  accounting["units"] = %units
  var required = 0
  var satisfied = 0
  for u in units:
    if u{"requirementDecision"}.getStr() == "REQUIRED":
      inc required
    if u{"verificationOutcome"}.getStr() == "SATISFIED":
      inc satisfied
  accounting["requiredCount"] = %required
  accounting["satisfiedCount"] = %satisfied
  accounting["unsatisfiedCount"] = %0
  accounting["pendingCount"] = %0
  accounting["contestedCount"] = %0
  accounting["notAttemptedCount"] = %0
  accounting["notRequiredCount"] = %0
  accounting["proofFailedCount"] = %0
  accounting["freshExecutionCount"] = %required
  accounting["satisfiedByFresh"] = %satisfied
  accounting["satisfiedByReused"] = %0
  accounting["unresolvedDecisionCount"] = %0
  result = %*{
    "schemaVersion": "axiom.report.v1",
    "executionIdentity": {
      "verifierBuildId": "build-1",
      "toolchainIdentity": "nim-test",
      "executionConfigDigest": "cfg-1",
      "executionBundleFingerprint": "bundle-1",
      "executionEpoch": "epoch-1"},
    "freshness": marker,
    "runAccounting": accounting,
    "closure": {
      "closureComplete": closureComplete,
      "requiredCount": required,
      "completedCount": satisfied,
      "kernelScopeSize": 1,
      "universeCount": required},
    "runOutcome": {
      "verdict": runVerdict,
      "verificationComplete": verificationComplete},
    "canonicalRunDigest": "run-digest-1",
    "nodeReports": (if nodeReports.isNil: newJArray() else: nodeReports),
    "declaredRequired": %declared,
    "census": {"candidates": (if candidates.len == 0: newJArray() else: %candidates)},
    "eligibility": (if eligibility.isNil:
        newJObject() else: eligibility)}
  if not scopeContract.isNil:
    result["scopeContract"] = scopeContract
  if eligibility.isNil:
    result["eligibility"][UnitId] = %"elProofCandidate"

proc scopeLock(symbols: seq[string]): JsonNode =
  %*{"kernel_total": symbols.len, "kernel_symbols": symbols}

proc verdictOf(state: JsonNode; scope: JsonNode): JsonNode =
  projectVerdict(state, scope, "scope-digest", SubjectSha, "tree-sha")

proc reasonsOf(v: JsonNode): seq[string] =
  for r in v{"reasons"}.elems:
    result.add(r.getStr())

suite "fresh verdict — four-state mapping":
  test "all required units fresh and fully classified → PROVED":
    let state = makeState(@[unit()], freshMarker())
    let v = verdictOf(state, scopeLock(@[UnitId]))
    check v{"verdict"}.getStr() == "PROVED"
    check v{"exitCode"}.getInt() == 0
    check v{"checkConclusion"}.getStr() == "success"
    check v{"counts"}{"proved"}.getInt() == 1

  test "REUSED satisfaction never proves — UNKNOWN + contract failure":
    var state = makeState(@[unit(source = "REUSED")], freshMarker())
    state["runAccounting"]["satisfiedByReused"] = %1
    let v = verdictOf(state, scopeLock(@[UnitId]))
    check v{"verdict"}.getStr() == "UNKNOWN"
    check "satisfied-by-reuse" in reasonsOf(v)
    check "satisfied-by-reused-nonzero" in reasonsOf(v)
    check v{"checkConclusion"}.getStr() == "failure"

  test "bare failed row is UNKNOWN, not REFUTED":
    var state = makeState(@[unit(outcome = "UNSATISFIED", source = "NONE")],
      freshMarker())
    state["runAccounting"]["unsatisfiedCount"] = %1
    state["runAccounting"]["satisfiedCount"] = %0
    state["runOutcome"]["verdict"] = %"FAIL"
    state["runOutcome"]["verificationComplete"] = %false
    let v = verdictOf(state, scopeLock(@[UnitId]))
    check v{"verdict"}.getStr() == "UNKNOWN"
    check "unsatisfied-without-refutation-witness" in reasonsOf(v)
    check v{"counts"}{"refuted"}.getInt() == 0
    check v{"checkConclusion"}.getStr() == "neutral"

  test "machine-readable counterexample row → REFUTED":
    var state = makeState(@[unit(outcome = "UNSATISFIED", source = "NONE")],
      freshMarker())
    state["runAccounting"]["unsatisfiedCount"] = %1
    state["runAccounting"]["satisfiedCount"] = %0
    state["nodeReports"] = %*[{"nodeId": UnitId, "status": "failed",
      "counterexample": {"input": "x=0", "expected": "1", "actual": "0"}}]
    let v = verdictOf(state, scopeLock(@[UnitId]))
    check v{"verdict"}.getStr() == "REFUTED"
    check v{"exitCode"}.getInt() == 1
    check v{"checkConclusion"}.getStr() == "failure"

  test "NOT_REQUIRED alone is UNKNOWN; explicit scope contract is OUT_OF_SCOPE":
    let bare = makeState(@[unit(decision = "NOT_REQUIRED", outcome = "PENDING",
      source = "NONE")], freshMarker())
    let vBare = verdictOf(bare, scopeLock(@[UnitId]))
    check vBare{"verdict"}.getStr() == "UNKNOWN"
    check "not-required-without-scope-contract" in reasonsOf(vBare)

    let declared = makeState(@[unit(decision = "NOT_REQUIRED",
      outcome = "PENDING", source = "NONE")], freshMarker(),
      scopeContract = %*{"outOfScope": [UnitId]})
    let vDeclared = verdictOf(declared, scopeLock(@[UnitId]))
    check vDeclared{"counts"}{"outOfScope"}.getInt() == 1
    check vDeclared{"verdict"}.getStr() == "UNKNOWN"

  test "absent freshness marker cannot prove":
    let state = makeState(@[unit()], newJObject())
    let v = verdictOf(state, scopeLock(@[UnitId]))
    check v{"verdict"}.getStr() == "UNKNOWN"
    check "freshness-marker-absent" in reasonsOf(v)
    check v{"checkConclusion"}.getStr() == "failure"

  test "unclassified scope symbol blocks PROVED":
    let state = makeState(@[unit()], freshMarker())
    let v = verdictOf(state, scopeLock(@[UnitId, "m.nim::other"]))
    check v{"verdict"}.getStr() == "UNKNOWN"
    check "scope-coverage-incomplete" in reasonsOf(v)
    check v{"coverage"}{"missing"}.len == 1

  test "incomplete closure blocks PROVED":
    let state = makeState(@[unit()], freshMarker(), closureComplete = false)
    let v = verdictOf(state, scopeLock(@[UnitId]))
    check v{"verdict"}.getStr() == "UNKNOWN"
    check "closure-incomplete" in reasonsOf(v)

  test "subject SHA is required for PROVED":
    let state = makeState(@[unit()], freshMarker())
    let v = projectVerdict(state, scopeLock(@[UnitId]), "scope-digest", "", "")
    check v{"verdict"}.getStr() == "UNKNOWN"
    check "subject-sha-absent" in reasonsOf(v)

  test "census classification counts toward coverage":
    let state = makeState(@[unit()], freshMarker(),
      declared = @[UnitId],
      candidates = @[%*{"modulePath": "m.nim", "functionName": "other",
                        "eligibility": "elNoObligation"}])
    let v = verdictOf(state, scopeLock(@[UnitId, "m.nim::other"]))
    check v{"coverage"}{"complete"}.getBool() == true

suite "fresh verdict — canonical evidence":
  test "same inputs with different provenance → same canonical digest":
    var a = makeState(@[unit()], freshMarker())
    var b = makeState(@[unit()], freshMarker())
    a["provenance"] = %*{"runId": "1", "attempt": "1"}
    b["provenance"] = %*{"runId": "2", "attempt": "7"}
    a["executionStats"] = %*{"totalWallTimeMs": 1000}
    b["executionStats"] = %*{"totalWallTimeMs": 9999}
    let va = verdictOf(a, scopeLock(@[UnitId]))
    let vb = verdictOf(b, scopeLock(@[UnitId]))
    check va{"canonicalEvidenceDigest"}.getStr() ==
      vb{"canonicalEvidenceDigest"}.getStr()
    check va{"provenance"}{"runId"}.getStr() == "1"
    check vb{"provenance"}{"runId"}.getStr() == "2"

  test "changed unit outcome changes the canonical digest":
    var a = makeState(@[unit()], freshMarker())
    let b = makeState(@[unit(outcome = "PENDING", source = "NONE")],
      freshMarker())
    let da = verdictOf(a, scopeLock(@[UnitId])){"canonicalEvidenceDigest"}.getStr()
    let db = verdictOf(b, scopeLock(@[UnitId])){"canonicalEvidenceDigest"}.getStr()
    check da != db

  test "exit code and conclusion are functions of the verdict":
    check exitCodeOf("PROVED") == 0
    check exitCodeOf("REFUTED") == 1
    check exitCodeOf("UNKNOWN") == 3
    check checkConclusionOf("UNKNOWN", 0) == "neutral"
    check checkConclusionOf("UNKNOWN", 1) == "failure"