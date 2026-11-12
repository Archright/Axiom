import ../../src/core/results
import std/os
import ../../src/core/types/universe_types
import ../../src/core/proof/proof_universe_lock
import std/unittest

proc testVerificationIsReadOnlyOnMismatch() =
  ## [AXIOM v0.6.7] Verify that verifyProofUniverseLock never mutates the lock
  ## file on mismatch. This is the core invariant behind the read-only pre-push
  ## gate (AGENTS.md §14.4).
  let wrongLock = ProofUniverseLock(
    merkleRoot: "9999999999",
    timestamp: "2026-01-01T00:00:00+09:00",
    fileCount: 0,
    vkdFixed4: "0.0000"
  )
  let testPath = "test_read_only_mismatch.lock"
  writeFile(testPath, """{"merkleRoot":"9999999999","timestamp":"2026-01-01T00:00:00+09:00","fileCount":0,"vkdFixed4":"0.0000"}""")
  let verifiedResult = verifyProofUniverseLock(getCurrentDir(), path = testPath)
  check verifiedResult.isOk  # was: assert verifiedResult.isOk, "verifyProofUniverseLock failed: " & verifiedResult.error
  check verifiedResult.get == false  # was: assert verifiedResult.get == false, "Expected mismatch to be detected"

  let storedRes = readProofUniverseLock(testPath)
  check storedRes.isOk  # was: assert storedRes.isOk, "Must read back lock file"
  let stored = storedRes.get
  check stored.merkleRoot == "9999999999"  # was: assert stored.merkleRoot == "9999999999", "Lock file must not be modified by verification"
  check stored.fileCount == 0  # was: assert stored.fileCount == 0, "Lock file must not be modified by verification"

  removeFile(testPath)

suite "Gate Hook Read Only":
  test "Gate Hook Read Only tests":
    testVerificationIsReadOnlyOnMismatch()
