import std/options
import std/os
import std/strutils
import std/tempfiles
import std/json
import std/tables
import core/results
import core/crypto/hash_kernel
import core/io/io_utils
import core/proof/proof_integrity
import core/trusted/axiom_pragmas
import core/trusted/scope_identity
import core/trusted/trust_commit
import core/types/certificate_types
import verification/batch_uap/pbt_adapter
import verification/proof_state_builder

## Test suite for trust_commit.nim (Step 2).
## Covers: identity determinism, durable single-file persistence, validation
## invariants (I5 fail-closed), round-trip serialization, and chaining via
## parentCommit.

var failures = 0

proc expect(cond: bool; msg: string) =
  if not cond:
    inc failures
    echo "  FAIL: " & msg

var baseCounter = 0
proc tmpBase(): string =
  inc baseCounter
  let d = getTempDir() / "axiom_tc_test" / ($getCurrentProcessId() & "_" & $baseCounter)
  if not dirExists(d):
    createDir(d)
  d

proc mkCommit(evidenceId, claim, solver, scope, config: string;
              parent: Option[string] = none(string)): TrustCommit =
  TrustCommit(kind: tcVerifiedProof, evidenceId: evidenceId, claim: claim,
              solverInvocation: solver, attestation: "att", certificateDigest: "cd",
              scopeDigest: scope, configDigest: config, parentCommit: parent)

proc makePbtClaim(irHash, modulePath: string): string =
  let cert = %*{
    "irHash": irHash,
    "functionName": "prop_add_commutes",
    "kind": "empirical",
    "status": "certPseudoVerified",
    "modulePath": modulePath,
    "sourcePath": modulePath,
    "isKernel": false,
    "expectedObligation": false,
    "pbt": {
      "seed": 12345,
      "durationMs": 17
    }
  }
  $cert

echo "=== trust_commit tests ==="

# --- 1. Identity determinism ---
block:
  let e1 = computeEvidenceId("claim1", "solver1", "cert1")
  let e2 = computeEvidenceId("claim1", "solver1", "cert1")
  expect(e1 == e2, "evidenceId deterministic")
  let e3 = computeEvidenceId("claim2", "solver1", "cert1")
  expect(e1 != e3, "evidenceId order/content sensitive")

  let id1 = computeCommitId(tcVerifiedProof, e1, "scopeA", "cfgA", none(string))
  let id2 = computeCommitId(tcVerifiedProof, e1, "scopeA", "cfgA", none(string))
  expect(id1 == id2, "commitId deterministic")
  let id3 = computeCommitId(tcVerifiedProof, e1, "scopeB", "cfgA", none(string))
  expect(id1 != id3, "commitId sensitive to scopeDigest")
  let id4 = computeCommitId(tcVerifiedProof, e1, "scopeA", "cfgA", some("parentX"))
  expect(id1 != id4, "commitId sensitive to parent")
  echo "Test 1 PASSED: identity determinism + sensitivity"

# --- 2. validateCommit invariants (I5 fail-closed) ---
block:
  let v = mkCommit(computeEvidenceId("c", "s", "cd"), "c", "s", "scope", "cfg")
  let ok = validateCommit(v)
  expect(ok.ok, "valid commit accepted")

  var emptyEv = mkCommit("", "c", "s", "scope", "cfg")
  expect(validateCommit(emptyEv).isErr, "empty evidenceId rejected")

  var emptyScope = mkCommit(computeEvidenceId("c", "s", "cd"), "c", "s", "", "cfg")
  expect(validateCommit(emptyScope).isErr, "empty scopeDigest rejected")

  # evidenceId mismatch vs embedded content -> tamper detected
  var tampered = mkCommit("deadbeef", "c", "s", "scope", "cfg")
  expect(validateCommit(tampered).isErr, "evidenceId/content mismatch rejected")
  echo "Test 2 PASSED: validateCommit fail-closed invariants"

# --- 3. Durable persistence + read-back round trip ---
block:
  let base = tmpBase()
  # evidenceId must bind to the ACTUAL embedded content (validateCommit recomputes it)
  let evidenceId = computeEvidenceId("claimJSON", "solverJSON", "cd")
  let c = mkCommit(evidenceId, "claimJSON", "solverJSON", "scopeDig", "cfgDig", some("parent0"))
  let res = commitVerification(base, c)
  expect(res.ok, "commitVerification ok, got: " & (if res.isErr: res.error else: ""))
  let cid = res.value
  let path = commitPath(base, cid)
  expect(fileExists(path), "journal file created at <commitId>.json")
  # File holds exactly ONE TrustCommit record (canonical pretty-printed JSON
  # object, possibly multi-line). Re-parse as a single commit to prove it.
  expect(commitFromJson(readFile(path)).isOk,
         "journal file holds exactly one parseable TrustCommit record")
  let back = readCommit(base, cid)
  expect(back.ok, "readCommit ok")
  expect(back.value.claim == "claimJSON", "claim round-trip")
  expect(back.value.solverInvocation == "solverJSON", "solver round-trip")
  expect(back.value.scopeDigest == "scopeDig", "scope round-trip")
  expect(back.value.parentCommit.isSome and back.value.parentCommit.get == "parent0",
         "parentCommit round-trip")
  expect(back.value.evidenceId == evidenceId, "evidenceId round-trip")
  # validate the persisted form
  expect(validateCommit(back.value).ok, "persisted commit re-validates")
  echo "Test 3 PASSED: durable persistence + round trip"

# --- 4. readCommit fail-closed ---
block:
  let base = tmpBase()
  let missing = readCommit(base, "0000000000000000000000000000000000000000")
  expect(missing.isErr, "missing commit -> err (fail-closed)")
  echo "Test 4 PASSED: readCommit fail-closed on absence"

# --- 5. Chaining: parent-dependent commitId + monotonic journal ---
block:
  let base = tmpBase()
  # mkCommit hardcodes certificateDigest="cd"; evidenceId must match embedded content
  let evidenceId = computeEvidenceId("c1", "s1", "cd")
  let c1 = mkCommit(evidenceId, "c1", "s1", "scope", "cfg")
  let r1 = commitVerification(base, c1)
  expect(r1.ok, "commit1 ok")
  let c2 = mkCommit(computeEvidenceId("c2", "s2", "cd"), "c2", "s2", "scope", "cfg",
                    some(r1.value))
  let r2 = commitVerification(base, c2)
  expect(r2.ok, "commit2 ok")
  expect(r1.value != r2.value, "child commit id differs from parent")
  expect(fileExists(commitPath(base, r1.value)), "parent file exists")
  expect(fileExists(commitPath(base, r2.value)), "child file exists")
  let r3 = commitVerification(base, mkCommit(computeEvidenceId("c3", "s3", "cd"),
                "c3", "s3", "scope2", "cfg", some(r1.value)))
  expect(r3.ok, "commit3 ok")
  expect(r2.value != r3.value, "sibling commits differ on scope/content")
  echo "Test 5 PASSED: chaining + distinct commit ids"

# --- 6. Journal replay (I4): chain ordering, state digest, fail-closed ---
block:
  let base = tmpBase()
  # c1 (root) -> c2 (child of c1) -> c3 (child of c2)
  let r1 = commitVerification(base, mkCommit(computeEvidenceId("a", "s", "cd"), "a", "s", "scope", "cfg"))
  expect(r1.ok, "replay commit1 ok")
  let r2 = commitVerification(base, mkCommit(computeEvidenceId("b", "s", "cd"), "b", "s", "scope", "cfg", some(r1.value)))
  expect(r2.ok, "replay commit2 ok")
  let r3 = commitVerification(base, mkCommit(computeEvidenceId("c", "s", "cd"), "c", "s", "scope", "cfg", some(r2.value)))
  expect(r3.ok, "replay commit3 ok")

  let st = replayJournal(base)
  expect(st.ok, "replayJournal ok: " & (if st.isErr: st.error else: ""))
  let state = st.value
  expect(state.commitIds.len == 3, "replay reconstructs all 3 commits")
  expect(state.commitIds == @[r1.value, r2.value, r3.value],
         "replay orders by parent chain (root first)")
  expect(state.scopeDigest == "scope", "replay carries final scopeDigest")
  expect(state.configDigest == "cfg", "replay carries final configDigest")
  expect(state.stateDigest == computeStateDigest(state.commitIds),
         "replay stateDigest matches recomputed digest")
  echo "Test 6 PASSED: journal replay chain + state digest"

# --- 7. Replay fail-closed on corrupt commit / orphan parent ---
block:
  # orphan parent: child references a parent id that has no journal file
  let base2 = tmpBase()
  let orphan = mkCommit(computeEvidenceId("x", "s", "cd"), "x", "s", "scope", "cfg", some("deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"))
  let rO = commitVerification(base2, orphan)
  expect(rO.ok, "orphan commit writes ok")
  let st2 = replayJournal(base2)
  expect(st2.isErr, "replay fails closed on orphan parent: " & (if st2.ok: "state returned" else: st2.error))
  echo "Test 7 PASSED: replay fail-closed on orphan parent"

# --- 8. Replay fail-closed on corrupt commit / orphan parent ---
block:
  # orphan parent: child references a parent id that has no journal file
  let base2 = tmpBase()
  let orphan = mkCommit(computeEvidenceId("x", "s", "cd"), "x", "s", "scope", "cfg", some("deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"))
  let rO = commitVerification(base2, orphan)
  expect(rO.ok, "orphan commit writes ok")
  let st2 = replayJournal(base2)
  expect(st2.isErr, "replay fails closed on orphan parent: " & (if st2.ok: "state returned" else: st2.error))
  echo "Test 7 PASSED: replay fail-closed on orphan parent"

# --- 8. PBT claim identity is bound to the embedded certificate digest ---
block:
  let base = tmpBase()
  let irHash = "pbt-irhash-8"
  let claim = makePbtClaim(irHash, "src/example/add.nim")
  let certificateDigest = hash_kernel.sha256Hex(claim)
  let solverInvocation = "pbt:<" & irHash & ">"
  let evidenceId = computeEvidenceId(claim, solverInvocation, certificateDigest)
  let scopeDigest = canonicalScopeDigest(CanonicalScopeInput(
    kernelSymbols: @[],
    kernelExemptSymbols: @[],
    kernelTotal: 0,
    vksTotal: 0,
    profileIdentity: hash_kernel.sha256Hex("pbt-empirical-v1"),
    protocolVersion: "pbt-v1"
  ))
  let configDigest = configIdentityDigest(hash_kernel.sha256Hex("pbt-empirical-v1"), hash_kernel.sha256Hex("missing:verification_scope.lock"))
  let c = TrustCommit(
    kind: tcVerifiedProof,
    evidenceId: evidenceId,
    claim: claim,
    solverInvocation: solverInvocation,
    attestation: "",
    certificateDigest: certificateDigest,
    scopeDigest: scopeDigest,
    configDigest: configDigest,
    parentCommit: none(string)
  )
  expect(validateCommit(c).ok, "PBT TrustCommit shape validates")
  let res = commitVerification(base, c)
  expect(res.ok, "PBT commitVerification ok: " & (if res.isErr: res.error else: ""))
  let cid = res.value
  expect(fileExists(commitPath(base, cid)), "PBT journal file exists")
  let back = readCommit(base, cid)
  expect(back.ok and back.value.claim == claim, "PBT commit round-trip preserves claim")
  let replay = replayJournal(base)
  expect(replay.ok and replay.value.commitIds == @[cid], "PBT journal replay admits exactly one commit")

  var changedCert = c
  changedCert.certificateDigest = "different-digest"
  expect(computeEvidenceId(claim, solverInvocation, changedCert.certificateDigest) != evidenceId,
         "changing certificateDigest changes PBT evidenceId")
  echo "Test 8 PASSED: PBT TrustCommit identity + durable replay"

# --- 9. PBT adapter writes TrustCommit only and proof_state_builder ignores stale empirical vault certs ---
block:
  let base = tmpBase()
  let repo = base / "repo"
  createDir(repo)
  createDir(repo / "data")
  createDir(repo / ".axiom")
  createDir(repo / ".axiom" / "vault")
  writeFile(repo / "data" / "verification_scope.lock", "{\"kernel_total\":0,\"vksTotal\":0,\"kernel_symbols\":[],\"kernel_exempt_symbols\":[]}")
  let stalePath = getCanonicalCertFilename(repo, "stale-pbt")
  writeFile(stalePath, pretty(%*{
    "irHash": "stale-pbt",
    "functionName": "prop_add_commutes",
    "kind": "empirical",
    "status": "certGreen",
    "modulePath": "src/example/add.nim",
    "sourcePath": "src/example/add.nim",
    "isKernel": false,
    "expectedObligation": false,
    "pbt": {"seed": 1, "durationMs": 2}
  }))

  let entry = RuntimeAxiomEntry(
    name: "prop_add_commutes",
    irSerialized: "__opaque__",
    smtSource: "",
    leanSource: "",
    sourcePath: "src/example/add.nim",
    isKernel: false,
    irHash: "pbt-irhash-9",
    effectKind: Pure,
    bmcSkippable: false,
    expectedObligation: false
  )
  pbt_adapter.pbtRegistry = initTable[string, pbt_adapter.PbtProperty]()
  pbt_adapter.pbtRegistry[entry.name] = proc() = discard

  executePbtAndWriteCert(entry, repo)
  expect(fileExists(stalePath), "standalone stale empirical cert remains untouched")
  let journalReplay = replayJournal(repo)
  expect(journalReplay.ok and journalReplay.value.commitIds.len == 1,
         "PBT adapter writes one TrustCommit journal entry")
  let cid = journalReplay.value.commitIds[0]
  let journalPath = commitPath(repo, cid)
  expect(fileExists(journalPath), "TrustCommit journal file exists")

  let (journalState, journalCerts) = hydrateProofStateFromTrustCommitJournal(repo)
  expect(journalState.getOrDefault("summary").getOrDefault("pseudoVerified").getInt(0) == 1,
         "proof_state_builder hydrates one pseudo-verified PBT entry from TrustCommit")
  expect(journalCerts.len == 1, "proof_state_builder returns one PBT FunctionCertificate")
  expect(journalCerts[0].status == certPseudoVerified, "PBT FunctionCertificate status is certPseudoVerified")
  expect(string(journalCerts[0].certificatePath) == journalPath, "PBT FunctionCertificate path points at journal")

  # vault hydration merges the authoritative journal (1 pseudo-verified PBT
  # entry) but must NOT additionally promote the stale standalone empirical cert.
  let (vaultState, vaultCerts) = hydrateProofStateFromCertificateVault(repo / ".axiom" / "vault", repo)
  expect(vaultState.getOrDefault("summary").getOrDefault("pseudoVerified").getInt(0) == 1,
         "vault hydration reports the one journal PBT entry as pseudo-verified (stale empirical cert not promoted)")
  expect(vaultCerts.len == 1, "vault hydration returns exactly the journal PBT cert, not the stale empirical cert")
  echo "Test 9 PASSED: PBT adapter journal-only path and proof_state_builder consumer"

# --- 10. readCommit is content-addressed: consistent journal tamper fails closed ---
block:
  let base = tmpBase()
  let evidenceId = computeEvidenceId("claimA", "solverA", "cd")
  let c = mkCommit(evidenceId, "claimA", "solverA", "scopeA", "cfgA")
  let res = commitVerification(base, c)
  expect(res.ok, "commitVerification ok: " & (if res.isErr: res.error else: ""))
  let cid = res.value

  # (a) A valid record written through commitVerification reads back through the
  # validated read path — existing behavior preserved.
  let back = readCommit(base, cid)
  expect(back.ok, "readCommit succeeds for valid record: " &
    (if back.isErr: back.error else: ""))

  # (b) CONSISTENT tamper: rewrite the content under the SAME filename with a
  # recomputed evidenceId, so structural validateCommit alone would accept it —
  # only the content-addressing check can reject this.
  var tampered = back.value
  tampered.claim = "tampered claim content"
  tampered.evidenceId = computeEvidenceId(tampered.claim, tampered.solverInvocation,
                                          tampered.certificateDigest)
  expect(validateCommit(tampered).ok,
         "test preconditions: tampered record passes structural validation")
  expect(computeCommitId(tampered.kind, tampered.evidenceId, tampered.scopeDigest,
                         tampered.configDigest, tampered.parentCommit) != cid,
         "test preconditions: tampered content hashes to a different commitId")
  writeFile(commitPath(base, cid), commitToJson(tampered))
  let mismatch = readCommit(base, cid)
  expect(mismatch.isErr,
         "readCommit rejects content-addressed mismatch (same filename, altered content)")
  expect(mismatch.isErr and mismatch.error.contains("content-addressing mismatch"),
         "rejection is the content-addressing guard: " &
    (if mismatch.isErr: mismatch.error else: ""))

  # (c) INCONSISTENT tamper: evidenceId left stale against rewritten content ->
  # structural validation fails closed on read.
  var stale = back.value
  stale.claim = "rewritten content, stale evidenceId"
  writeFile(commitPath(base, cid), commitToJson(stale))
  let invalid = readCommit(base, cid)
  expect(invalid.isErr, "readCommit rejects structurally invalid record: " &
    (if invalid.ok: "ok returned" else: invalid.error))

  # (d) replayJournal parses through the same validated read: the consistently
  # tampered journal must fail closed, not silently enter trust state.
  writeFile(commitPath(base, cid), commitToJson(tampered))
  let replay = replayJournal(base)
  expect(replay.isErr, "replayJournal fails closed on consistently tampered journal: " &
    (if replay.ok: "state returned" else: replay.error))

  echo "Test 10 PASSED: readCommit content-addressing (tamper fail-closed)"

echo ""
if failures == 0:
  echo "=== All trust_commit tests PASSED ==="
else:
  echo "=== " & $failures & " trust_commit test(s) FAILED ==="
  quit(1)
