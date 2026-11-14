{.push raises: [CatchableError].}

## Proof State Projection Tests — Unit tests for verification/proof_state_projection.nim
## Tests all exported pure functions operating on JsonNode-based proof state entries.

import std/[unittest, json, os, tables, times]
import verification/proof_state_projection
import core/types/certificate_types
import core/types/verification_tier
import core/utils/constants

# ---------------------------------------------------------------------------
# proofStateLabelFromModuleFunction
# ---------------------------------------------------------------------------

suite "proofStateLabelFromModuleFunction":
  test "normal module and function":
    check proofStateLabelFromModuleFunction("src/core/sorter.nim", "buildPlan") ==
      "sorter.nim::buildPlan"

  test "empty module → empty string":
    check proofStateLabelFromModuleFunction("", "func") == ""

  test "empty function → empty string":
    check proofStateLabelFromModuleFunction("src/mod.nim", "") == ""

  test "both empty → empty string":
    check proofStateLabelFromModuleFunction("", "") == ""

  test "deep path extracts filename only":
    check proofStateLabelFromModuleFunction("a/b/c/d/module.nim", "fn") ==
      "module.nim::fn"

# ---------------------------------------------------------------------------
# proofStateLabelFromEntry
# ---------------------------------------------------------------------------

suite "proofStateLabelFromEntry":
  test "nil node → empty string":
    check proofStateLabelFromEntry(nil) == ""

  test "non-object node → empty string":
    check proofStateLabelFromEntry(%* "string") == ""

  test "explicit label field takes precedence":
    let entry = %*{
      "label": "my::label",
      "modulePath": "src/mod.nim",
      "functionName": "fn"
    }
    check proofStateLabelFromEntry(entry) == "my::label"

  test "falls back to modulePath::functionName":
    let entry = %*{
      "modulePath": "src/core/sorter.nim",
      "functionName": "buildPlan"
    }
    check proofStateLabelFromEntry(entry) == "sorter.nim::buildPlan"

  test "missing fields → empty string":
    let entry = %*{"other": "data"}
    check proofStateLabelFromEntry(entry) == ""

# ---------------------------------------------------------------------------
# certificateStatusToProofStateStatus
# ---------------------------------------------------------------------------

suite "certificateStatusToProofStateStatus":
  test "certGreen → verified":
    check certificateStatusToProofStateStatus("certGreen") == verifiedKey

  test "certVerifiedAxiom → verified":
    check certificateStatusToProofStateStatus("certVerifiedAxiom") == verifiedKey

  test "certIntrinsic → verified":
    check certificateStatusToProofStateStatus("certIntrinsic") == verifiedKey

  test "verified → verified":
    check certificateStatusToProofStateStatus(verifiedKey) == verifiedKey

  test "certPseudoVerified → pseudo_verified":
    check certificateStatusToProofStateStatus("certPseudoVerified") == "pseudo_verified"

  test "certPending → unattempted":
    check certificateStatusToProofStateStatus("certPending") == unattemptedKey

  test "pending → unattempted":
    check certificateStatusToProofStateStatus("pending") == unattemptedKey

  test "certYellow → partially_verified":
    check certificateStatusToProofStateStatus("certYellow") == "partially_verified"

  test "bounded → partially_verified":
    check certificateStatusToProofStateStatus("bounded") == "partially_verified"

  test "certRed → counter_example_found":
    check certificateStatusToProofStateStatus("certRed") == "counter_example_found"

  test "failed → counter_example_found":
    check certificateStatusToProofStateStatus("failed") == "counter_example_found"

  test "certZ3Candidate → z3_candidate (honest candidate, never counterexample)":
    ## DECISION-0630: unsat candidate evidence is its own state — the
    ## projection must not erase it to "unknown" nor inflate it to
    ## counter_example_found (SAT-only).
    check certificateStatusToProofStateStatus("certZ3Candidate") == "z3_candidate"

  test "certZ3Verified (legacy) → z3_candidate":
    ## Legacy spelling canonicalizes to the candidate state on read.
    check certificateStatusToProofStateStatus("certZ3Verified") == "z3_candidate"

  test "timed_out → timedOut":
    check certificateStatusToProofStateStatus("timed_out") == timedOutKey

  test "unknown status → unknown":
    check certificateStatusToProofStateStatus("bogus") == "unknown"

  test "certStale → certStale":
    check certificateStatusToProofStateStatus("certStale") == "certStale"

# ---------------------------------------------------------------------------
# isCertifiedExemptProofStateEntry
# ---------------------------------------------------------------------------

suite "isCertifiedExemptProofStateEntry":
  test "nil → false":
    check isCertifiedExemptProofStateEntry(nil) == false

  test "non-object → false":
    check isCertifiedExemptProofStateEntry(%* 42) == false

  test "correct status and reason prefix → true":
    let entry = %*{
      "status": "certified_exempt",
      "reason": "certified-exempt:some_reason"
    }
    check isCertifiedExemptProofStateEntry(entry) == true

  test "correct status but wrong reason → false":
    let entry = %*{
      "status": "certified_exempt",
      "reason": "some other reason"
    }
    check isCertifiedExemptProofStateEntry(entry) == false

  test "correct exemptionReason field → true":
    let entry = %*{
      "status": "certified_exempt",
      "reason": "",
      "exemptionReason": "axiom-pure-or-vacuous-primitive"
    }
    check isCertifiedExemptProofStateEntry(entry) == true

  test "wrong status → false":
    let entry = %*{
      "status": "verified",
      "reason": "certified-exempt:foo"
    }
    check isCertifiedExemptProofStateEntry(entry) == false

# ---------------------------------------------------------------------------
# proofStateEntryConvergesWithCertificate
# ---------------------------------------------------------------------------

suite "proofStateEntryConvergesWithCertificate":
  test "nil entry → false":
    let proj = CertificateProjection(status: "certGreen")
    check proofStateEntryConvergesWithCertificate(nil, proj) == false

  test "matching status → true":
    let entry = %*{"status": verifiedKey}
    let proj = CertificateProjection(status: "certGreen")
    check proofStateEntryConvergesWithCertificate(entry, proj) == true

  test "non-matching status → false":
    let entry = %*{"status": unattemptedKey}
    let proj = CertificateProjection(status: "certGreen")
    check proofStateEntryConvergesWithCertificate(entry, proj) == false

  test "certified_exempt entry converges with certGreen":
    let entry = %*{
      "status": "certified_exempt",
      "reason": "certified-exempt:foo"
    }
    let proj = CertificateProjection(status: "certGreen")
    check proofStateEntryConvergesWithCertificate(entry, proj) == true

  test "unknown certificate status → false":
    let entry = %*{"status": "verified"}
    let proj = CertificateProjection(status: "bogus")
    check proofStateEntryConvergesWithCertificate(entry, proj) == false

# ---------------------------------------------------------------------------
# hasSubstantiveProofStateEvidence
# ---------------------------------------------------------------------------

suite "hasSubstantiveProofStateEvidence":
  test "all fields present → true":
    let entry = %*{
      "leanCompilerVerified": true,
      "negativeTestResult": true,
      "evidencePath": "/path/to/evidence",
      "negativeEvidencePath": "/path/to/neg"
    }
    check hasSubstantiveProofStateEvidence(entry) == true

  test "missing leanCompilerVerified → false":
    let entry = %*{
      "negativeTestResult": true,
      "evidencePath": "/e",
      "negativeEvidencePath": "/n"
    }
    check hasSubstantiveProofStateEvidence(entry) == false

  test "missing evidencePath → false":
    let entry = %*{
      "leanCompilerVerified": true,
      "negativeTestResult": true,
      "evidencePath": "",
      "negativeEvidencePath": "/n"
    }
    check hasSubstantiveProofStateEvidence(entry) == false

  test "nil entry → false":
    check hasSubstantiveProofStateEvidence(nil) == false

# ---------------------------------------------------------------------------
# applyProofStateSyncStatus
# ---------------------------------------------------------------------------

suite "applyProofStateSyncStatus":
  test "substantive + dual evidence → certGreen":
    var node = %*{
      "status": "unattempted",
      "winningStrategy": "",
      "solverStatus": "unsat",
      "solverMeta": %*{"leanCompilerVerified": true},
      "kernel": true
    }
    applyProofStateSyncStatus(node, true)
    check node["status"].getStr() == "certGreen"
    check node["reason"].getStr() == "proof-state-kernel-replay"
    check node["winningStrategy"].getStr() == "lean-replay"

  test "substantive + z3-only evidence → certZ3Candidate (never certGreen)":
    # DEBT#504: Z3-only now projects through the canonical tierToStatusString
    # (DECISION-0630) — the honest candidate state, never certGreen.
    var node = %*{
      "status": "x",
      "solverStatus": "unsat",
      "solverMeta": %*{"leanCompilerVerified": false}
    }
    applyProofStateSyncStatus(node, true)
    check node["status"].getStr() == "certZ3Candidate"

  test "substantive but no dual evidence → honest tier, not certGreen":
    # P0: certGreen requires z3Passed ∧ leanVerified. A substantive flag alone
    # never grants certGreen — missing evidence must not overclaim dual assurance.
    var node = %*{"status": "x", "winningStrategy": ""}
    applyProofStateSyncStatus(node, true)
    check node["status"].getStr() != "certGreen"

  test "substantive=true preserves existing winningStrategy":
    var node = %*{"status": "x", "winningStrategy": "custom"}
    applyProofStateSyncStatus(node, true)
    check node["winningStrategy"].getStr() == "custom"

  test "substantive=false → certPseudoVerified":
    var node = %*{"status": "x"}
    applyProofStateSyncStatus(node, false)
    check node["status"].getStr() == "certPseudoVerified"
    check node["trusted"].getBool() == false

# ---------------------------------------------------------------------------
# applyProofStateSyncStatus — canonical tier projection (DEBT#504)
# ---------------------------------------------------------------------------

suite "applyProofStateSyncStatus canonical tier projection":
  test "tierToStatusString maps all six tiers canonically (DECISION-0630)":
    # DEBT#504: sync projects through the single canonical tierToStatusString
    # (core/types/certificate_types.nim). Pin the six values so any drift in
    # the canonical mapping surfaces in the projection contract.
    check tierToStatusString(vtDual) == "certGreen"
    check tierToStatusString(vtZ3Only) == "certZ3Candidate"
    check tierToStatusString(vtKInduction) == "certZ3Candidate"
    check tierToStatusString(vtLeanOnly) == "certLeanVerified"
    check tierToStatusString(vtNone) == "certNoObligation"
    check tierToStatusString(vtUfAbstract) == "certZ3Candidate"

  test "lean-only evidence → certLeanVerified":
    var node = %*{
      "status": "x",
      "solverMeta": %*{"leanCompilerVerified": true},
      "kernel": true
    }
    applyProofStateSyncStatus(node, true)
    check node["status"].getStr() == "certLeanVerified"

  test "no evidence (vtNone) → certNoObligation, never certRed":
    # vtNone means "no evidence and no obligation tracked" — projecting it to
    # certRed would fabricate a counterexample. The proof-state leg is stable:
    # certNoObligation maps to no_obligation.
    var node = %*{"status": "x"}
    applyProofStateSyncStatus(node, true)
    check node["status"].getStr() == "certNoObligation"
    check certificateStatusToProofStateStatus(node["status"].getStr()) == "no_obligation"

# ---------------------------------------------------------------------------
# legacy certZ3Verified normalization (DEBT#504)
# ---------------------------------------------------------------------------

suite "legacy certZ3Verified normalization":
  test "synced certZ3Candidate projects back to z3_candidate":
    var node = %*{
      "status": "x",
      "solverStatus": "unsat",
      "solverMeta": %*{"leanCompilerVerified": false}
    }
    applyProofStateSyncStatus(node, true)
    check node["status"].getStr() == "certZ3Candidate"
    check certificateStatusToProofStateStatus(node["status"].getStr()) == "z3_candidate"

  test "certZ3Candidate certificate converges with z3_candidate entry":
    let entry = %*{"status": "z3_candidate"}
    let proj = CertificateProjection(status: "certZ3Candidate")
    check proofStateEntryConvergesWithCertificate(entry, proj) == true

  test "legacy certZ3Verified certificate converges with z3_candidate entry":
    # Legacy spelling is canonicalized on read — proof-state semantics are
    # unchanged by the DEBT#504 projection fix.
    let entry = %*{"status": "z3_candidate"}
    let proj = CertificateProjection(status: "certZ3Verified")
    check proofStateEntryConvergesWithCertificate(entry, proj) == true

# ---------------------------------------------------------------------------
# spNoObligation provenance guard (unchanged by DEBT#504)
# ---------------------------------------------------------------------------

suite "spNoObligation provenance guard":
  test "top-level solverProvenance=spNoObligation is derived":
    check isNoObligationDerived(%*{"solverProvenance": "spNoObligation"}) == true

  test "nested solverMeta.solverProvenance=spNoObligation is derived":
    check isNoObligationDerived(%*{"solverMeta": %*{"solverProvenance": "spNoObligation"}}) == true

  test "other provenance is not derived":
    check isNoObligationDerived(%*{"solverProvenance": "spZ3"}) == false
    check isNoObligationDerived(%*{}) == false

  test "spNoObligation + substantive dual evidence blocks certGreen (§0.9)":
    var node = %*{
      "status": "unattempted",
      "solverProvenance": "spNoObligation",
      "solverStatus": "unsat",
      "solverMeta": %*{"leanCompilerVerified": true},
      "kernel": true
    }
    applyProofStateSyncStatus(node, true)
    check node["status"].getStr() != "certGreen"
    check node["status"].getStr() == "certPseudoVerified"
    check node["trusted"].getBool() == false

  test "nested spNoObligation + substantive dual evidence blocks certGreen":
    var node = %*{
      "status": "unattempted",
      "solverStatus": "unsat",
      "solverMeta": %*{"leanCompilerVerified": true, "solverProvenance": "spNoObligation"},
      "kernel": true
    }
    applyProofStateSyncStatus(node, true)
    check node["status"].getStr() != "certGreen"
    check node["status"].getStr() == "certPseudoVerified"

  test "non-spNoObligation provenance does not trigger the guard":
    var node = %*{
      "status": "unattempted",
      "solverProvenance": "spZ3",
      "solverStatus": "unsat",
      "solverMeta": %*{"leanCompilerVerified": true},
      "kernel": true
    }
    applyProofStateSyncStatus(node, true)
    check node["status"].getStr() == "certGreen"


# ---------------------------------------------------------------------------
# proofStateEntryFromCertificate
# ---------------------------------------------------------------------------

suite "proofStateEntryFromCertificate":
  test "constructs entry from projection":
    let proj = CertificateProjection(
      path: "certs/test.json",
      label: "mod.nim::fn",
      modulePath: "src/mod.nim",
      functionName: "fn",
      status: "certGreen",
      node: %*{"reason": "proved", "winningStrategy": "simp"}
    )
    let entry = proofStateEntryFromCertificate(proj)
    check entry["modulePath"].getStr() == "src/mod.nim"
    check entry["functionName"].getStr() == "fn"
    check entry["status"].getStr() == verifiedKey
    check entry["certificateStatus"].getStr() == "certGreen"
    check entry["certificatePath"].getStr() == "certs/test.json"
    check entry["reason"].getStr() == "proved"
    check entry["winningStrategy"].getStr() == "simp"

  test "unattempted status → attempted=false":
    let proj = CertificateProjection(
      path: "c.json", label: "m::f",
      modulePath: "m", functionName: "f",
      status: "certPending", node: %*{}
    )
    let entry = proofStateEntryFromCertificate(proj)
    check entry["attempted"].getBool() == false

  test "verified status → attempted=true":
    let proj = CertificateProjection(
      path: "c.json", label: "m::f",
      modulePath: "m", functionName: "f",
      status: "certGreen", node: %*{}
    )
    let entry = proofStateEntryFromCertificate(proj)
    check entry["attempted"].getBool() == true

# ---------------------------------------------------------------------------
# loadCertificateProjections
# ---------------------------------------------------------------------------

suite "loadCertificateProjections":
  test "non-existent directory → empty table":
    let table = loadCertificateProjections("/nonexistent/path")
    check table.len == 0

  test "empty cert dir → empty table":
    let tmpDir = getTempDir() / "axiom_test_cproj_" & $epochTime().int
    createDir(tmpDir)
    defer: removeDir(tmpDir)
    let table = loadCertificateProjections(tmpDir)
    check table.len == 0

  test "loads valid certificate JSON files":
    let tmpDir = getTempDir() / "axiom_test_cproj_load_" & $epochTime().int
    createDir(tmpDir)
    defer: removeDir(tmpDir)
    writeFile(tmpDir / "test_cert.json", $ %*{
      "modulePath": "src/core/test.nim",
      "functionName": "myFunc",
      "status": "certGreen"
    })
    let table = loadCertificateProjections(tmpDir)
    check table.len == 1
    let key = "test.nim::myFunc"
    check table.hasKey(key)
    check table[key].status == "certGreen"

  test "ignores JSON files without valid module/function":
    let tmpDir = getTempDir() / "axiom_test_cproj_bad_" & $epochTime().int
    createDir(tmpDir)
    defer: removeDir(tmpDir)
    writeFile(tmpDir / "bad.json", $ %*{"foo": "bar"})
    let table = loadCertificateProjections(tmpDir)
    check table.len == 0

# ---------------------------------------------------------------------------
# certificateStatusByLabel
# ---------------------------------------------------------------------------

suite "certificateStatusByLabel":
  test "empty dir → empty table":
    let table = certificateStatusByLabel("/nonexistent/path")
    check table.len == 0

  test "returns status mapping":
    let tmpDir = getTempDir() / "axiom_test_csl_" & $epochTime().int
    createDir(tmpDir)
    defer: removeDir(tmpDir)
    writeFile(tmpDir / "cert.json", $ %*{
      "modulePath": "src/a.nim",
      "functionName": "fn1",
      "status": "certGreen"
    })
    let table = certificateStatusByLabel(tmpDir)
    check table.len == 1
    check table["a.nim::fn1"] == "certGreen"

{.pop.}
