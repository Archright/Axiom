# Wave 5b: Four durable cert artifact writes migrated to TrustCommit journal.
# Covers: vault_manifest, vault_index, proof_universe_lock_gate, pipeline_stage_k_induction.

import std/[json, os, options, sequtils, strutils, tempfiles]
import core/crypto/hash_kernel
import core/results
import core/trusted/trust_commit
import core/trusted/scope_identity
import core/json/json_utils
import verification/vault_manifest

proc expect(cond: bool; msg: string) =
  if not cond:
    echo "  FAIL: " & msg
    quit(1)

var failures = 0
proc expectFail(cond: bool; msg: string) =
  if cond:
    inc failures
    echo "  FAIL (expected failure): " & msg

proc tmpBase(): string =
  let d = getTempDir() / ("ax_wave5b_" & $getCurrentProcessId())
  if dirExists(d):
    try: removeDir(d)
    except CatchableError: # axiom:best-effort(temp dir pre-cleanup in tmpBase is non-fatal; test asserts on commitVerification output)
      discard
  createDir(d)
  writeFile(d / ".axiom_root", "repo\n")
  d

# ---------------------------------------------------------------------------
# Helper: build a vault-manifest-style TrustCommit
# ---------------------------------------------------------------------------
func vaultManifestCommit(baseDir, claim: string): TrustCommit {.raises: [].} =
  let certificateDigest = sha256Hex(claim)
  let evidenceId = computeEvidenceId(claim, "vault-manifest", certificateDigest)
  TrustCommit(
    kind: tcVerifiedProof,
    evidenceId: evidenceId,
    claim: claim,
    solverInvocation: "vault-manifest",
    attestation: "Vault manifest state captured in TrustCommit journal",
    certificateDigest: certificateDigest,
    scopeDigest: certificateScopeDigestForPair("src/verification/vault_manifest.nim", "atomicWriteManifest"),
    configDigest: certificateConfigDigestForPair("src/verification/vault_manifest.nim", "atomicWriteManifest", "manifest-write", "", "", "SPV1"),
    parentCommit: none(string)
  )

# ---------------------------------------------------------------------------
# Helper: build a vault-index-style TrustCommit
# ---------------------------------------------------------------------------
func vaultIndexCommit(baseDir, claim: string): TrustCommit {.raises: [].} =
  let certificateDigest = sha256Hex(claim)
  let evidenceId = computeEvidenceId(claim, "vault-index", certificateDigest)
  TrustCommit(
    kind: tcVerifiedProof,
    evidenceId: evidenceId,
    claim: claim,
    solverInvocation: "vault-index",
    attestation: "Vault index state captured in TrustCommit journal",
    certificateDigest: certificateDigest,
    scopeDigest: certificateScopeDigestForPair("src/verification/vault_index.nim", "saveVirtualVaultIndex"),
    configDigest: certificateConfigDigestForPair("src/verification/vault_index.nim", "saveVirtualVaultIndex", "index-save", "", "", "SPV1"),
    parentCommit: none(string)
  )

# ---------------------------------------------------------------------------
# Helper: build a lock-gate-style TrustCommit
# ---------------------------------------------------------------------------
func lockGateCommit(baseDir, claim: string): TrustCommit {.raises: [].} =
  let certificateDigest = sha256Hex(claim)
  let evidenceId = computeEvidenceId(claim, "universe-lock-gate", certificateDigest)
  TrustCommit(
    kind: tcVerifiedProof,
    evidenceId: evidenceId,
    claim: claim,
    solverInvocation: "universe-lock-gate",
    attestation: "Proof universe lock checkpoint captured in TrustCommit journal",
    certificateDigest: certificateDigest,
    scopeDigest: certificateScopeDigestForPair("src/gate/runners/proof_universe_lock_gate.nim", "writeCheckpoint"),
    configDigest: certificateConfigDigestForPair("src/gate/runners/proof_universe_lock_gate.nim", "writeCheckpoint", "checkpoint", "", "", "SPV1"),
    parentCommit: none(string)
  )

# ---------------------------------------------------------------------------
# Helper: build a k-induction-style TrustCommit
# ---------------------------------------------------------------------------
func kInductionCommit(baseDir, claim: string): TrustCommit {.raises: [].} =
  let certificateDigest = sha256Hex(claim)
  let evidenceId = computeEvidenceId(claim, "k-induction", certificateDigest)
  TrustCommit(
    kind: tcVerifiedProof,
    evidenceId: evidenceId,
    claim: claim,
    solverInvocation: "k-induction",
    attestation: "K-induction evidence captured in TrustCommit journal",
    certificateDigest: certificateDigest,
    scopeDigest: certificateScopeDigestForPair("src/verification/pipeline_stage_k_induction.nim", "runKInductionStage"),
    configDigest: certificateConfigDigestForPair("src/verification/pipeline_stage_k_induction.nim", "runKInductionStage", "k-induction", "", "", "SPV1"),
    parentCommit: none(string)
  )

# ---------------------------------------------------------------------------
# Test 1: vault-manifest TrustCommit validates, persists, and roundtrips
# ---------------------------------------------------------------------------
block:
  echo "Test 1: vault-manifest TrustCommit"
  let base = tmpBase()
  let claim = %*{
    "version": 2,
    "entries": @[%*{"modulePath": "src/mod.nim", "functionName": "f", "status": "certGreen", "solverMethod": "smFFI", "lastVerifiedAt": "2026-01-01T00:00:00Z", "irHash": "hash1"}]
  }
  let claimStr = renderJsonMultiline(claim)
  let c = vaultManifestCommit(base, claimStr)

  # validateCommit passes
  let val = validateCommit(c)
  expect(val.ok, "vault-manifest commit validates")

  # commitVerification succeeds
  let res = commitVerification(base, c)
  expect(res.ok, "vault-manifest commitVerification ok: " & (if res.isErr(): res.error else: ""))
  let cid = res.value

  # journal file exists
  expect(fileExists(commitPath(base, cid)), "vault-manifest journal file exists")

  # read-back roundtrip
  let back = readCommit(base, cid)
  expect(back.ok, "vault-manifest readCommit ok")
  expect(back.value.claim == claimStr, "vault-manifest claim roundtrip")
  expect(back.value.solverInvocation == "vault-manifest", "vault-manifest solverInvocation")
  expect(back.value.evidenceId == c.evidenceId, "vault-manifest evidenceId roundtrip")

  # evidenceId is content-sensitive
  let differentClaim = claimStr & "extra"
  let differentDigest = sha256Hex(differentClaim)
  let differentEvidenceId = computeEvidenceId(differentClaim, "vault-manifest", differentDigest)
  expect(differentEvidenceId != c.evidenceId, "vault-manifest evidenceId content-sensitive")

  # replayJournal returns exactly one commit
  let replay = replayJournal(base)
  expect(replay.ok, "vault-manifest replayJournal ok")
  expect(replay.value.commitIds == @[cid], "vault-manifest replay returns exactly one commit")

  echo "  PASSED: vault-manifest TrustCommit"

# ---------------------------------------------------------------------------
# Test 2: vault-index TrustCommit validates, persists, and roundtrips
# ---------------------------------------------------------------------------
block:
  echo "Test 2: vault-index TrustCommit"
  let base = tmpBase()
  let claim = %*{
    "version": 1,
    "lastVerifiedAt": 1700000000,
    "entries": @[%*{"fileName": "mod.nim.json", "modulePath": "src/mod.nim", "functionName": "f", "fingerprint": "fp1", "status": "certGreen", "trusted": true, "sourceMtime": 1700000000, "certMtime": 1700000001, "proofTimeMs": 100, "axiomCount": 5, "solverEngine": "z3"}]
  }
  let claimStr = renderJsonMultiline(claim)
  let c = vaultIndexCommit(base, claimStr)

  let val = validateCommit(c)
  expect(val.ok, "vault-index commit validates")

  let res = commitVerification(base, c)
  expect(res.ok, "vault-index commitVerification ok: " & (if res.isErr(): res.error else: ""))
  let cid = res.value

  expect(fileExists(commitPath(base, cid)), "vault-index journal file exists")

  let back = readCommit(base, cid)
  expect(back.ok, "vault-index readCommit ok")
  expect(back.value.solverInvocation == "vault-index", "vault-index solverInvocation")

  let replay = replayJournal(base)
  expect(replay.ok, "vault-index replayJournal ok")
  expect(replay.value.commitIds == @[cid], "vault-index replay returns exactly one commit")

  echo "  PASSED: vault-index TrustCommit"

# ---------------------------------------------------------------------------
# Test 3: lock-gate TrustCommit validates, persists, and roundtrips
# ---------------------------------------------------------------------------
block:
  echo "Test 3: lock-gate TrustCommit"
  let base = tmpBase()
  let claim = %*{
    "chunkCount": 1,
    "lastVerifiedCount": 1,
    "nextFrontierOffset": 0,
    "lastChunkAt": "2026-01-01T00:00:00Z"
  }
  let claimStr = renderJsonMultiline(claim)
  let c = lockGateCommit(base, claimStr)

  let val = validateCommit(c)
  expect(val.ok, "lock-gate commit validates")

  let res = commitVerification(base, c)
  expect(res.ok, "lock-gate commitVerification ok: " & (if res.isErr(): res.error else: ""))
  let cid = res.value

  expect(fileExists(commitPath(base, cid)), "lock-gate journal file exists")

  let back = readCommit(base, cid)
  expect(back.ok, "lock-gate readCommit ok")
  expect(back.value.solverInvocation == "universe-lock-gate", "lock-gate solverInvocation")

  let replay = replayJournal(base)
  expect(replay.ok, "lock-gate replayJournal ok")
  expect(replay.value.commitIds == @[cid], "lock-gate replay returns exactly one commit")

  echo "  PASSED: lock-gate TrustCommit"

# ---------------------------------------------------------------------------
# Test 4: k-induction TrustCommit validates, persists, and roundtrips
# ---------------------------------------------------------------------------
block:
  echo "Test 4: k-induction TrustCommit"
  let base = tmpBase()
  let claim = %*{
    "k": 2,
    "verdict": "kivProved",
    "baseCaseUnsat": true,
    "stepCaseUnsat": true,
    "baseCaseTimeMs": 50,
    "stepCaseTimeMs": 120,
    "uniquenessConstraints": 3,
    "useLocallyShortest": false,
    "verificationPath": "vpIncrementalK"
  }
  let claimStr = renderJsonMultiline(claim)
  let c = kInductionCommit(base, claimStr)

  let val = validateCommit(c)
  expect(val.ok, "k-induction commit validates")

  let res = commitVerification(base, c)
  expect(res.ok, "k-induction commitVerification ok: " & (if res.isErr(): res.error else: ""))
  let cid = res.value

  expect(fileExists(commitPath(base, cid)), "k-induction journal file exists")

  let back = readCommit(base, cid)
  expect(back.ok, "k-induction readCommit ok")
  expect(back.value.solverInvocation == "k-induction", "k-induction solverInvocation")

  let replay = replayJournal(base)
  expect(replay.ok, "k-induction replayJournal ok")
  expect(replay.value.commitIds == @[cid], "k-induction replay returns exactly one commit")

  echo "  PASSED: k-induction TrustCommit"

# ---------------------------------------------------------------------------
# Test 5: All four commits in one journal — replay returns all four
# ---------------------------------------------------------------------------
block:
  echo "Test 5: All four commits in one journal"
  let base = tmpBase()

  let c1 = vaultManifestCommit(base, renderJsonMultiline(%*{"version": 2, "entries": @[]}))
  let c2 = vaultIndexCommit(base, renderJsonMultiline(%*{"version": 1, "entries": @[]}))
  let c3 = lockGateCommit(base, renderJsonMultiline(%*{"chunkCount": 1}))
  let c4 = kInductionCommit(base, renderJsonMultiline(%*{"k": 2, "verdict": "kivProved"}))

  let r1 = commitVerification(base, c1)
  expect(r1.ok, "commit1 ok")
  let r2 = commitVerification(base, c2)
  expect(r2.ok, "commit2 ok")
  let r3 = commitVerification(base, c3)
  expect(r3.ok, "commit3 ok")
  let r4 = commitVerification(base, c4)
  expect(r4.ok, "commit4 ok")

  let replay = replayJournal(base)
  expect(replay.ok, "multi-commit replayJournal ok")
  expect(replay.value.commitIds.len == 4, "replay returns all four commits")

  # All four solverInvocation values are present
  var invocations: seq[string] = @[]
  for id in replay.value.commitIds:
    let rc = readCommit(base, id)
    expect(rc.ok, "read commit " & id)
    invocations.add(rc.value.solverInvocation)
  expect(invocations.contains("vault-manifest"), "vault-manifest in replay")
  expect(invocations.contains("vault-index"), "vault-index in replay")
  expect(invocations.contains("universe-lock-gate"), "lock-gate in replay")
  expect(invocations.contains("k-induction"), "k-induction in replay")

  echo "  PASSED: all four commits in one journal"

# ---------------------------------------------------------------------------
# Test 6: validateCommit rejects invalid TrustCommits (fail-closed)
# ---------------------------------------------------------------------------
block:
  echo "Test 6: validateCommit fail-closed"
  # empty evidenceId
  var bad = vaultManifestCommit(".", "claim")
  bad.evidenceId = ""
  expect(validateCommit(bad).isErr(), "empty evidenceId rejected")

  # empty claim
  bad = vaultManifestCommit(".", "claim")
  bad.claim = ""
  expect(validateCommit(bad).isErr(), "empty claim rejected")

  # empty solverInvocation
  bad = vaultManifestCommit(".", "claim")
  bad.solverInvocation = ""
  expect(validateCommit(bad).isErr(), "empty solverInvocation rejected")

  # empty scopeDigest
  bad = vaultManifestCommit(".", "claim")
  bad.scopeDigest = ""
  expect(validateCommit(bad).isErr(), "empty scopeDigest rejected")

  # empty configDigest
  bad = vaultManifestCommit(".", "claim")
  bad.configDigest = ""
  expect(validateCommit(bad).isErr(), "empty configDigest rejected")

  # evidenceId mismatch (tamper)
  bad = vaultManifestCommit(".", "claim")
  bad.evidenceId = "deadbeef"
  expect(validateCommit(bad).isErr(), "evidenceId mismatch rejected")

  echo "  PASSED: validateCommit fail-closed"

# ---------------------------------------------------------------------------
# Test 7: batched vault-manifest sync — N in-memory merges, ONE disk write.
# Regression for the phase-13 loop in cli/axiom_engine.nim: entries accumulate
# via mergeResult in memory and atomicWriteManifest (the single-writer
# authority) runs once at the loop boundary. Each atomicWriteManifest
# invocation appends exactly one immutable vault-manifest journal record, so
# the journal-record count is the durable write counter — deterministic, no
# mtime/timing dependence.
# ---------------------------------------------------------------------------
block:
  echo "Test 7: batched manifest sync (N merges → 1 write)"
  let base = tmpBase()
  let certDir = base / "certs"
  createDir(certDir)
  let manifestPath = certDir / "manifest.json"
  # Mirror atomicWriteManifest's own journal-root resolution (vault_manifest.nim)
  let resolvedRoot = repoRootForPath(manifestPath)
  let journalBase = if resolvedRoot.len > 0: resolvedRoot else: manifestPath.parentDir()

  proc vaultManifestWriteCount(root: string): int =
    let ids = listCommitIds(root)
    expect(ids.ok, "listCommitIds ok: " & (if ids.isErr(): ids.error else: ""))
    for id in ids.value:
      let rc = readCommit(root, id)
      expect(rc.ok, "readCommit ok for " & id)
      if rc.value.solverInvocation == "vault-manifest":
        inc result

  # The batched engine sequence: load once, merge N results, persist once.
  var manifest = loadManifest(manifestPath)
  for i in 1 .. 4:
    manifest.mergeResult("f" & $i, "src/mod" & $i & ".nim", "hash" & $i,
      "certGreen", "smFFI")
  manifest.atomicWriteManifest(manifestPath)

  expect(vaultManifestWriteCount(journalBase) == 1,
    "batched sync: exactly 1 vault-manifest journal record")

  # All N entries land in the manifest, in insertion order.
  let reloaded = loadManifest(manifestPath)
  expect(reloaded.entries.len == 4, "manifest carries 4 entries")
  expect(reloaded.entries.mapIt(it.functionName) == @["f1", "f2", "f3", "f4"],
    "entry insertion order preserved")

  # Determinism: rewriting the identical entry set yields byte-identical
  # manifest bytes (timestamps are fixed at merge time, not write time).
  let firstBytes = readFile(manifestPath)
  manifest.atomicWriteManifest(manifestPath)
  expect(readFile(manifestPath) == firstBytes,
    "same entry set → byte-identical manifest rewrite")
  expect(vaultManifestWriteCount(journalBase) == 1,
    "identical rewrite keeps exactly 1 journal record (content-addressed)")

  # Counter sensitivity: the per-item pattern (persist inside the merge loop)
  # leaves one journal record per entry — proving the counter counts
  # atomicWriteManifest invocations, so a regression back to per-item writes
  # fails the assertion above.
  let perItemBase = tmpBase()
  let perItemDir = perItemBase / "certs"
  createDir(perItemDir)
  let perItemPath = perItemDir / "manifest.json"
  let perItemRoot = repoRootForPath(perItemPath)
  let perItemJournal = if perItemRoot.len > 0: perItemRoot else: perItemPath.parentDir()
  var perItem = loadManifest(perItemPath)
  for i in 1 .. 4:
    perItem.mergeResult("g" & $i, "src/mod" & $i & ".nim", "ihash" & $i,
      "certGreen", "smFFI")
    perItem.atomicWriteManifest(perItemPath)
  expect(vaultManifestWriteCount(perItemJournal) == 4,
    "per-item sync: 4 entries → 4 vault-manifest journal records")

  echo "  PASSED: batched manifest sync"

echo ""
if failures == 0:
  echo "=== All Wave 5b TrustCommit tests PASSED ==="
else:
  echo "=== " & $failures & " Wave 5b test(s) FAILED ==="
  quit(1)