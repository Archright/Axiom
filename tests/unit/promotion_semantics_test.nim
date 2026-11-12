import std/[json, os, unittest, strutils]
import ../../src/verification/cert_promotion
import ../../src/core/types/results
import ../../src/core/types/certificate_types
import ../../src/verification/certificate_eligibility

## ─── Phase C: Regression tests for invariant noObligation ≠ failed ≠ verified ───
##
## These tests seal the promotion-classification invariant at the unit level:
##
##   (a) certNoObligation is neither promotion-eligible nor verified
##   (b) certZ3Candidate (Z3-only evidence) is never promoted to verified
##   (c) The classification of a noObligation node is NOT a persist failure
##       (the loop_driver.nim classification logic at lines 1066-1116 is
##        embedded in a proc with I/O and is NOT a pure function; there is
##        no extractable `classifyPromotionStatus` helper.  The invariant is
##        therefore frozen at the building-block level via the pure functions
##        that the classification logic calls: isPromotionAllowedStatus,
##        isVerifiedCertificateStatus, and hasSemanticEvidence.)
##
## Integration coverage: the live `ax prove` run in a later phase covers the
## end-to-end scenario where a noObligation symbol does NOT trigger a PERSIST
## FAIL.  The unit tests below freeze the preconditions that guarantee that
## outcome.

suite "isPromotionAllowedStatus — promotion eligibility":

  test "certGreen is promotion-eligible":
    check isPromotionAllowedStatus("certGreen") == true

  test "certLeanVerified is promotion-eligible":
    check isPromotionAllowedStatus("certLeanVerified") == true

  test "certYellow is promotion-eligible":
    check isPromotionAllowedStatus("certYellow") == true

  test "certNoObligation is NOT promotion-eligible":
    ## P4: noObligation nodes have no semantic evidence to promote.
    ## The loop_driver classifies them as orchestrationNoObligation,
    ## NOT as orchestrationProofFailed (persist failure).
    check isPromotionAllowedStatus("certNoObligation") == false

  test "certZ3Candidate is NOT promotion-eligible":
    ## Z3-only evidence is candidate-only — never promoted to verified.
    ## The loop_driver classifies this as orchestrationNotVerifiable,
    ## NOT as orchestrationProofFailed (persist failure).
    check isPromotionAllowedStatus("certZ3Candidate") == false

  test "certRed is NOT promotion-eligible":
    check isPromotionAllowedStatus("certRed") == false

  test "certUnknown is NOT promotion-eligible":
    check isPromotionAllowedStatus("certUnknown") == false

  test "empty string is NOT promotion-eligible":
    check isPromotionAllowedStatus("") == false

suite "isVerifiedCertificateStatus — verified status mapping":

  test "certGreen is verified":
    check isVerifiedCertificateStatus("certGreen") == true

  test "certLeanVerified is verified":
    check isVerifiedCertificateStatus("certLeanVerified") == true

  test "certNoObligation is NOT verified":
    ## P4: noObligation is a terminal classification meaning the symbol
    ## has no verification obligation.  It is neither verified nor failed.
    check isVerifiedCertificateStatus("certNoObligation") == false

  test "certZ3Candidate is NOT verified":
    ## Z3-only evidence does not constitute kernel verification.
    check isVerifiedCertificateStatus("certZ3Candidate") == false

  test "certRed is NOT verified":
    check isVerifiedCertificateStatus("certRed") == false

  test "certUnknown is NOT verified":
    check isVerifiedCertificateStatus("certUnknown") == false

suite "hasSemanticEvidence — evidence-gated promotion":

  test "certNoObligation JSON has no semantic evidence":
    ## A noObligation certificate has no Z3 or Lean evidence.
    ## This is the precondition that causes the loop_driver to classify
    ## the node as orchestrationNoObligation (not orchestrationProofFailed).
    let cert = %*{
      "schemaVersion": "axiom.certificate.v3",
      "modulePath": "src/no_obligation.nim",
      "functionName": "noObligationFn",
      "status": "certNoObligation",
      "solverStatus": "",
      "smtlib2": "",
      "solverMeta": %*{"leanCompilerVerified": false, "leanKernelVerified": false}
    }
    check hasSemanticEvidence(cert) == false

  test "certGreen with dual evidence has semantic evidence":
    let cert = %*{
      "schemaVersion": "axiom.certificate.v3",
      "modulePath": "src/dual.nim",
      "functionName": "dualFn",
      "status": "certGreen",
      "solverStatus": "unsat",
      "smtlib2": "(assert true)",
      "solverMeta": %*{"leanCompilerVerified": true, "leanKernelVerified": true}
    }
    check hasSemanticEvidence(cert) == true

  test "certLeanVerified with Lean-only evidence has semantic evidence":
    let cert = %*{
      "schemaVersion": "axiom.certificate.v3",
      "modulePath": "src/lean_only.nim",
      "functionName": "leanFn",
      "status": "certLeanVerified",
      "solverStatus": "",
      "smtlib2": "",
      "solverMeta": %*{"leanCompilerVerified": true, "leanKernelVerified": true},
      "kernel": newJBool(true)
    }
    check hasSemanticEvidence(cert) == true

  test "certZ3Candidate with Z3-only evidence has semantic evidence":
    ## Z3-only evidence IS semantic evidence (it just is not verified
    ## evidence — it does not promote to certGreen/certLeanVerified).
    let cert = %*{
      "schemaVersion": "axiom.certificate.v3",
      "modulePath": "src/z3_only.nim",
      "functionName": "z3Fn",
      "status": "certZ3Candidate",
      "solverStatus": "unsat",
      "smtlib2": "(assert true)",
      "solverMeta": %*{"leanCompilerVerified": false, "leanKernelVerified": false}
    }
    check hasSemanticEvidence(cert) == true

  test "nil cert has no semantic evidence":
    check hasSemanticEvidence(nil) == false

  test "non-object cert has no semantic evidence":
    let cert = %* "not-an-object"
    check hasSemanticEvidence(cert) == false

suite "noObligation ≠ failed — classification invariant":

  ## The loop_driver.nim lines 1066-1116 classify a candidate's
  ## promotion status through a chain of conditions.  The classification
  ## is NOT a pure function — it is embedded in a proc with I/O
  ## (readFile, parseJson, logging, counter increments).  There is no
  ## extractable `classifyPromotionStatus(status, hasSemanticEvidence)`
  ## helper to unit-test directly.
  ##
  ## We therefore freeze the invariant at the building-block level:
  ## the pure functions that the classification logic calls MUST produce
  ## the values that cause the noObligation branch to be taken (not the
  ## persist-failure branch).

  test "certNoObligation is not promotion-eligible (prevents persist-fail path)":
    ## In loop_driver.nim, the persist-fail path is only reached when
    ## the cert is malformed (nil/not JObject) OR when promotion fails
    ## on a promotion-eligible status.  certNoObligation is excluded
    ## from promotion eligibility, so it can never reach the
    ## promoteToCanonical call that could fail as a persist error.
    check isPromotionAllowedStatus("certNoObligation") == false

  test "certNoObligation has no semantic evidence (triggers noObligation branch, not unverifiable)":
    ## In loop_driver.nim, the classification chain is:
    ##   1. certNode nil/not JObject → persistFail (FAILED)
    ##   2. certStatus == "certNoObligation" → noObligation (NOT failed)
    ##   3. not hasSemanticEvidence → unverifiable (NOT failed)
    ##   4. isPromotionAllowedStatus → promote (VERIFIED)
    ##   5. else → unverifiable (NOT failed)
    ##
    ## For certNoObligation, step 2 is reached directly.  We confirm
    ## step 3's precondition (hasSemanticEvidence == false) holds,
    ## which is what the loop_driver checks for the unverifiable branch.
    let cert = %*{
      "schemaVersion": "axiom.certificate.v3",
      "modulePath": "src/no_obligation.nim",
      "functionName": "noObligationFn",
      "status": "certNoObligation",
      "solverStatus": "",
      "smtlib2": "",
      "solverMeta": %*{"leanCompilerVerified": false, "leanKernelVerified": false}
    }
    check hasSemanticEvidence(cert) == false

  test "certZ3Candidate has semantic evidence but is not promotion-eligible (never promoted, never failed)":
    ## Z3-only evidence means hasSemanticEvidence == true, so the
    ## loop_driver reaches the `else` branch at line 1106 (not the
    ## `not hasSemanticEvidence` branch at line 1084).  Since
    ## isPromotionAllowedStatus("certZ3Candidate") == false, it falls
    ## through to the final else → orchestrationNotVerifiable, NOT
    ## orchestrationProofFailed.
    check isPromotionAllowedStatus("certZ3Candidate") == false
    let cert = %*{
      "schemaVersion": "axiom.certificate.v3",
      "modulePath": "src/z3_only.nim",
      "functionName": "z3Fn",
      "status": "certZ3Candidate",
      "solverStatus": "unsat",
      "smtlib2": "(assert true)",
      "solverMeta": %*{"leanCompilerVerified": false, "leanKernelVerified": false}
    }
    check hasSemanticEvidence(cert) == true

  test "malformed cert (nil) → persist fail, distinct from noObligation":
    ## This test documents that a nil certNode IS a persist failure
    ## (orchestrationProofFailed, promoFailedCount++), which is
    ## structurally distinct from the noObligation path.  The invariant
    ## is that noObligation ≠ failed: noObligation nodes have a valid
    ## certNode with status "certNoObligation", so they never hit this
    ## branch.
    check hasSemanticEvidence(nil) == false
    ## isPromotionAllowedStatus is irrelevant for nil certs because
    ## the nil check happens first in the classification chain.
    check isPromotionAllowedStatus("certNoObligation") == false

suite "promoteToCanonical write-vault staging boundary (R1 regression)":

  ## Regression for the R1 robustness defect: promoteToCanonical historically
  ## hardcoded the staging root to build/certificates, rejecting any candidate
  ## whose actual write vault was configured via AXIOM_PROVE_VAULT_DIR (e.g.
  ## build/ax_start_vaults/runN in the readiness START vertical slice).  The
  ## write side (resolveVaultDirForWrite, DECISION-0622) honored the env vault,
  ## so write and promotion disagreed → PERSIST FAIL → exit 2.
  ##
  ## Fix (Option A, DECISION-0633 extension): candidateRoot is parameterized;
  ## the caller (loop_driver) passes the vault the candidate was actually
  ## written into.  The two tests below bind the boundary semantics:
  ##   (1) a candidate OUTSIDE the declared write vault is still rejected
  ##       (fail-closed preserved), and
  ##   (2) a candidate INSIDE a non-default write vault passes the path
  ##       boundary (is no longer rejected for "must be under build/certificates").

  proc tmpVault(prefix: string): string =
    let d = getTempDir() / "axiom_promo_test" / ($getCurrentProcessId() & "_" & prefix)
    if dirExists(d):
      removeDir(d)
    createDir(d)
    d

  test "candidate outside the declared write vault is rejected (fail-closed preserved)":
    ## A candidate file that lives outside the passed candidateRoot must be
    ## rejected at the staging boundary — never promoted.
    let outsideFile = getTempDir() / ("axiom_outside_" & $getCurrentProcessId() & ".json")
    writeFile(outsideFile, """{"modulePath":"m","functionName":"f","status":"certGreen"}""")
    let vault = tmpVault("out_vault")
    let res = promoteToCanonical(outsideFile, candidateRoot = vault)
    check res.isErr() == true
    check "candidate must be staged under the write vault" in res.error
    removeFile(outsideFile)

  test "candidate inside a non-default write vault passes the staging boundary":
    ## A candidate staged under a non-default vault (≠ build/certificates)
    ## must no longer be rejected by the path check.  It may still fail later
    ## (gate/parse) because the synthetic file is not a full promotional
    ## candidate, but the error must NOT be the staging-boundary error — that
    ## is the specific behavior the R1 fix restores.
    let vault = tmpVault("in_vault")
    let candidate = vault / "deadbeef.json"
    writeFile(candidate, """{"modulePath":"m","functionName":"f","status":"certGreen","irHash":"deadbeef"}""")
    let res = promoteToCanonical(candidate, candidateRoot = vault)
    check res.isErr() == true  # still fails later (not a real promotable candidate)
    check "candidate must be staged under the write vault" notin res.error  # path boundary passed
