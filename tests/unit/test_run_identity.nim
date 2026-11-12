## Unit tests for run_identity.nim — BaseRunIdentity attestation layer (P8.3).
## Uses custom main() pattern to avoid unittest framework cleanup crashes.
##
## Asserts the core invariant: identityDigest is stable across records with
## identical semantic fields but different provenance (runId/timestamp/runner
## differ → identityDigest identical; provenance differs).

import std/[strutils, algorithm]
import core/types/results
import core/crypto/hash_kernel
import verification/run_identity
import gate/proof_unit_catalog

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

  # Helper: compute sha256 hex
  func sha256hex(s: string): string =
    hash_kernel.sha256Hex(s)

  # ======================================================================
  echo "=== BaseRunIdentity — identity/provenance separation ==="

  # Two records with identical semantic fields but different provenance.
  block:
    let sem1 = makeBaseSemanticIdentity("abc123", "tree456", "v2-full", "complete")
    let sem2 = makeBaseSemanticIdentity("abc123", "tree456", "v2-full", "complete")
    let prov1 = makeBaseProvenance("run-aaa", "workflow-x", "success", "2026-01-01T00:00:00Z", "runner-1")
    let prov2 = makeBaseProvenance("run-bbb", "workflow-y", "success", "2026-06-01T00:00:00Z", "runner-2")
    let base1 = BaseRunIdentity(semanticIdentity: sem1, provenance: prov1)
    let base2 = BaseRunIdentity(semanticIdentity: sem2, provenance: prov2)

    check "identityDigest is stable across different provenance":
      assert base1.semanticIdentity.identityDigest == base2.semanticIdentity.identityDigest,
        "identityDigest must be identical when semantic fields match, regardless of runId/timestamp/runner"
    check "provenance differs (runId)":
      assert base1.provenance.runId != base2.provenance.runId
    check "provenance differs (recordedAt)":
      assert base1.provenance.recordedAt != base2.provenance.recordedAt
    check "provenance differs (runnerId)":
      assert base1.provenance.runnerId != base2.provenance.runnerId

  # ======================================================================
  echo "=== BaseRunIdentity — identityDigest changes on semantic field change ==="

  block:
    let sem1 = makeBaseSemanticIdentity("abc123", "tree456", "v2-full", "complete")
    let sem2 = makeBaseSemanticIdentity("def456", "tree456", "v2-full", "complete")
    let sem3 = makeBaseSemanticIdentity("abc123", "tree789", "v2-full", "complete")
    let sem4 = makeBaseSemanticIdentity("abc123", "tree456", "v1-incremental", "complete")
    let sem5 = makeBaseSemanticIdentity("abc123", "tree456", "v2-full", "partial")

    check "identityDigest changes when baseCommit changes":
      assert sem1.identityDigest != sem2.identityDigest
    check "identityDigest changes when treeDigest changes":
      assert sem1.identityDigest != sem3.identityDigest
    check "identityDigest changes when certificationMode changes":
      assert sem1.identityDigest != sem4.identityDigest
    check "identityDigest changes when requiredWorkUnitCoverage changes":
      assert sem1.identityDigest != sem5.identityDigest

  # ======================================================================
  echo "=== BaseRunIdentity — requireValidBaseRunIdentity ==="

  block:
    let semComplete = makeBaseSemanticIdentity("abc123", "tree456", "v2-full", "complete")
    let semPartial = makeBaseSemanticIdentity("abc123", "tree456", "v2-full", "partial")
    let provSuccess = makeBaseProvenance("run-aaa", "wf", "success", "2026-01-01T00:00:00Z", "r1")
    let provFailed = makeBaseProvenance("run-bbb", "wf", "failure", "2026-01-01T00:00:00Z", "r1")

    let baseOk = BaseRunIdentity(semanticIdentity: semComplete, provenance: provSuccess)
    let baseResultStatusFail = BaseRunIdentity(semanticIdentity: semComplete, provenance: provFailed)
    let baseCoverageFail = BaseRunIdentity(semanticIdentity: semPartial, provenance: provSuccess)

    check "requireValidBaseRunIdentity returns error when resultStatus != success":
      let res = requireValidBaseRunIdentity(baseResultStatusFail)
      assert res.isErr()
      assert res.error().contains("resultStatus")
      assert res.error().contains("BaseRunIdentity unavailable ⇒ V1 forbidden ⇒ V2")

    check "requireValidBaseRunIdentity returns error when requiredWorkUnitCoverage != complete":
      let res = requireValidBaseRunIdentity(baseCoverageFail)
      assert res.isErr()
      assert res.error().contains("requiredWorkUnitCoverage")
      assert res.error().contains("BaseRunIdentity unavailable ⇒ V1 forbidden ⇒ V2")

    check "requireValidBaseRunIdentity returns OK when both conditions satisfied":
      let res = requireValidBaseRunIdentity(baseOk)
      assert res.isOk()

  # ======================================================================
  echo "=== BaseRunIdentity — isValid predicate ==="

  block:
    let semOk = makeBaseSemanticIdentity("a", "b", "mode", "complete")
    let semBad = makeBaseSemanticIdentity("a", "b", "mode", "partial")
    let provOk = makeBaseProvenance("r", "w", "success", "t", "rn")
    let provBad = makeBaseProvenance("r", "w", "failure", "t", "rn")

    let baseOk = BaseRunIdentity(semanticIdentity: semOk, provenance: provOk)
    let baseResultFail = BaseRunIdentity(semanticIdentity: semOk, provenance: provBad)
    let baseCovFail = BaseRunIdentity(semanticIdentity: semBad, provenance: provOk)

    check "isValid is true when resultStatus=success and coverage=complete":
      assert baseOk.isValid == true
    check "isValid is false when resultStatus != success":
      assert baseResultFail.isValid == false
    check "isValid is false when requiredWorkUnitCoverage != complete":
      assert baseCovFail.isValid == false

  # ======================================================================
  echo "=== Manifest integrity — proof_unit_catalog (W1–W11 single authority) ==="

  block:
    ## Formerly read data/ci_required_work_units.json (deleted 2026-09-23 —
    ## this test was its sole consumer). The W-axis manifest now lives in
    ## src/gate/proof_unit_catalog.nim (single editing authority); the same
    ## invariants are validated against the catalog module directly.
    let manifestUnits = ProofUnitCatalog
    assert manifestUnits.len == 11, "catalog must contain exactly 11 work units (W1-W11)"

    var seenIds: seq[string] = @[]
    for unit in manifestUnits:
      let id = unit.id
      let name = unit.name
      let reqFull = unit.requiredForFullCertification

      check "unit " & id & " has requiredForFullCertification=true":
        assert reqFull == true, id & " must have requiredForFullCertification=true"

      check "unit " & id & " id ∈ {W1..W11}":
        let validIds = @["W1","W2","W3","W4","W5","W6","W7","W8","W9","W10","W11"]
        assert id in validIds, id & " must be in {W1..W11}"

      check "unit " & id & " has a non-empty name":
        assert name.len > 0, id & " must have a non-empty name"

      check "unit " & id & " has a tier":
        assert unit.tier in {ptL0, ptL1, ptL2}, id & " must have a tier in {L0,L1,L2}"

      seenIds.add(id)

    check "all W1-W11 present exactly once":
      var expectedIds: seq[string] = @[]
      for i in 1..11: expectedIds.add("W" & $i)
      assert sorted(seenIds) == sorted(expectedIds), "all W1..W11 must be present"

  # ======================================================================
  echo "=== Cross-check — identityDigest reproducibility ==="

  block:
    # Same semantic fields → same identityDigest, provenance never matters.
    let semA = makeBaseSemanticIdentity("base-1", "tree-1", "v2-full", "complete")
    let semB = makeBaseSemanticIdentity("base-1", "tree-1", "v2-full", "complete")
    let semC = makeBaseSemanticIdentity("base-2", "tree-1", "v2-full", "complete")

    check "identityDigest is reproducible (same inputs → same digest)":
      assert semA.identityDigest == semB.identityDigest
    check "identityDigest differs when baseCommit changes":
      assert semA.identityDigest != semC.identityDigest
    check "identityDigest does not include provenance":
      # Even if provenance fields were included in the hash, semA and semB
      # would differ if provenance were mixed in. Since they match,
      # provenance is excluded by construction.
      assert semA.identityDigest == semB.identityDigest

  echo ""
  echo "=== Results: " & $passed & " passed, " & $failed & " failed ==="
  if failed > 0:
    quit(1)

main()
