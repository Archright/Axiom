import std/[base64, json, strutils, algorithm]
import core/crypto/hash_kernel
import core/results
import verification/canonical_json
import verification/evidence_ledger
import verification/ledger_side_ref
import verification/verification_subject

## Evidence CAS ledger tests (durable side-ref evidence store).
##
## Isolation: the ledger talks to GitHub's REST Git Data API through the
## injectable LedgerTransport, so these tests run against an in-memory
## FakeBackend (same approach as the P11 side-ref ledger block in
## tests/verification/test_attestation.nim) — no git commands, no network,
## and the real repository's refs are never touched. The default ledger ref
## (EvidenceCasRefName = refs/heads/axiom/evidence-cas) is likewise never
## consulted: every call targets the injected fake via its transport.
##
## Coverage:
##   E1  append → lookup roundtrip (absent ref → root + FF append; verified
##       payload reuse on lookup)
##   E2  idempotent re-append of the same key → existing entry returned,
##       no duplicate, no second CAS write
##   E3  distinct keys → distinct records (no cross-contamination, sorted
##       listing)
##   E4  tamper detection: one flipped payload byte → lookup fails closed;
##       evidenceKey rewritten inside a stored record → identity mismatch
##       fail-closed; missing key → fail-closed
##   E5  persistent non-FF move → bounded retry exhaustion → fail-closed
##       (4 attempts, tip never advances, no entry lands)
##   E6  absent ref: hasEvidence = MISS (ok(false)); lookup = fail-closed
##   E7  record validation (pure): malformed inputs rejected (including
##       missing / malformed evidenceDigest); a corrupt record never touches
##       the transport
##   E8  malformed blob response → fail-closed
##   E9  root-only ledger (empty tree): listing = ok(@[]), valid key = MISS,
##       and the FIRST append succeeds (empty-tree normalization)
##   E10 append on an already-poisoned empty-tree ROOT tip lands (no ref
##       repair) — regression for the SL-15 404 state
##   E11 the rooting attempt skips the exactly-once re-check (zero reads);
##       pre-existing tips still re-check; idempotency preserved
##   E12 fail-closed preserved: a 404 on a NON-empty tree and a malformed
##       commit response stay errors, never an absence

var failures = 0

proc expect(cond: bool; msg: string) =
  if not cond:
    inc failures
    echo "  FAIL: " & msg

proc checkEqStr(name: string; got, exp: string) =
  if got == exp:
    echo "  [PASS] " & name
  else:
    inc failures
    echo "  FAIL: " & name & "\n      got: " & got & "\n      exp: " & exp

# ---------------------------------------------------------------------------
# Fake transport backend (in-memory git object store)
# ---------------------------------------------------------------------------

type
  EvidenceEntry = object
    path: string
    content: string
    sha: string

  FakeBackend = ref object
    tip: string
    entries: seq[EvidenceEntry]
    counter: int
    rejectPatch: bool
    omitBlobContent: bool
    fetchCalls: int
    postCalls: int
    patchCalls: int
    pendingSha: string
    pendingPath: string
    pendingContent: string

proc fakeSha(prefix: string; b: FakeBackend): string =
  inc b.counter
  sha256Hex(prefix & $b.counter & "evidence-cas-fixture")[0 ..< 40]

proc seedEntry(b: FakeBackend; path, content: string) =
  b.entries.add(EvidenceEntry(path: path, content: content, sha: fakeSha("seed", b)))

const NonEmptyFakeTreeSha = "e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1"
  ## Fixed non-empty tree sha served by the fake commit reader — the existing
  ## /git/trees/ handler answers any tree sha with the current entries.

proc makeTransport(b: FakeBackend): LedgerTransport =
  var fetch: JsonFetcher = proc(url: string): Result[JsonNode, string] {.raises: [CatchableError, OSError, Exception].} =
    inc b.fetchCalls
    if url.contains("/git/commits/"):
      # Commit → tree resolution (fetchTipTree): zero entries ⇔ empty tree
      # (the ledger ROOT commit's tree — not a fetchable object on GitHub).
      let treeSha = if b.entries.len == 0: EmptyTreeSha else: NonEmptyFakeTreeSha
      return ok(%*{"sha": url[(url.rfind("/") + 1) .. ^1], "tree": {"sha": treeSha}})
    if url.contains("/git/trees/"):
      var entries = newJArray()
      for e in b.entries:
        entries.add(%*{"path": e.path, "type": "blob", "sha": e.sha})
      return ok(%*{"tree": entries})
    if url.contains("/git/blobs/"):
      let sha = url[(url.rfind("/") + 1) .. ^1]
      for e in b.entries:
        if e.sha == sha:
          let content = if b.omitBlobContent: "" else: encode(e.content)
          return ok(%*{"content": content, "encoding": "base64"})
      return err("fake fetch: unknown blob " & sha)
    err("fake fetch: unexpected " & url)
  var post: JsonPoster = proc(url: string; body: string): Result[JsonNode, string] {.raises: [CatchableError, OSError, Exception].} =
    inc b.postCalls
    if url.contains("/git/blobs"):
      # Content-addressed store: the blob sha is derived from the stored bytes.
      b.pendingContent = parseJson(body).getOrDefault("content").getStr("")
      b.pendingSha = fakeSha("blob:" & b.pendingContent, b)
      return ok(%*{"sha": b.pendingSha})
    if url.contains("/git/trees"):
      let treeEntry = parseJson(body){"tree"}[0]
      b.pendingPath = treeEntry.getOrDefault("path").getStr("")
      return ok(%*{"sha": fakeSha("tree", b)})
    if url.contains("/git/commits"):
      return ok(%*{"sha": fakeSha("commit", b)})
    if url.contains("/git/refs"):
      return ok(%*{"sha": fakeSha("ref", b)})
    err("fake post: unexpected " & url)
  var patch: JsonPatcher = proc(url: string; body: string): Result[JsonNode, string] {.raises: [CatchableError, OSError, Exception].} =
    inc b.patchCalls
    if b.rejectPatch:
      return err("GitHub API PATCH " & url & " -> 422: is not fast-forward")
    let newSha = parseJson(body).getOrDefault("sha").getStr("")
    # FF commit lands: the pending object pipeline materializes as an entry.
    b.entries.add(EvidenceEntry(path: b.pendingPath, content: b.pendingContent, sha: b.pendingSha))
    b.tip = newSha
    ok(%*{"object": {"type": "commit", "sha": newSha}})
  var tip: LedgerTipFetcher = proc(repo: string): Result[string, string] {.raises: [CatchableError, OSError, Exception].} =
    ok(b.tip)
  LedgerTransport(fetch: fetch, post: post, patch: patch, tip: tip)

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

const StoredAtA = "2026-10-06T00:00:00Z"
const StoredAtB = "2026-10-06T00:00:01Z"

let payloadA = canonicalJsonString(%*{"normalized": "evidence-A", "verdict": "krPassed"})
let payloadB = canonicalJsonString(%*{"normalized": "evidence-B", "verdict": "krPassed"})
# Evidence keys are opaque 64-hex identities produced OUTSIDE this module
# (evidence key derivation lives in the producer layer); they are NOT the
# payload hash.
let keyA = sha256Hex("axiom.evidence.cas.v1\nkey-wire-A")
let keyB = sha256Hex("axiom.evidence.cas.v1\nkey-wire-B")

let digestsA = %*{
  "attestation": "sha256:" & sha256Hex("att-a"),
  "verdict": "sha256:" & sha256Hex("verdict-a")
}
let digestsB = %*{"attestation": "sha256:" & sha256Hex("att-b")}

# Evidence digests: the producer's binding digest, opaque to this module (each
# producer computes it from its own single definition — ADR-0034). Distinct
# from the payload hashes below.
let digestA = sha256Hex("evidence-bundle-wire-A")
let digestB = sha256Hex("evidence-bundle-wire-B")

proc fixtureRecord(key, payload: string; digests: JsonNode; storedAt,
                   evidenceDigest: string): EvidenceCasRecord =
  let built = makeEvidenceRecord(key, payload, digests, storedAt, evidenceDigest)
  if built.isErr:
    echo "  FAIL: fixture record construction refused: " & built.error
    inc failures
  built.get

let recA = fixtureRecord(keyA, payloadA, digestsA, StoredAtA, digestA)
let recB = fixtureRecord(keyB, payloadB, digestsB, StoredAtB, digestB)

proc canonicalOf(rec: EvidenceCasRecord): string =
  evidenceRecordToCanonicalJson(rec)

echo "=== evidence-cas ledger tests ==="

# --- E1: append → lookup roundtrip (root creation on absent ref) ---
block:
  let b1 = FakeBackend(tip: "", entries: @[], counter: 0, rejectPatch: false,
    omitBlobContent: false, fetchCalls: 0, postCalls: 0, patchCalls: 0)
  let t1 = makeTransport(b1)
  expect(hasEvidence(t1, "owner/repo", keyA).get == false, "E1: fresh ledger is a MISS for keyA")
  let appended = appendEvidence(t1, "owner/repo", recA)
  expect(appended.isOk, "E1: append succeeds on absent ref: " &
    (if appended.isErr: appended.error else: ""))
  if appended.isOk:
    expect(appended.get.alreadyPresent == false, "E1: first append is not a no-op")
    expect(appended.get.tipSha == b1.tip, "E1: outcome tip == backend tip")
    expect(appended.get.tipSha.len == 40, "E1: tip is a 40-char OID")
    expect(appended.get.record.evidenceKey == keyA, "E1: outcome record carries the key")
  checkEqStr("E1: exactly one FF CAS ref update", $b1.patchCalls, "1")
  let hit = hasEvidence(t1, "owner/repo", keyA)
  expect(hit.isOk and hit.get == true, "E1: hasEvidence = HIT after append")
  let fetched = fetchEvidenceRecord(t1, "owner/repo", keyA)
  expect(fetched.isOk, "E1: fetchEvidenceRecord succeeds: " &
    (if fetched.isErr: fetched.error else: ""))
  if fetched.isOk:
    expect(fetched.get.evidenceKey == recA.evidenceKey, "E1: evidenceKey round-trips")
    expect(fetched.get.payload == payloadA, "E1: payload round-trips byte-exact")
    expect(fetched.get.payloadSha256 == recA.payloadSha256, "E1: payloadSha256 round-trips")
    expect(fetched.get.evidenceDigest == digestA, "E1: evidenceDigest round-trips")
    expect(fetched.get.storedAtUtc == StoredAtA, "E1: storedAtUtc round-trips")
    expect(fetched.get.verifierArtifactDigests == digestsA, "E1: verifierArtifactDigests round-trips")
  let lookedUp = lookupEvidence(t1, "owner/repo", keyA)
  expect(lookedUp.isOk and lookedUp.get == payloadA,
    "E1: lookupEvidence returns the exact payload bytes")
  echo "Test E1 PASSED: append → lookup roundtrip"

# --- E2: idempotent re-append of the same key returns the existing entry ---
block:
  let b2 = FakeBackend(tip: "", entries: @[], counter: 0, rejectPatch: false,
    omitBlobContent: false, fetchCalls: 0, postCalls: 0, patchCalls: 0)
  let t2 = makeTransport(b2)
  let first = appendEvidence(t2, "owner/repo", recA)
  expect(first.isOk, "E2: first append succeeds")
  let tipAfterFirst = b2.tip
  let patchesAfterFirst = b2.patchCalls
  # A re-run with the SAME logical evidence (same payload bytes → same
  # payloadSha256; storedAtUtc is audit-only and may differ) must be an
  # idempotent no-op returning the EXISTING entry.
  let rerunRecord = fixtureRecord(keyA, payloadA, digestsA, StoredAtB, digestA)
  let second = appendEvidence(t2, "owner/repo", rerunRecord)
  expect(second.isOk, "E2: re-append succeeds (idempotent): " &
    (if second.isErr: second.error else: ""))
  if second.isOk:
    expect(second.get.alreadyPresent == true, "E2: re-append is a no-op (alreadyPresent)")
    expect(second.get.tipSha == tipAfterFirst, "E2: tip unchanged by no-op append")
    expect(second.get.record.payload == payloadA, "E2: outcome carries the EXISTING payload")
    expect(second.get.record.storedAtUtc == StoredAtA,
      "E2: outcome carries the FIRST entry's audit timestamp (no rewrite)")
  checkEqStr("E2: re-append performs zero CAS ref updates", $b2.patchCalls, $patchesAfterFirst)
  checkEqStr("E2: exactly one ledger entry after re-append", $b2.entries.len, "1")
  let list2 = listEvidenceKeys(t2, "owner/repo")
  expect(list2.isOk and list2.get == @[keyA], "E2: ledger lists exactly the one key")
  echo "Test E2 PASSED: idempotent re-append, no duplication"

# --- E3: distinct keys → distinct records ---
block:
  let b3 = FakeBackend(tip: "", entries: @[], counter: 0, rejectPatch: false,
    omitBlobContent: false, fetchCalls: 0, postCalls: 0, patchCalls: 0)
  let t3 = makeTransport(b3)
  let appA = appendEvidence(t3, "owner/repo", recA)
  expect(appA.isOk and not appA.get.alreadyPresent, "E3: keyA append lands")
  let tipA = b3.tip
  let appB = appendEvidence(t3, "owner/repo", recB)
  expect(appB.isOk and not appB.get.alreadyPresent, "E3: keyB append lands")
  expect(b3.tip != tipA, "E3: tip advanced for the second record")
  checkEqStr("E3: two entries for two keys", $b3.entries.len, "2")
  let lookupA = lookupEvidence(t3, "owner/repo", keyA)
  let lookupB = lookupEvidence(t3, "owner/repo", keyB)
  expect(lookupA.isOk and lookupA.get == payloadA, "E3: keyA reuses payloadA")
  expect(lookupB.isOk and lookupB.get == payloadB, "E3: keyB reuses payloadB")
  let list3 = listEvidenceKeys(t3, "owner/repo")
  expect(list3.isOk and list3.get == sorted(@[keyA, keyB]),
    "E3: listing returns both keys sorted")
  expect(lookupEvidence(t3, "owner/repo", sha256Hex("axiom.evidence.cas.v1\nkey-wire-C")).isErr,
    "E3: unknown key → fail-closed (never a payload from another key)")
  echo "Test E3 PASSED: distinct keys, distinct records"

# --- E4: tamper detection — fail-closed reads ---
block:
  let b4 = FakeBackend(tip: "", entries: @[], counter: 0, rejectPatch: false,
    omitBlobContent: false, fetchCalls: 0, postCalls: 0, patchCalls: 0)
  let t4 = makeTransport(b4)
  expect(appendEvidence(t4, "owner/repo", recA).isOk, "E4: seed append succeeds")
  # Flip ONE byte of the stored payload inside the fixture blob: the record
  # JSON still parses, but sha256(payload) no longer equals payloadSha256.
  var stored = parseJson(b4.entries[0].content)
  var flippedPayload = payloadA
  flippedPayload[7] = 'X'
  stored["payload"] = %flippedPayload
  b4.entries[0].content = $stored
  let tamperedLookup = lookupEvidence(t4, "owner/repo", keyA)
  expect(tamperedLookup.isErr, "E4: tampered payload → lookup fails closed")
  expect(tamperedLookup.isErr and tamperedLookup.error.contains("sha256(payload)"),
    "E4: tamper error names the re-hash mismatch")
  expect(tamperedLookup.isErr and tamperedLookup.error.contains("fail-closed"),
    "E4: tamper error is fail-closed")
  let membership = hasEvidence(t4, "owner/repo", keyA)
  expect(membership.isOk and membership.get == true,
    "E4: membership is intact (HIT) — the CORRUPTION is caught at read, not masked as a MISS")
  # Restore, then tamper the identity: rewrite evidenceKey inside the stored
  # record → the read must refuse the key mismatch.
  b4.entries[0].content = canonicalOf(recA)
  var keyTampered = parseJson(b4.entries[0].content)
  keyTampered["evidenceKey"] = %keyB
  b4.entries[0].content = $keyTampered
  let keyMismatch = fetchEvidenceRecord(t4, "owner/repo", keyA)
  expect(keyMismatch.isErr, "E4: rewritten evidenceKey → fetch fails closed")
  expect(keyMismatch.isErr and keyMismatch.error.contains("!= requested"),
    "E4: identity mismatch error names requested vs stored key")
  echo "Test E4 PASSED: tamper detection (payload byte flip + identity rewrite)"

# --- E5: persistent non-FF move → bounded retry exhaustion → fail-closed ---
block:
  let b5 = FakeBackend(tip: sha256Hex("evidence-cas-tip-fixture-5")[0 ..< 40],
    entries: @[], counter: 0, rejectPatch: true,
    omitBlobContent: false, fetchCalls: 0, postCalls: 0, patchCalls: 0)
  let t5 = makeTransport(b5)
  let tipBefore = b5.tip
  let conflicted = appendEvidence(t5, "owner/repo", recA)
  expect(conflicted.isErr, "E5: persistent conflict → fail-closed")
  expect(conflicted.error.contains("concurrent evidence ledger append conflict after 4 attempts"),
    "E5: exhaustion states the bounded attempt budget")
  expect(conflicted.error.contains("422"), "E5: exhaustion carries the last 422 conflict error")
  checkEqStr("E5: exactly 4 CAS PATCH attempts (no early give-up, no extra)", $b5.patchCalls, "4")
  expect(b5.tip == tipBefore, "E5: tip never advanced")
  checkEqStr("E5: no entry ever landed under conflict", $b5.entries.len, "0")
  echo "Test E5 PASSED: non-FF conflict → bounded retry → fail-closed"

# --- E6: absent ref — MISS membership, fail-closed lookup ---
block:
  let b6 = FakeBackend(tip: "", entries: @[], counter: 0, rejectPatch: false,
    omitBlobContent: false, fetchCalls: 0, postCalls: 0, patchCalls: 0)
  let t6 = makeTransport(b6)
  let miss = hasEvidence(t6, "owner/repo", keyA)
  expect(miss.isOk and miss.get == false, "E6: absent ref = legitimate MISS")
  let absentLookup = lookupEvidence(t6, "owner/repo", keyA)
  expect(absentLookup.isErr, "E6: lookup on absent ref → fail-closed error, not empty payload")
  expect(absentLookup.error.contains("absent"), "E6: error names the absent ledger ref")
  echo "Test E6 PASSED: absent ref MISS vs fail-closed lookup"

# --- E7: record validation — malformed inputs rejected, corrupt record never touches transport ---
block:
  expect(makeEvidenceRecord("not-hex", payloadA, digestsA, StoredAtA, digestA).isErr,
    "E7: non-64-hex evidenceKey rejected")
  expect(makeEvidenceRecord(keyA, "", digestsA, StoredAtA, digestA).isErr,
    "E7: empty payload rejected")
  expect(makeEvidenceRecord(keyA, payloadA, %*{"x": 1}, StoredAtA, digestA).isErr,
    "E7: non-string digest value rejected")
  expect(makeEvidenceRecord(keyA, payloadA, newJArray(), StoredAtA, digestA).isErr,
    "E7: non-object digests rejected")
  expect(makeEvidenceRecord(keyA, payloadA, digestsA, "2026-10-06 00:00:00", digestA).isErr,
    "E7: non-canonical storedAtUtc rejected")
  expect(makeEvidenceRecord(keyA, payloadA, digestsA, StoredAtA, "not-hex").isErr,
    "E7: non-64-hex evidenceDigest rejected")
  expect(makeEvidenceRecord(keyA, payloadA, digestsA, StoredAtA, "").isErr,
    "E7: empty evidenceDigest rejected")
  let emptyDigests = makeEvidenceRecord(keyA, payloadA, nil, StoredAtA, digestA)
  expect(emptyDigests.isOk and emptyDigests.get.verifierArtifactDigests.kind == JObject,
    "E7: nil digests → empty object")
  # Canonical bytes round-trip through the strict parser.
  let parsed = parseEvidenceRecord(canonicalOf(recA))
  expect(parsed.isOk, "E7: canonical record parses: " &
    (if parsed.isErr: parsed.error else: ""))
  if parsed.isOk:
    expect(parsed.get.payload == payloadA, "E7: parsed payload matches")
    expect(parsed.get.evidenceDigest == digestA, "E7: parsed evidenceDigest matches")
  # A record WITHOUT evidenceDigest (old-generation record) fails the strict
  # parse — the ADR-0034 generation-cutover backstop.
  var missingDigest = parseJson(canonicalOf(recA))
  missingDigest.delete("evidenceDigest")
  let missingParsed = parseEvidenceRecord($missingDigest)
  expect(missingParsed.isErr and
    missingParsed.error.contains("missing or empty field 'evidenceDigest'"),
    "E7: old-format record without evidenceDigest rejected (fail-closed backstop)")
  # A record with a MALFORMED evidenceDigest also fails the strict parse.
  var malformedDigest = parseJson(canonicalOf(recA))
  malformedDigest["evidenceDigest"] = %"zzzz-not-hex"
  let malformedParsed = parseEvidenceRecord($malformedDigest)
  expect(malformedParsed.isErr and malformedParsed.error.contains("evidenceDigest"),
    "E7: malformed evidenceDigest rejected by the strict parser")
  # Foreign schemaVersion → fail-closed.
  var foreign = parseJson(canonicalOf(recA))
  foreign["schemaVersion"] = %"axiom.evidence.cas.v2"
  let foreignParsed = parseEvidenceRecord($foreign)
  expect(foreignParsed.isErr and foreignParsed.error.contains("schemaVersion"),
    "E7: foreign schemaVersion rejected")
  # Direct payloadSha256 lie → re-hash discipline catches it.
  var lied = parseJson(canonicalOf(recA))
  lied["payloadSha256"] = %sha256Hex("different-bytes")
  let liedParsed = parseEvidenceRecord($lied)
  expect(liedParsed.isErr and liedParsed.error.contains("sha256(payload)"),
    "E7: forged payloadSha256 rejected by re-hash")
  # A corrupt record must be refused BEFORE any transport call.
  let b7 = FakeBackend(tip: "", entries: @[], counter: 0, rejectPatch: false,
    omitBlobContent: false, fetchCalls: 0, postCalls: 0, patchCalls: 0)
  let t7 = makeTransport(b7)
  var corrupt = recA
  corrupt.payloadSha256 = sha256Hex("different-bytes")
  let corruptAppend = appendEvidence(t7, "owner/repo", corrupt)
  expect(corruptAppend.isErr, "E7: corrupt record append → fail-closed")
  checkEqStr("E7: corrupt record never touches the transport", $b7.fetchCalls, "0")
  checkEqStr("E7: corrupt record performs no POSTs", $b7.postCalls, "0")
  checkEqStr("E7: corrupt record performs no PATCHes", $b7.patchCalls, "0")
  echo "Test E7 PASSED: record validation + pre-transport corruption refusal"

# --- E8: malformed blob response → fail-closed ---
block:
  let b8 = FakeBackend(tip: sha256Hex("evidence-cas-tip-fixture-8")[0 ..< 40],
    entries: @[], counter: 0, rejectPatch: false,
    omitBlobContent: true, fetchCalls: 0, postCalls: 0, patchCalls: 0)
  b8.seedEntry(evidenceEntryName(keyA), canonicalOf(recA))
  let t8 = makeTransport(b8)
  let malformed = fetchEvidenceRecord(t8, "owner/repo", keyA)
  expect(malformed.isErr, "E8: blob response missing content → fail-closed")
  expect(malformed.error.contains("missing content"), "E8: error names the missing blob content")
  checkEqStr("E8: malformed read performs no CAS write", $b8.patchCalls, "0")
  echo "Test E8 PASSED: malformed blob response fail-closed"

# --- E9: root-only ledger (empty tree) — the FIRST append must succeed ---
# Production regression (observed 2026-10-06): a freshly rooted ledger's tip
# commit carries EmptyTreeSha, which GitHub never serves as a fetchable tree
# — every tree read 404'd, fail-closing the first append and all consults.
block:
  let b9 = FakeBackend(tip: sha256Hex("evidence-cas-root-fixture-9")[0 ..< 40],
    entries: @[], counter: 0, rejectPatch: false,
    omitBlobContent: false, fetchCalls: 0, postCalls: 0, patchCalls: 0)
  let t9 = makeTransport(b9)
  let keys9 = listEvidenceKeys(t9, "owner/repo")
  expect(keys9.isOk and keys9.get.len == 0, "E9: root-only ledger lists empty (ok(@[]))")
  let miss9 = hasEvidence(t9, "owner/repo", keyA)
  expect(miss9.isOk and miss9.get == false, "E9: valid key on root-only ledger = MISS")
  let append9 = appendEvidence(t9, "owner/repo", recA)
  expect(append9.isOk, "E9: FIRST append on a root-only ledger succeeds: " &
    (if append9.isErr: append9.error else: ""))
  if append9.isOk:
    expect(append9.get.alreadyPresent == false, "E9: first append is not a no-op")
    expect(append9.get.tipSha == b9.tip, "E9: outcome tip == backend tip")
  checkEqStr("E9: exactly one FF CAS ref update", $b9.patchCalls, "1")
  let fetched9 = fetchEvidenceRecord(t9, "owner/repo", keyA)
  expect(fetched9.isOk, "E9: fetchEvidenceRecord round-trips: " &
    (if fetched9.isErr: fetched9.error else: ""))
  if fetched9.isOk:
    expect(fetched9.get.evidenceKey == keyA, "E9: evidenceKey round-trips")
    expect(fetched9.get.payload == payloadA, "E9: payload round-trips byte-exact")
    expect(fetched9.get.payloadSha256 == recA.payloadSha256, "E9: payloadSha256 round-trips")
  let existing9 = existingEvidenceAtTip(t9, "owner/repo", b9.tip, keyA)
  expect(existing9.isOk and existing9.get.payload == payloadA,
    "E9: existingEvidenceAtTip round-trips the stored record")
  echo "Test E9 PASSED: root-only ledger (empty tree) — first append succeeds"

# --- E10: append on an already-poisoned empty-tree root tip lands ---
# The poisoned state run 37417742964 left behind: the ledger ref points at a
# commit whose tree IS the empty tree. The fake models that state directly
# (zero entries ⇒ the commit reader resolves the tip's tree to EmptyTreeSha).
block:
  let poisonedRoot = sha256Hex("evidence-cas-poisoned-root-10")[0 ..< 40]
  let b10 = FakeBackend(tip: poisonedRoot, entries: @[], counter: 0, rejectPatch: false,
    omitBlobContent: false, fetchCalls: 0, postCalls: 0, patchCalls: 0)
  let t10 = makeTransport(b10)
  let appended = appendEvidence(t10, "owner/repo", recA)
  expect(appended.isOk, "E10: append on empty-tree root succeeds: " &
    (if appended.isErr: appended.error else: ""))
  if appended.isOk:
    expect(appended.get.alreadyPresent == false, "E10: lands as a fresh entry")
    expect(appended.get.tipSha == b10.tip, "E10: tip advanced past the poisoned root")
  checkEqStr("E10: exactly one entry after the append", $b10.entries.len, "1")
  let hit = hasEvidence(t10, "owner/repo", keyA)
  expect(hit.isOk and hit.get, "E10: appended key is readable past the poisoned root")
  echo "Test E10 PASSED: poisoned empty-tree root tolerated (no ref repair required)"

# --- E11: the rooting attempt skips the exactly-once re-check; pre-existing
#         tips still re-check (idempotency is load-bearing) ---
block:
  let b11 = FakeBackend(tip: "", entries: @[], counter: 0, rejectPatch: false,
    omitBlobContent: false, fetchCalls: 0, postCalls: 0, patchCalls: 0)
  let t11 = makeTransport(b11)
  let rooted = appendEvidence(t11, "owner/repo", recA)
  expect(rooted.isOk, "E11: fresh-root append succeeds: " &
    (if rooted.isErr: rooted.error else: ""))
  checkEqStr("E11: rooting attempt issues ZERO reads (re-check skipped — the fresh root holds nothing)",
    $b11.fetchCalls, "0")
  let readsBefore = b11.fetchCalls
  let second = appendEvidence(t11, "owner/repo", recB)
  expect(second.isOk and not second.get.alreadyPresent, "E11: distinct key on existing tip lands")
  expect(b11.fetchCalls > readsBefore,
    "E11: append on a pre-existing tip still re-checks (dereference + tree read issued)")
  let rerun = appendEvidence(t11, "owner/repo", recA)
  expect(rerun.isOk and rerun.get.alreadyPresent,
    "E11: re-append on existing tip stays an idempotent no-op")
  checkEqStr("E11: idempotent no-op performs no CAS write", $b11.patchCalls, "2")
  echo "Test E11 PASSED: root-attempt re-check skip + existing-tip re-checks"

# --- E12: fail-closed preserved — a refused NON-empty tree and a malformed
#         commit response stay errors, never an absence ---
block:
  let tip12 = sha256Hex("evidence-cas-unreadable-tree-12")[0 ..< 40]
  var refusedFetch: JsonFetcher = proc(url: string): Result[JsonNode, string] {.raises: [CatchableError, OSError, Exception].} =
    if url.contains("/git/commits/"):
      return ok(%*{"sha": url[(url.rfind("/") + 1) .. ^1],
        "tree": {"sha": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}})
    if url.contains("/git/trees/"):
      return err("GitHub API error for " & url & ": 404 Not Found")
    err("E12 fake fetch: unexpected " & url)
  var unusedPost: JsonPoster = proc(url: string; body: string): Result[JsonNode, string] {.raises: [CatchableError, OSError, Exception].} =
    err("E12: post must not be reached")
  var unusedPatch: JsonPatcher = proc(url: string; body: string): Result[JsonNode, string] {.raises: [CatchableError, OSError, Exception].} =
    err("E12: patch must not be reached")
  var fixedTip: LedgerTipFetcher = proc(repo: string): Result[string, string] {.raises: [CatchableError, OSError, Exception].} =
    ok(tip12)
  let t12 = LedgerTransport(fetch: refusedFetch, post: unusedPost,
    patch: unusedPatch, tip: fixedTip)
  let refused = existingEvidenceAtTip(t12, "owner/repo", tip12, keyA)
  expect(refused.isErr, "E12: unreadable NON-empty tree → fail-closed")
  expect(refused.error.contains("404"),
    "E12: the transport error surfaces (not masked)")
  expect((refused.error.find("no evidence record for key") < 0),
    "E12: a refused tree read is NEVER converted into the absent signal")
  let refusedAppend = appendEvidence(t12, "owner/repo", recA)
  expect(refusedAppend.isErr, "E12: append against an unreadable tree → fail-closed")
  expect(refusedAppend.error.contains("404"),
    "E12: append failure carries the underlying tree-read error")
  # A malformed commit response (missing tree.sha) is also fail-closed.
  var malformedFetch: JsonFetcher = proc(url: string): Result[JsonNode, string] {.raises: [CatchableError, OSError, Exception].} =
    if url.contains("/git/commits/"):
      return ok(%*{"sha": url[(url.rfind("/") + 1) .. ^1]})   # malformed: no tree.sha
    err("E12 malformed fake fetch: unexpected " & url)
  let t12b = LedgerTransport(fetch: malformedFetch, post: unusedPost,
    patch: unusedPatch, tip: fixedTip)
  let malformed = existingEvidenceAtTip(t12b, "owner/repo", tip12, keyA)
  expect(malformed.isErr, "E12: malformed commit response → fail-closed")
  expect(malformed.error.contains("tree.sha"),
    "E12: malformed-commit failure names the missing field")
  echo "Test E12 PASSED: non-empty-tree 404 and malformed commit stay fail-closed"

echo ""
if failures == 0:
  echo "=== All evidence-cas ledger tests PASSED ==="
else:
  echo "=== " & $failures & " evidence-cas ledger test assertion(s) FAILED ==="
  quit(1)
