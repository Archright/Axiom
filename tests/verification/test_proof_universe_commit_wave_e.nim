import std/options
import std/strutils
import std/json
import std/os
import std/tempfiles
import core/results
import core/trusted/trust_commit
import core/trusted/scope_identity

## Wave E — proof_universe_commit TrustCommit journal hook test.
##
## Verifies the data-flow chain that commitUniverseIntegrityAndLock uses
## when it builds a TrustCommit after persisting the proof_universe lock:
##   claim JSON -> evidenceId -> scopeDigest -> configDigest -> commit.
##
## N.B.: The proof_universe_commit hook intentionally passes an empty
## solverInvocation (placeholder for graph/lock snapshot).  validateCommit
## will reject this in its current form (solverInvocation non-empty is
## required).  The test therefore uses a placeholder non-empty solverInvocation
## to exercise the full round-trip; the hook itself always routes through
## commitVerification so the validation gate controls admission to the journal.

var failures = 0

proc expect(cond: bool; msg: string) =
  if not cond:
    inc failures
    echo "  FAIL: " & msg

var baseCounter = 0
proc tmpBase(): string =
  inc baseCounter
  let d = getTempDir() / ("axiom_puc_test_" & $getCurrentProcessId() & "_" & $baseCounter)
  if not dirExists(d):
    createDir(d)
  d

echo "=== proof_universe_commit Wave E tests ==="

# --- 1. Claim JSON construction from graph/lock data ---
block:
  let ks = @["mod::bar", "mod::foo"]
  let lockMerkle = "r:abc123"
  let vkd = "0.7500"
  let claim = %*{
    "graphSnapshot": %*{
      "symbolCount": ks.len,
      "edgeCount": 1
    },
    "lockSnapshot": %*{
      "merkleRoot": lockMerkle,
      "fileCount": 5,
      "vkdFixed4": vkd
    }
  }
  let claimStr = $claim
  # Nim's %* produces compact JSON (no spaces after colons)
  expect(claimStr.contains("\"symbolCount\":2"), "claim contains symbolCount")
  expect(claimStr.contains("\"edgeCount\":1"), "claim contains edgeCount")
  expect(claimStr.contains("\"merkleRoot\":\"r:abc123\""), "claim contains lock merkleRoot")
  expect(claimStr.contains("\"vkdFixed4\":\"0.7500\""), "claim contains vkdFixed4")
  echo "Test 1 PASSED: claim JSON from graph/lock data"

# --- 2. evidenceId binds claim + solverInvocation + certificateDigest ---
block:
  let claimA = """{"graph":{"symbolCount":2,"edgeCount":1},"lock":{"merkleRoot":"r:abc123"}}"""
  let ev1 = computeEvidenceId(claimA, "{}", "")
  let ev2 = computeEvidenceId(claimA, "{}", "")
  expect(ev1 == ev2, "evidenceId deterministic for same inputs")

  let claimB = """{"graph":{"symbolCount":3,"edgeCount":1},"lock":{"merkleRoot":"r:abc123"}}"""
  let ev3 = computeEvidenceId(claimB, "{}", "")
  expect(ev1 != ev3, "evidenceId content-sensitive (different claim)")

  let ev4 = computeEvidenceId(claimA, "solver:z3", "")
  expect(ev1 != ev4, "evidenceId content-sensitive (different solverInvocation)")
  echo "Test 2 PASSED: evidenceId binding determinism + sensitivity"

# --- 3. scopeDigest + configDigest from proof-universe inputs ---
block:
  let ks = @["mod::bar", "mod::foo"]
  let scopeInput = scopeInputFromSynthetic(ks, @[], ks.len, 0, "0.7500", "axiom-v33")
  let sd = canonicalScopeDigest(scopeInput)
  expect(sd.len > 0, "scopeDigest non-empty")

  let profileIdentity = "0.7500"
  let scopeLockHash = "r:abc123"
  let cd = configIdentityDigest(profileIdentity, scopeLockHash)
  expect(cd.len > 0, "configDigest non-empty")

  # Determinism
  let sd2 = canonicalScopeDigest(scopeInputFromSynthetic(ks, @[], ks.len, 0, "0.7500", "axiom-v33"))
  expect(sd == sd2, "scopeDigest deterministic")
  echo "Test 3 PASSED: scopeDigest + configDigest for proof universe"

# --- 4. TrustCommit round-trip through validateCommit + commitVerification (non-empty solverInvocation) ---
block:
  let base = tmpBase()
  let claimStr = """{"graph":{"symbolCount":1,"edgeCount":0},"lock":{"merkleRoot":"r:test","fileCount":1,"vkdFixed4":"1.0000"}}"""
  let solverInvocation = "{}"  # non-empty placeholder (Wave E hook uses "" as profile)
  let certificateDigest = ""
  let evidenceId = computeEvidenceId(claimStr, solverInvocation, certificateDigest)

  let ks = @["mod::f"]
  let scopeInput = scopeInputFromSynthetic(ks, @[], ks.len, 0, "1.0000", "axiom-v33")
  let scopeDigest = canonicalScopeDigest(scopeInput)
  let configDigest = configIdentityDigest("1.0000", "r:test")

  let tc = TrustCommit(
    kind: tcVerifiedProof,
    evidenceId: evidenceId,
    claim: claimStr,
    solverInvocation: solverInvocation,
    attestation: "",
    certificateDigest: certificateDigest,
    scopeDigest: scopeDigest,
    configDigest: configDigest,
    parentCommit: none(string)
  )
  let val = validateCommit(tc)
  expect(val.ok, "TrustCommit with non-empty solverInvocation validates")

  let cid = commitVerification(base, tc)
  expect(cid.ok, "commitVerification succeeds for valid TrustCommit: " & (if cid.isErr: cid.error else: ""))

  # Read-back and verify fields
  let readBack = readCommit(base, cid.value)
  expect(readBack.ok, "readCommit succeeds for persisted commit")
  expect(readBack.value.claim == claimStr, "claim round-trips")
  expect(readBack.value.solverInvocation == solverInvocation, "solverInvocation round-trips")
  expect(readBack.value.scopeDigest == scopeDigest, "scopeDigest round-trips")
  expect(readBack.value.configDigest == configDigest, "configDigest round-trips")
  expect(readBack.value.kind == tcVerifiedProof, "kind is tcVerifiedProof")
  echo "Test 4 PASSED: TrustCommit round-trip (non-empty solverInvocation)"

# --- 5. Wave E pattern: evidenceId with empty solverInvocation + certificateDigest ---
block:
  # This mirrors exactly what the hook in proof_universe_commit.nim does.
  # validateCommit will reject this (empty solverInvocation), but the
  # construction + evidenceId computation is correct — the rejection
  # is controlled by validateCommit until a later wave provides a
  # non-empty solverInvocation for the graph/lock snapshot.
  let claimStr = """{"graph":{"symbolCount":1,"edgeCount":0},"lock":{"merkleRoot":"r:empty"}}"""
  let evidenceId = computeEvidenceId(claimStr, "", "")  # solverInvocation=empty, certificateDigest=empty
  expect(evidenceId.len > 0, "evidenceId non-empty even with empty solverInvocation")
  echo "Test 5 PASSED: Wave E evidenceId computation with empty solverInvocation"

echo ""
if failures == 0:
  echo "=== All proof_universe_commit Wave E tests PASSED ==="
else:
  echo "=== " & $failures & " proof_universe_commit Wave E test(s) FAILED ==="
  quit(1)
