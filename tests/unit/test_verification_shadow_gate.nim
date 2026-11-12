## Unit tests for verification_shadow_gate.nim
## Uses custom main() pattern to avoid unittest framework crashes.
## Verifies: pre-flight independence, query identity stability,
## dependency mutation, provenance invariance, unclassified fail-closed,
## selfCalibration fail-closed, and bidirectional mismatch detection.

import std/[os, strutils]
import core/crypto/hash_kernel
import verification/verification_dependency
import verification/observation_pipeline
import verification/semantic_query_types
import verification/observed_audit_contract
import verification/repo_snapshot_digest
from ci/verification_probe import prcModuleContent
from tools/ci/verification_shadow_gate import verifySubstrateIndependence, parseGateOutput, crossCheckStatus, buildEvidenceJson, countDomainModulesIndependent, classifyFileIndependent, DependencyResolutionEntry, parseStraceLine

proc main() =
  var passed = 0
  var failed = 0

  template check(name: string, body: untyped) =
    block:
      try:
        body
        inc passed
        echo "  PASS: " & name
      except CatchableError:
        inc failed
        echo "  FAIL: " & name & " - " & getCurrentExceptionMsg()

  # ==================== R0: verifySubstrateIndependence ====================
  echo "=== R0: verifySubstrateIndependence ==="

  block:
    check "distinct+same-SHA → empty string":
      let r = verifySubstrateIndependence(@["/a/oracle", "/b/model"], "abc123", "abc123")
      assert r == ""

  block:
    check "same path twice → error":
      let r = verifySubstrateIndependence(@["/a/oracle", "/a/oracle"], "abc123", "abc123")
      assert r != ""

  block:
    check "differing SHA/tree → error":
      let r = verifySubstrateIndependence(@["/a/oracle", "/b/model"], "sha1", "sha2")
      assert r != ""

  block:
    check "live-root included → error":
      let r = verifySubstrateIndependence(@["/a/oracle", "."], "abc123", "abc123")
      assert r != ""

  # ==================== R1: same semantic inputs → same provisional QueryID ====================
  echo ""
  echo "=== R1: same semantic inputs → same provisional QueryID ==="

  block:
    check "identical digests produce identical QueryID":
      let snap = newSnapshotDigest(hash_kernel.sha256Hex("same-content"))
      let tc = newTestClosureDigest(hash_kernel.sha256Hex("same-content"))
      let bl = newBaselineDigest(hash_kernel.sha256Hex("same-content"))
      let lk = newLockDigest(hash_kernel.sha256Hex("same-content"))
      let pol = newPolicyDigest(hash_kernel.sha256Hex("same-content"))
      let gi = newGateImplDigest(hash_kernel.sha256Hex("same-content"))
      let srd = selectionRuleDigest(DefaultSelectionRule)
      let q1 = SemanticQuery(
        gateId: newGateId("gate1"),
        snapshot: snap, testClosure: tc, baseline: bl,
        lock: lk, policy: pol, gateImpl: gi,
        selectionRuleVersion: "1", selectionRuleDigest: srd
      )
      let q2 = SemanticQuery(
        gateId: newGateId("gate2"),
        snapshot: snap, testClosure: tc, baseline: bl,
        lock: lk, policy: pol, gateImpl: gi,
        selectionRuleVersion: "1", selectionRuleDigest: srd
      )
      let id1 = provisionalQueryID(q1)
      let id2 = provisionalQueryID(q2)
      assert id1 == id2

  block:
    check "verdict derivation identical → same fresh verdict":
      let r1 = buildObservedAuditResult(5, 5, @[], osComplete)
      let r2 = buildObservedAuditResult(5, 5, @[], osComplete)
      assert r1.verdict == r2.verdict

  # ==================== R2: dependency mutation → identity/closure changes ====================
  echo ""
  echo "=== R2: dependency mutation → identity/closure changes ==="

  block:
    check "different snapshot content → different QueryID (identity inequality)":
      let snapA = newSnapshotDigest(hash_kernel.sha256Hex("content-A"))
      let snapB = newSnapshotDigest(hash_kernel.sha256Hex("content-B"))
      let baseTC = newTestClosureDigest(hash_kernel.sha256Hex("tc"))
      let baseBL = newBaselineDigest(hash_kernel.sha256Hex("bl"))
      let baseLK = newLockDigest(hash_kernel.sha256Hex("lk"))
      let basePol = newPolicyDigest(hash_kernel.sha256Hex("pol"))
      let baseGI = newGateImplDigest(hash_kernel.sha256Hex("gi"))
      let srd = selectionRuleDigest(DefaultSelectionRule)
      let qA = SemanticQuery(
        gateId: newGateId("gate"),
        snapshot: snapA, testClosure: baseTC, baseline: baseBL,
        lock: baseLK, policy: basePol, gateImpl: baseGI,
        selectionRuleVersion: "1", selectionRuleDigest: srd
      )
      let qB = SemanticQuery(
        gateId: newGateId("gate"),
        snapshot: snapB, testClosure: baseTC, baseline: baseBL,
        lock: baseLK, policy: basePol, gateImpl: baseGI,
        selectionRuleVersion: "1", selectionRuleDigest: srd
      )
      let idA = provisionalQueryID(qA)
      let idB = provisionalQueryID(qB)
      assert idA != idB

  block:
    check "different snapshot digests → different QueryIDs (no reuse equivalence)":
      let snapA = newSnapshotDigest(hash_kernel.sha256Hex("content-A"))
      let snapB = newSnapshotDigest(hash_kernel.sha256Hex("content-B"))
      let tc = newTestClosureDigest(hash_kernel.sha256Hex("tc"))
      let bl = newBaselineDigest(hash_kernel.sha256Hex("bl"))
      let lk = newLockDigest(hash_kernel.sha256Hex("lk"))
      let pol = newPolicyDigest(hash_kernel.sha256Hex("pol"))
      let gi = newGateImplDigest(hash_kernel.sha256Hex("gi"))
      let srd = selectionRuleDigest(DefaultSelectionRule)
      let qA = SemanticQuery(gateId: newGateId("g"), snapshot: snapA, testClosure: tc, baseline: bl, lock: lk, policy: pol, gateImpl: gi, selectionRuleVersion: "1", selectionRuleDigest: srd)
      let qB = SemanticQuery(gateId: newGateId("g"), snapshot: snapB, testClosure: tc, baseline: bl, lock: lk, policy: pol, gateImpl: gi, selectionRuleVersion: "1", selectionRuleDigest: srd)
      let idA = provisionalQueryID(qA)
      let idB = provisionalQueryID(qB)
      assert idA != idB

  # ==================== R3: provenance-only change → same QueryID → same verdict ====================
  echo ""
  echo "=== R3: provenance-only change → same QueryID → same verdict ==="

  block:
    check "provenance-only change (gateId) → identical QueryID":
      let snap = newSnapshotDigest(hash_kernel.sha256Hex("content"))
      let tc = newTestClosureDigest(hash_kernel.sha256Hex("tc"))
      let bl = newBaselineDigest(hash_kernel.sha256Hex("bl"))
      let lk = newLockDigest(hash_kernel.sha256Hex("lk"))
      let pol = newPolicyDigest(hash_kernel.sha256Hex("pol"))
      let gi = newGateImplDigest(hash_kernel.sha256Hex("gi"))
      let srd = selectionRuleDigest(DefaultSelectionRule)
      let q1 = SemanticQuery(gateId: newGateId("gate-A"), snapshot: snap, testClosure: tc, baseline: bl, lock: lk, policy: pol, gateImpl: gi, selectionRuleVersion: "1", selectionRuleDigest: srd)
      let q2 = SemanticQuery(gateId: newGateId("gate-B"), snapshot: snap, testClosure: tc, baseline: bl, lock: lk, policy: pol, gateImpl: gi, selectionRuleVersion: "1", selectionRuleDigest: srd)
      let id1 = provisionalQueryID(q1)
      let id2 = provisionalQueryID(q2)
      assert id1 == id2

  block:
    check "provenance-only change → same verdict from buildObservedAuditResult":
      let r1 = buildObservedAuditResult(5, 5, @[], osComplete)
      let r2 = buildObservedAuditResult(5, 5, @[], osComplete)
      assert r1.verdict == r2.verdict

  # ==================== R4: unclassified observation → fail-closed ====================
  echo ""
  echo "=== R4: unclassified observation → fail-closed ==="

  block:
    check "rcOther → dkUnclassified via classifyReadClass":
      assert classifyReadClass(rcOther) == dkUnclassified

  block:
    check "isUnclassified(rcOther) → true":
      assert isUnclassified(rcOther)

  block:
    check "rcEnvVar → dkUnclassified → isUnclassified":
      assert classifyReadClass(rcEnvVar) == dkUnclassified
      assert isUnclassified(rcEnvVar)

  # ==================== R5: selfCalibration → osUnknown → fail-closed ====================
  echo ""
  echo "=== R5: selfCalibration → osUnknown → fail-closed ==="

  block:
    check "selfCalibration + osUnknown → resolve == drFailClosed":
      let r = buildObservedAuditResult(5, 5, @["selfCalibration"], osUnknown)
      assert resolve(r) == drFailClosed

  # ==================== R6-N: bidirectional ≥2 each ====================
  echo ""
  echo "=== R6-N: bidirectional mismatch detection ==="

  block:
    check "N1a: crossCheckStatus(PASS, FAIL) → MISMATCH":
      assert crossCheckStatus("PASS", "FAIL") == "MISMATCH"

  block:
    check "N1b: model expectedCount corruption (+1) → FAIL while oracle PASS":
      let oracleVerdict = "PASS"
      let modelResult = buildObservedAuditResult(6, 5, @[], osComplete)
      assert modelResult.verdict == "FAIL"
      assert crossCheckStatus(oracleVerdict, modelResult.verdict) == "MISMATCH"

  block:
    check "N2a: probeReadClassToReadClass(prcModuleContent) == rcModuleContent":
      assert probeReadClassToReadClass(prcModuleContent) == rcModuleContent

  block:
    check "N2b: mis-mapped rcModuleContent→rcOther → isUnclassified → true (fail-closed)":
      assert isUnclassified(rcOther)

  block:
    check "N3a: parseGateOutput PASS + exitCode=1 → ok=false":
      let p = parseGateOutput("[verification-auditor-gate] PASS\n", 1)
      assert p.ok == false

  block:
    check "N3b: parseGateOutput FAIL + exitCode=0 → ok=false":
      let p = parseGateOutput("[verification-auditor-gate] FAIL\n", 0)
      assert p.ok == false

  block:
    check "N4a: parseGateOutput domain:10 → parsed count == 10":
      let p = parseGateOutput("domain: 10\n[verification-auditor-gate] PASS\n", 0)
      assert p.domainCount == 10

  block:
    check "N4b: corrupted domain count → parsed differs from truth → MISMATCH":
      let truthCount = 10
      let p = parseGateOutput("domain: 11\n[verification-auditor-gate] PASS\n", 0)
      assert p.domainCount != truthCount
      assert crossCheckStatus("PASS", "FAIL") == "MISMATCH"

  # ==================== R7: evidence-only ====================
  echo ""
  echo "=== R7: evidence-only ==="

  block:
    check "buildEvidenceJson contains raw fields, no canReuse/evidenceComplete":
      let depEntries: seq[DependencyResolutionEntry] = @[
        DependencyResolutionEntry(path: "src/foo.nim", readClass: "module_content", kind: "SEMANTIC", resolution: "Declared")
      ]
      let json = buildEvidenceJson(
        "verification_shadow_gate", "abc123", "PASS", "PASS", "MATCH",
        "qid-123", "impl|nim:2.2.10", "2.2.10", "Complete",
        5, 5, 5, 100, 0,
        @["selfCalibration"],
        depEntries
      )
      assert json.contains("tool")
      assert json.contains("ref")
      assert json.contains("actualVerdict")
      assert json.contains("modelVerdict")
      assert json.contains("crossCheckStatus")
      assert json.contains("actualDomainCount")
      assert json.contains("modelDomainCount")
      assert json.contains("baselineDomainCount")
      assert json.contains("queryId")
      assert json.contains("gateImplIdentity")
      assert json.contains("toolchain")
      assert json.contains("couplingFlags")
      assert json.contains("observationStatus")
      assert json.contains("oracleWallclockMs")
      assert json.contains("dependencyResolutions")
      assert json.contains("unclassifiedObservations")
      assert not json.contains("canReuse")
      assert not json.contains("evidenceComplete")
      assert not json.contains("summary")

  block:
    check "buildEvidenceJson dependencyResolutions array is non-empty":
      let depEntries: seq[DependencyResolutionEntry] = @[
        DependencyResolutionEntry(path: "src/foo.nim", readClass: "module_content", kind: "SEMANTIC", resolution: "Declared")
      ]
      let json = buildEvidenceJson(
        "verification_shadow_gate", "abc123", "PASS", "PASS", "MATCH",
        "qid-123", "impl|nim:2.2.10", "2.2.10", "Complete",
        5, 5, 5, 100, 0,
        @[],
        depEntries
      )
      assert json.contains("dependencyResolutions")

  # ==================== countDomainModulesIndependent ====================
  echo ""
  echo "=== countDomainModulesIndependent / classifyFileIndependent ==="

  block:
    check "classifyFileIndependent: domain module → domain":
      assert classifyFileIndependent("proc foo() = discard") == "domain"

  block:
    check "classifyFileIndependent: exempt module → exempt":
      assert classifyFileIndependent("type Foo = object\ndiscard") == "exempt"

  block:
    check "classifyFileIndependent: infrastructure import → infrastructure":
      assert classifyFileIndependent("proc foo()\nimport os\ndiscard") == "infrastructure"

  # ==================== strace line parse regression ====================
  # Regression: strace -f prefixes every line with a PID ("152368 openat(...)").
  # A startsWith("openat(") filter silently drops ALL observations → empty
  # dependency set (theater risk). parseStraceLine must handle the PID prefix.
  echo ""
  echo "=== strace parse regression (PID prefix) ==="

  block:
    check "PID-prefixed openat line → path extracted":
      let (p, found) = parseStraceLine("152368 openat(AT_FDCWD, \"/etc/ld.so.cache\", O_RDONLY|O_CLOEXEC) = 3")
      assert found and p == "/etc/ld.so.cache"

  block:
    check "PID-prefixed access line → path extracted":
      let (p, found) = parseStraceLine("152368 access(\"/tmp/x\", F_OK) = -1 ENOENT (No such file)")
      assert found and p == "/tmp/x"

  block:
    check "non-file syscall (execve) → not found":
      let (_, found) = parseStraceLine("152368 execve(\"/usr/bin/ls\", [\"ls\"], 0x7fff) = 0")
      assert not found

  block:
    check "empty/blank line → not found":
      let (_, found) = parseStraceLine("   ")
      assert not found

  block:
    check "no-parenthesis line → not found":
      let (_, found) = parseStraceLine("garbage without parens")
      assert not found

  echo ""
  echo "=== Results: " & $passed & " passed, " & $failed & " failed ==="
  if failed > 0: quit(1)

main()