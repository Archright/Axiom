import std/options
import std/os
import std/strutils
import core/results
import core/trusted/trust_commit

## Test: verify_cli replay awareness determinism.
## Writes two commits via commitVerification into a temp base,
## then asserts that replayJournal returns the same stateDigest
## on repeated calls (deterministic reconstruction).

var failures = 0

proc expect(cond: bool; msg: string) =
  if not cond:
    inc failures
    echo "  FAIL: " & msg

var baseCounter = 0
proc tmpBase(): string =
  inc baseCounter
  let d = getTempDir() / "axiom_replay_test" / ($getCurrentProcessId() & "_" & $baseCounter)
  if not dirExists(d):
    createDir(d)
  d

echo "=== verify_cli replay determinism tests ==="

# --- 1. Two commits, deterministic replay ---
block:
  let base = tmpBase()
  # Build two valid TrustCommits (evidenceId must bind to embedded content).
  let e1 = computeEvidenceId("claimA", "solverA", "certA")
  let c1 = TrustCommit(kind: tcVerifiedProof,
                       evidenceId: e1, claim: "claimA",
                       solverInvocation: "solverA", attestation: "attA",
                       certificateDigest: "certA",
                       scopeDigest: "scope1", configDigest: "cfg1",
                       parentCommit: none(string))
  let r1 = commitVerification(base, c1)
  expect(r1.ok, "commit1 ok: " & (if r1.isErr: r1.error else: ""))

  let e2 = computeEvidenceId("claimB", "solverB", "certB")
  let c2 = TrustCommit(kind: tcVerifiedProof,
                       evidenceId: e2, claim: "claimB",
                       solverInvocation: "solverB", attestation: "attB",
                       certificateDigest: "certB",
                       scopeDigest: "scope1", configDigest: "cfg1",
                       parentCommit: some(r1.value))
  let r2 = commitVerification(base, c2)
  expect(r2.ok, "commit2 ok: " & (if r2.isErr: r2.error else: ""))

  # Replay twice — stateDigest must be identical (deterministic reconstruction).
  let replay1 = replayJournal(base)
  expect(replay1.ok, "replay1 ok: " & (if replay1.isErr: replay1.error else: ""))
  let replay2 = replayJournal(base)
  expect(replay2.ok, "replay2 ok: " & (if replay2.isErr: replay2.error else: ""))

  expect(replay1.value.stateDigest == replay2.value.stateDigest,
         "stateDigest is deterministic across two replays")
  expect(replay1.value.commitIds.len == 2,
         "replay contains exactly 2 commits, got " & $replay1.value.commitIds.len)
  expect(replay1.value.commitIds.len == replay2.value.commitIds.len,
         "both replays return same commit count")

  echo "Test 1 PASSED: two-commit deterministic replay"

echo ""
if failures == 0:
  echo "=== All verify_cli replay determinism tests PASSED ==="
else:
  echo "=== " & $failures & " verify_cli replay determinism test(s) FAILED ==="
  quit(1)
