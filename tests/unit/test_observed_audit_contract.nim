## Unit tests for observed_audit_contract.nim — Observed Audit Contract.
## Uses custom main() pattern to avoid unittest framework crashes.
## Verifies: classifyReadClass contract, ObservedAuditContract construction,
## resolve fail-closed, selfCalibration coupling, domain mismatch detection,
## probe→ReadClass adapter exhaustiveness, and Unknown reuse prohibition.

import std/[os, strutils, algorithm]
import core/crypto/hash_kernel
import verification/verification_dependency
import verification/observation_pipeline
import verification/semantic_query_types
import verification/observed_audit_contract
import ci/verification_probe

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

  # -----------------------------------------------------------------
  echo "=== classifyReadClass contract sanity ==="

  block:
    check "module_content -> SEMANTIC":
      assert classifyReadClass(rcModuleContent) == dkSemantic
    check "baseline -> SEMANTIC":
      assert classifyReadClass(rcBaseline) == dkSemantic
    check "module_existence -> UNCLASSIFIED":
      assert classifyReadClass(rcModuleExistence) == dkUnclassified
    check "env_var -> UNCLASSIFIED":
      assert classifyReadClass(rcEnvVar) == dkUnclassified
    check "cwd -> UNCLASSIFIED":
      assert classifyReadClass(rcCwd) == dkUnclassified
    check "compiler_subprocess -> UNCLASSIFIED":
      assert classifyReadClass(rcCompilerSubprocess) == dkUnclassified
    check "other -> UNCLASSIFIED":
      assert classifyReadClass(rcOther) == dkUnclassified
    check "commit_id -> PROVENANCE":
      assert classifyReadClass(rcCommitId) == dkProvenance
    check "timestamp -> INTERNAL":
      assert classifyReadClass(rcTimestamp) == dkInternal
    check "gate_output -> OUTPUT":
      assert classifyReadClass(rcGateOutput) == dkOutput

  # -----------------------------------------------------------------
  echo "=== ObservedAuditContract construction maps each input ==="

  block:
    let snap = newSnapshotDigest("aa" & repeat('0', 61))
    let base = newBaselineDigest("bb" & repeat('0', 61))
    let pol = newPolicyDigest("cc" & repeat('0', 61))
    let impl = newGateImplDigest("dd" & repeat('0', 61))
    let contract = newObservedAuditContract(
      snap, base, pol, impl, "nim-2.2.10", @["selfCalibration"], true
    )
    check "subjectSnapshot maps correctly":
      assert contract.subjectSnapshot == snap
    check "baseline maps correctly":
      assert contract.baseline == base
    check "gatePolicy maps correctly":
      assert contract.gatePolicy == pol
    check "gateImplementation maps correctly":
      assert contract.gateImplementation == impl
    check "toolchain maps correctly":
      assert contract.toolchain == "nim-2.2.10"
    check "couplingFlags maps correctly":
      assert contract.couplingFlags == @["selfCalibration"]
    check "provisional marker is true":
      assert contract.provisional == true

  block:
    let snap = newSnapshotDigest("snap1")
    let base = newBaselineDigest("base1")
    let pol = newPolicyDigest("pol1")
    let impl = newGateImplDigest("impl1")
    let contract = newObservedAuditContract(snap, base, pol, impl, "nim-2.2.10")
    check "default couplingFlags is empty":
      assert contract.couplingFlags == @[]
    check "default provisional is true":
      assert contract.provisional == true

  # -----------------------------------------------------------------
  echo "=== ObservedAuditInput enum classification ==="

  block:
    check "oaiSubjectSnapshot -> dkSemantic":
      assert classifyInput(oaiSubjectSnapshot) == dkSemantic
    check "oaiBaseline -> dkSemantic":
      assert classifyInput(oaiBaseline) == dkSemantic
    check "oaiGatePolicy -> dkSemantic":
      assert classifyInput(oaiGatePolicy) == dkSemantic
    check "oaiGateImplementation -> dkSemantic":
      assert classifyInput(oaiGateImplementation) == dkSemantic
    check "oaiToolchain -> dkProvenance":
      assert classifyInput(oaiToolchain) == dkProvenance

  # -----------------------------------------------------------------
  echo "=== resolve fail-closed: osUnknown/osUnclassified/osIncomplete ==="

  block:
    let resUnknown = newObservedAuditResult(10, 10, "PASS", @[], osUnknown)
    check "osUnknown -> drFailClosed":
      assert resolve(resUnknown) == drFailClosed
    check "osUnknown -> NOT reusable":
      assert not isReusable(resUnknown)

  block:
    let resUnclassified = newObservedAuditResult(10, 10, "PASS", @[], osUnclassified)
    check "osUnclassified -> drFailClosed":
      assert resolve(resUnclassified) == drFailClosed
    check "osUnclassified -> NOT reusable":
      assert not isReusable(resUnclassified)

  block:
    let resIncomplete = newObservedAuditResult(10, 10, "PASS", @[], osIncomplete)
    check "osIncomplete -> drFailClosed":
      assert resolve(resIncomplete) == drFailClosed
    check "osIncomplete -> NOT reusable":
      assert not isReusable(resIncomplete)

  block:
    let resComplete = newObservedAuditResult(10, 10, "PASS", @[], osComplete)
    check "osComplete + PASS -> drDeclared":
      assert resolve(resComplete) == drDeclared
    check "osComplete + PASS -> reusable":
      assert isReusable(resComplete)

  block:
    let resCompleteFail = newObservedAuditResult(10, 10, "FAIL", @[], osComplete)
    check "osComplete + FAIL -> drRecompute":
      assert resolve(resCompleteFail) == drRecompute
    check "osComplete + FAIL -> NOT reusable":
      assert not isReusable(resCompleteFail)

  # -----------------------------------------------------------------
  echo "=== selfCalibration coupling flag -> NOT reusable ==="

  block:
    let resSelfCal = newObservedAuditResult(10, 10, "PASS", @["selfCalibration"], osUnknown)
    check "selfCalibration + osUnknown -> NOT reusable":
      assert not isReusable(resSelfCal)
    check "selfCalibration couplingFlags present":
      assert "selfCalibration" in resSelfCal.couplingFlags

  block:
    let resNoCal = newObservedAuditResult(10, 10, "PASS", @[], osComplete)
    check "no selfCalibration + osComplete -> reusable":
      assert isReusable(resNoCal)

  # -----------------------------------------------------------------
  echo "=== domain count mismatch -> verdict FAIL ==="

  block:
    let resMatch = newObservedAuditResult(10, 10, "PASS", @[], osComplete)
    check "match -> verdict PASS":
      assert resMatch.verdict == "PASS"
    let resMismatch = newObservedAuditResult(10, 15, "FAIL", @[], osComplete)
    check "mismatch -> verdict FAIL":
      assert resMismatch.verdict == "FAIL"
    check "observedDomainCount != expectedDomainCount":
      assert resMismatch.observedDomainCount != resMismatch.expectedDomainCount

  # -----------------------------------------------------------------
  echo "=== probe→ReadClass adapter identity-correct and exhaustive ==="

  block:
    # Verify all 15 ProbeReadClass values map to the corresponding ReadClass
    check "prcModuleContent -> rcModuleContent":
      assert probeReadClassToReadClass(prcModuleContent) == rcModuleContent
    check "prcModuleExistence -> rcModuleExistence":
      assert probeReadClassToReadClass(prcModuleExistence) == rcModuleExistence
    check "prcTestGateway -> rcTestGateway":
      assert probeReadClassToReadClass(prcTestGateway) == rcTestGateway
    check "prcManualFeature -> rcManualFeature":
      assert probeReadClassToReadClass(prcManualFeature) == rcManualFeature
    check "prcBaseline -> rcBaseline":
      assert probeReadClassToReadClass(prcBaseline) == rcBaseline
    check "prcLockFile -> rcLockFile":
      assert probeReadClassToReadClass(prcLockFile) == rcLockFile
    check "prcPolicy -> rcPolicy":
      assert probeReadClassToReadClass(prcPolicy) == rcPolicy
    check "prcCommitId -> rcCommitId":
      assert probeReadClassToReadClass(prcCommitId) == rcCommitId
    check "prcTimestamp -> rcTimestamp":
      assert probeReadClassToReadClass(prcTimestamp) == rcTimestamp
    check "prcHistory -> rcHistory":
      assert probeReadClassToReadClass(prcHistory) == rcHistory
    check "prcGateOutput -> rcGateOutput":
      assert probeReadClassToReadClass(prcGateOutput) == rcGateOutput
    check "prcEnvVar -> rcEnvVar":
      assert probeReadClassToReadClass(prcEnvVar) == rcEnvVar
    check "prcCwd -> rcCwd":
      assert probeReadClassToReadClass(prcCwd) == rcCwd
    check "prcCompilerSubprocess -> rcCompilerSubprocess":
      assert probeReadClassToReadClass(prcCompilerSubprocess) == rcCompilerSubprocess
    check "prcOther -> rcOther":
      assert probeReadClassToReadClass(prcOther) == rcOther

  block:
    # Exhaustiveness: every ProbeReadClass maps to a distinct ReadClass, none dropped, none added
    let allPrc = [prcModuleContent, prcModuleExistence, prcTestGateway, prcManualFeature,
                  prcBaseline, prcLockFile, prcPolicy, prcCommitId, prcTimestamp,
                  prcHistory, prcGateOutput, prcEnvVar, prcCwd, prcCompilerSubprocess, prcOther]
    let allRc = [rcModuleContent, rcModuleExistence, rcTestGateway, rcManualFeature,
                 rcBaseline, rcLockFile, rcPolicy, rcCommitId, rcTimestamp,
                 rcHistory, rcGateOutput, rcEnvVar, rcCwd, rcCompilerSubprocess, rcOther]
    check "adapter covers all 15 ProbeReadClass values":
      assert allPrc.len == 15
    check "adapter covers all 15 ReadClass values":
      assert allRc.len == 15
    var mapped: seq[ReadClass] = @[]
    for prc in allPrc:
      mapped.add(probeReadClassToReadClass(prc))
    mapped.sort(proc(a, b: ReadClass): int =
      if a.ord < b.ord: -1 elif a.ord > b.ord: 1 else: 0)
    check "adapter is exhaustive — no dropped or added values":
      assert mapped == allRc

  # -----------------------------------------------------------------
  echo "=== Unknown -> fail-closed reuse prohibition ==="

  block:
    let resUnknown = newObservedAuditResult(5, 5, "PASS", @[], osUnknown)
    check "Unknown observationStatus -> drFailClosed":
      assert resolve(resUnknown) == drFailClosed
    check "Unknown -> reuse prohibited (not drDeclared)":
      assert resolve(resUnknown) != drDeclared
    check "Unknown -> isReusable is false":
      assert not isReusable(resUnknown)

  block:
    let resUnclassified = newObservedAuditResult(5, 5, "PASS", @[], osUnclassified)
    check "Unclassified observationStatus -> drFailClosed":
      assert resolve(resUnclassified) == drFailClosed
    check "Unclassified -> reuse prohibited":
      assert not isReusable(resUnclassified)

  # -----------------------------------------------------------------
  echo "=== buildObservedAuditResult derives verdict ==="

  block:
    let res = buildObservedAuditResult(10, 10, @[], osComplete)
    check "buildObservedAuditResult equal counts -> PASS":
      assert res.verdict == "PASS"
    check "buildObservedAuditResult observedDomainCount correct":
      assert res.observedDomainCount == 10
    check "buildObservedAuditResult expectedDomainCount correct":
      assert res.expectedDomainCount == 10

  block:
    let res = buildObservedAuditResult(10, 15, @[], osComplete)
    check "buildObservedAuditResult mismatch -> FAIL":
      assert res.verdict == "FAIL"

  # -----------------------------------------------------------------
  echo "=== Results: " & $passed & " passed, " & $failed & " failed ==="
  if failed > 0: quit(1)

main()
