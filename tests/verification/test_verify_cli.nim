import std/json
import std/strutils
import std/os

import cli/verify_cli

## Test: verify CLI read-only artifact verification contract (R7).
##
## `ax verify <cert-path>` is a read-only integrity projection of the persisted
## canonical certificate. It must NOT re-execute the verification engine
## (I5). It validates the stored artifact against the trust closure
## (deep verification + identityDigest recompute + journal binding) and is
## fail-closed: any absent/mismatched element yields a non-zero exit.
##
## Constructing a full closure-PASS certificate requires a genuine Lean kernel
## acceptance + journal commit, which is exercised end-to-end by the golden slice
## (R8) in real execution. This unit test covers the fail-closed contract of the
## CLI boundary itself.

proc main() =
  echo "=== verify CLI tests ==="
  let tmpDir = getAppDir() & "/.tmp_verify_cli_test"
  if dirExists(tmpDir):
    removeDir(tmpDir)
  createDir(tmpDir)

  # 1. No arguments → usage + exit 1.
  let usageExit = runVerifyCli(@[])
  doAssert usageExit == 1, "empty args should return 1 (usage), got " & $usageExit

  # 2. Missing certificate file → fail-closed exit 1.
  let missingPath = tmpDir & "/does-not-exist.json"
  let missingExit = runVerifyCli(@[missingPath])
  doAssert missingExit == 1, "missing cert file should return 1 (ccsMalformed), got " & $missingExit

  # 3. A certificate lacking the v1 journal binding must fail closed (exit 1).
  #    The new verify contract is read-only: it does NOT replay Z3/Lean, and a
  #    cert without trustCommitId cannot establish durable provenance, so it is
  #    rejected rather than reported as "MATCH" (old Z3-replay contract).
  let unjournaledPath = tmpDir & "/unjournaled.json"
  let unjournaledCert = %*{
    "schemaVersion": "2",
    "subjectId": "test-subject-001",
    "functionName": "foo",
    "modulePath": "tests/verification/foo.nim",
    "outcome": "clProved",
    "specificationId": "spec-1",
    "semanticProfileId": "sem-1",
    "obligationId": "obl-1",
    "evidenceId": "ev-1",
    "dependencySnapshotId": "dep-1",
    "policyId": "pol-1"
  }
  writeFile(unjournaledPath, $unjournaledCert)
  let unjournaledExit = runVerifyCli(@[unjournaledPath])
  doAssert unjournaledExit == 1, "cert without journal binding should return 1 (fail-closed), got " & $unjournaledExit

  echo "Test PASSED: verify CLI is a read-only, fail-closed artifact verifier"

  removeDir(tmpDir)

when isMainModule:
  main()
