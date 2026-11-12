import std/[base64, json, os, strutils]
import core/crypto/hash_kernel
import core/results
import verification/attestation_orchestrator
import verification/evidence_ledger
import verification/extraction_provenance
import verification/ledger_side_ref
import verification/rust_replay_adapter
import verification/verification_subject

## Extraction provenance evidence chain tests (feat/rust-subject-v1 Phase 2-D).
##
## Isolation: the ledger talks through the injectable LedgerTransport against
## an in-memory FakeBackend (same approach as tests/verification/
## test_evidence_ledger.nim) — no git commands, no network, and the real
## repository's refs are never touched.
##
## Coverage:
##   J1  job-record roundtrip + canonical digest stability + content address
##   J2  job-record validation (pure): one negative per fail-closed rule;
##       foreign schemaVersion + malformed JSON rejected
##   J3  llbcFileDigest: raw-byte sha256, fail-closed on missing file, and a
##       one-byte LLBC change flips the digest
##   J4  rustToolchainIdentityToken: grammar validation, negatives, injectivity
##   J5  ledger append + re-read: payloadSha256 re-verified on fetch,
##       exactly-once idempotent re-append, distinct record → distinct entry
##   J6  tamper detection: one flipped stored payload byte → fetch fails
##       closed (never partial trust)
##   J7  re-compare gate (pure): match / mismatch / absent-measurement —
##       all three fail-closed semantics
##   J8  evidence wire v2: llbcDigest / rustToolchainIdentity /
##       toolchainIdentity each fold into evidenceDigest (negative contrast);
##       record-level all-or-nothing binding; v1 schemaVersion rejected;
##       pinned toolchain identity carries the charon segment

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
    postCalls: int
    patchCalls: int
    pendingSha: string
    pendingPath: string
    pendingContent: string

proc fakeSha(b: FakeBackend; seed: string): string =
  inc b.counter
  sha256Hex(seed & ":" & $b.counter & ":" & $b.tip)

proc makeBackend(b: FakeBackend): LedgerTransport =
  var fetch: JsonFetcher = proc(url: string): Result[JsonNode, string] {.raises: [CatchableError, OSError, Exception].} =
    if url.contains("/git/commits/"):
      # tip → tree resolution (fetchTipTree): serve a commit pointing at a tree
      let commitSha = url[(url.rfind("/") + 1) .. ^1]
      return ok(%*{"sha": commitSha, "tree": {"sha": b.fakeSha("tree-lookup")}})
    if url.contains("/git/trees/"):
      var entries = newJArray()
      for e in b.entries:
        entries.add(%*{"path": e.path, "type": "blob", "sha": e.sha})
      return ok(%*{"tree": entries})
    if url.contains("/git/blobs/"):
      let sha = url[(url.rfind("/") + 1) .. ^1]
      for e in b.entries:
        if e.sha == sha:
          return ok(%*{"content": encode(e.content), "encoding": "base64"})
      return err("fake fetch: unknown blob " & sha)
    err("fake fetch: unexpected " & url)
  var post: JsonPoster = proc(url: string; body: string): Result[JsonNode, string] {.raises: [CatchableError, OSError, Exception].} =
    inc b.postCalls
    if url.contains("/git/blobs"):
      b.pendingContent = parseJson(body).getOrDefault("content").getStr("")
      b.pendingSha = b.fakeSha("blob:" & b.pendingContent)
      return ok(%*{"sha": b.pendingSha})
    if url.contains("/git/trees"):
      let treeEntry = parseJson(body){"tree"}[0]
      b.pendingPath = treeEntry.getOrDefault("path").getStr("")
      return ok(%*{"sha": b.fakeSha("tree")})
    if url.contains("/git/commits"):
      return ok(%*{"sha": b.fakeSha("commit")})
    if url.contains("/git/refs"):
      return ok(%*{"sha": b.fakeSha("ref")})
    err("fake post: unexpected " & url)
  var patch: JsonPatcher = proc(url: string; body: string): Result[JsonNode, string] {.raises: [CatchableError, OSError, Exception].} =
    inc b.patchCalls
    if b.rejectPatch:
      return err("GitHub API PATCH " & url & " -> 422: is not fast-forward")
    let newSha = parseJson(body).getOrDefault("sha").getStr("")
    b.entries.add(EvidenceEntry(path: b.pendingPath, content: b.pendingContent, sha: b.pendingSha))
    b.tip = newSha
    ok(%*{"object": {"type": "commit", "sha": newSha}})
  var tip: LedgerTipFetcher = proc(repo: string): Result[string, string] {.raises: [CatchableError, OSError, Exception].} =
    ok(b.tip)
  LedgerTransport(fetch: fetch, post: post, patch: patch, tip: tip)

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

const StoredAt = "2026-10-13T00:00:00Z"

proc hexOf(seed: string; n: int): string =
  sha256Hex("fixture:" & seed)[0 ..< n]

proc fixtureFingerprint(): RustToolchainFingerprint =
  ## The MEASURED fingerprint shape (rust_replay_adapter.rustToolchainFingerprint
  ## fields), populated as a real measured run would fold it.
  RustToolchainFingerprint(
    rustcPath: "rustc",
    rustVersion: "rustc 1.91.0-nightly (a1b2c3d 2026-09-17)",
    rustcHash: hexOf("rustc-bin", 64),
    sysroot: "/home/agent/.rustup/toolchains/nightly-2026-09-17-x86_64-unknown-linux-gnu",
    componentsHash: hexOf("components-file", 64),
    components: @["cargo", "clippy", "llvm-tools", "rust-src", "rustc", "rustc-dev", "rustfmt"],
    channel: "nightly-2026-09-17-x86_64-unknown-linux-gnu",
    profile: "default")

proc fixtureRecord(): ExtractionJobRecord =
  ExtractionJobRecord(
    charonPinCommit: PinnedCharonPinCommit,
    charonVersion: PinnedCharonVersion,
    rustcFingerprint: fixtureFingerprint(),
    extractionContract: %*{
      "invocation": "make build-charon-rust && charon --defaults",
      "target": "x86_64-unknown-linux-gnu",
      "rustcArgs": "--edition 2021"
    },
    subjectGitRef: hexOf("gitref", 40),
    subjectTreeMerkle: hexOf("tree", 40),
    moduleSha256: hexOf("module", 64),
    llbcDigest: hexOf("llbc", 64))

proc fixtureEvidence(llbcDigest, rustToken: string): AttestationInputs =
  ## A v2 evidence record. The six digest bindings are well-formed fixture
  ## values — only the WIRE semantics are under test here (no chain run).
  AttestationInputs(
    schemaVersion: EvidenceScheme,
    subjectId: hexOf("subject", 64),
    prNumber: 0,
    prHeadSha: hexOf("head", 40),
    leanSource: "theorem p : True := trivial\n#print axioms p",
    smtlib2: "(declare-const x Int)\n(assert (> x 0))\n(check-sat)",
    funcSource: "proc inc3(x: int): int = x + 3\n",
    funcPath: "tmp/ax_prov_fixture.nim",
    funcName: "inc3",
    envDigest: hexOf("env", 64),
    policyDigest: hexOf("policy", 64),
    scopeDigest: hexOf("scope", 64),
    toolchainIdentity: pinnedToolchainIdentity(),
    llbcDigest: llbcDigest,
    rustToolchainIdentity: rustToken)

proc evidenceRecordJson(inputs: AttestationInputs): JsonNode =
  ## The full v2 evidence record as an embedding would serialize it (the
  ## witness evidenceRecordNode shape + the v2 binding fields).
  %*{
    "schemaVersion": inputs.schemaVersion,
    "subjectId": inputs.subjectId,
    "prNumber": inputs.prNumber,
    "prHeadSha": inputs.prHeadSha,
    "leanSource": inputs.leanSource,
    "smtlib2": inputs.smtlib2,
    "funcSource": inputs.funcSource,
    "funcPath": inputs.funcPath,
    "funcName": inputs.funcName,
    "policyDigest": inputs.policyDigest,
    "scopeDigest": inputs.scopeDigest,
    "envDigest": inputs.envDigest,
    "toolchainIdentity": inputs.toolchainIdentity,
    "llbcDigest": inputs.llbcDigest,
    "rustToolchainIdentity": inputs.rustToolchainIdentity
  }

# ---------------------------------------------------------------------------
# J1 — job-record roundtrip + canonical digest stability
# ---------------------------------------------------------------------------
echo "=== J1: job-record roundtrip + canonical digest stability ==="
block:
  let rec = fixtureRecord()
  let wire = jobRecordToCanonicalJson(rec)
  let parsed = extractionJobRecordFromPayload(wire)
  expect(parsed.isOk, "J1 canonical wire parses back: " & (if parsed.isErr: parsed.error else: ""))
  if parsed.isOk:
    let back = parsed.get
    expect(back == rec, "J1 roundtrip preserves every field")
  checkEqStr("J1 canonical serialization is stable (identical bytes)",
    jobRecordToCanonicalJson(rec), wire)
  let key = extractionJobKey(rec)
  expect(key.isOk, "J1 valid record yields a key")
  checkEqStr("J1 key is the content address of the canonical bytes",
    key.get, sha256Hex(wire))
  expect(isHexOfLen(key.get, 64), "J1 key is 64-hex")
  let node = parseJson(wire)
  checkEqStr("J1 wire carries the extraction job schemaVersion",
    node.getOrDefault("schemaVersion").getStr(""), ExtractionJobRecordSchema)
  checkEqStr("J1 wire carries the pinned charon commit",
    node.getOrDefault("charonPinCommit").getStr(""), PinnedCharonPinCommit)
  checkEqStr("J1 wire carries the LLBC digest",
    node.getOrDefault("llbcDigest").getStr(""), rec.llbcDigest)

# ---------------------------------------------------------------------------
# J2 — job-record validation (pure, fail-closed)
# ---------------------------------------------------------------------------
echo "=== J2: job-record validation (one negative per rule) ==="
proc mutated(mutator: proc(r: var ExtractionJobRecord) {.raises: [].}): ExtractionJobRecord =
  var rec = fixtureRecord()
  mutator(rec)
  rec

template expectRejected(name: string; rec: ExtractionJobRecord) =
  block:
    let problem = validateExtractionJobRecord(rec)
    expect(problem.len > 0, name & " (expected rejection, got ok)")

expectRejected("J2 short charonPinCommit rejected", mutated do(r: var ExtractionJobRecord):
  r.charonPinCommit = "abc123")
expectRejected("J2 empty charonVersion rejected", mutated do(r: var ExtractionJobRecord):
  r.charonVersion = "")
expectRejected("J2 empty rustVersion rejected", mutated do(r: var ExtractionJobRecord):
  r.rustcFingerprint.rustVersion = "")
expectRejected("J2 non-hex rustcHash rejected", mutated do(r: var ExtractionJobRecord):
  r.rustcFingerprint.rustcHash = "zz" & hexOf("x", 62))
expectRejected("J2 non-hex componentsHash rejected", mutated do(r: var ExtractionJobRecord):
  r.rustcFingerprint.componentsHash = "short")
expectRejected("J2 empty component set rejected", mutated do(r: var ExtractionJobRecord):
  r.rustcFingerprint.components = @[])
expectRejected("J2 empty channel rejected", mutated do(r: var ExtractionJobRecord):
  r.rustcFingerprint.channel = "")
expectRejected("J2 empty profile rejected", mutated do(r: var ExtractionJobRecord):
  r.rustcFingerprint.profile = "")
expectRejected("J2 non-object extractionContract rejected", mutated do(r: var ExtractionJobRecord):
  r.extractionContract = %"charon --defaults")
expectRejected("J2 non-string extractionContract value rejected", mutated do(r: var ExtractionJobRecord):
  r.extractionContract = %*{"invocation": 1})
expectRejected("J2 non-hex subjectGitRef rejected", mutated do(r: var ExtractionJobRecord):
  r.subjectGitRef = "HEAD")
expectRejected("J2 non-hex subjectTreeMerkle rejected", mutated do(r: var ExtractionJobRecord):
  r.subjectTreeMerkle = hexOf("tree", 39))
expectRejected("J2 non-hex moduleSha256 rejected", mutated do(r: var ExtractionJobRecord):
  r.moduleSha256 = hexOf("module", 63))
expectRejected("J2 non-hex llbcDigest rejected", mutated do(r: var ExtractionJobRecord):
  r.llbcDigest = "nothex")
block:
  # empty extractionContract object IS valid (recording is optional provenance)
  var rec = fixtureRecord()
  rec.extractionContract = newJObject()
  expect(validateExtractionJobRecord(rec).len == 0, "J2 empty extractionContract accepted")
block:
  let foreign = jobRecordFromJson(parseJson(
    jobRecordToCanonicalJson(fixtureRecord()).replace(ExtractionJobRecordSchema, "axiom.extraction.job.v0")))
  expect(foreign.isErr and foreign.error.contains("schemaVersion"),
    "J2 foreign schemaVersion rejected (fail-closed)")
block:
  let malformed = extractionJobRecordFromPayload("{not json")
  expect(malformed.isErr, "J2 malformed JSON rejected (fail-closed)")

# ---------------------------------------------------------------------------
# J3 — llbcFileDigest (raw-byte sha256, fail-closed)
# ---------------------------------------------------------------------------
echo "=== J3: llbcFileDigest ==="
block:
  let dir = getTempDir() / ("ax_prov_" & $getCurrentProcessId())
  createDir(dir)
  let llbcPath = dir / "subject.llbc"
  let llbcBytes = "{\"charon_version\":\"0.1.281\",\"translated\":{}}"
  writeFile(llbcPath, llbcBytes)
  let digest = llbcFileDigest(llbcPath)
  expect(digest.isOk, "J3 readable LLBC yields a digest")
  checkEqStr("J3 digest is sha256 over the raw file bytes",
    digest.get, sha256Hex(llbcBytes))
  # one-byte change → different digest (the binding the certificate relies on)
  writeFile(llbcPath, llbcBytes & " ")
  let digest2 = llbcFileDigest(llbcPath)
  expect(digest2.isOk and digest2.get != digest.get,
    "J3 one-byte LLBC change flips the digest")
  let missing = llbcFileDigest(dir / "absent.llbc")
  expect(missing.isErr, "J3 missing LLBC fails closed")
  expect(missing.error.contains("not found"), "J3 missing-file reason names the file")
  try:
    removeDir(dir)
  except CatchableError:
    discard  # axiom:best-effort(test temp dir cleanup — a leftover tmp dir is harmless to the verdict)

# ---------------------------------------------------------------------------
# J4 — rustToolchainIdentityToken (grammar + injectivity)
# ---------------------------------------------------------------------------
echo "=== J4: rustToolchainIdentityToken ==="
block:
  let fp = fixtureFingerprint()
  let token = rustToolchainIdentityToken(fp)
  checkEqStr("J4 token validates (canonical grammar)",
    validateRustToolchainIdentityToken(token), "")
  # every identity field travels in the token
  expect(token.contains("rustc-version=" & fp.rustVersion), "J4 token carries rustVersion")
  expect(token.contains("rustc-sha256=" & fp.rustcHash), "J4 token carries rustcHash")
  expect(token.contains("channel=" & fp.channel), "J4 token carries channel")
  expect(token.contains("components=" & fp.components.join(",")), "J4 token carries component set")
  expect(not token.contains("sysroot=") and not token.contains("rustcPath"),
    "J4 token excludes host-local paths (repo recorded-identity definition)")
  template rejectToken(name: string; bad: string) =
    expect(validateRustToolchainIdentityToken(bad).len > 0, name)
  rejectToken("J4 too-few segments rejected", "rustc-version=v|rustc-sha256=" & fp.rustcHash)
  rejectToken("J4 wrong segment order rejected",
    rustToolchainIdentityToken(fp).replace("channel=", "channel-x="))
  rejectToken("J4 empty field value rejected",
    rustToolchainIdentityToken(fp).replace("profile=default", "profile="))
  rejectToken("J4 non-hex rustc-sha256 rejected",
    rustToolchainIdentityToken(fp).replace(fp.rustcHash, "nothex"))
  # injectivity: any identity change → different token
  var fp2 = fp
  fp2.channel = "stable-x86_64-unknown-linux-gnu"
  expect(rustToolchainIdentityToken(fp2) != token, "J4 channel change → different token")
  var fp3 = fp
  fp3.components.add("miri")
  expect(rustToolchainIdentityToken(fp3) != token, "J4 component-set change → different token")

# ---------------------------------------------------------------------------
# J5 — ledger append + re-read (payloadSha256 re-verified, exactly-once)
# ---------------------------------------------------------------------------
echo "=== J5: ledger landing (append + verified re-read) ==="
block:
  let backend = FakeBackend(tip: "", entries: @[], counter: 0)
  let transport = makeBackend(backend)
  let rec = fixtureRecord()
  let landed = appendExtractionJobRecord(transport, "owner/repo", rec, StoredAt)
  expect(landed.isOk, "J5 first append lands: " & (if landed.isErr: landed.error else: ""))
  if landed.isOk:
    expect(not landed.get.alreadyPresent, "J5 first append is not a no-op")
    expect(landed.get.tipSha.len > 0, "J5 append returns the new tip")
  let key = extractionJobKey(rec)
  expect(key.isOk, "J5 record yields its content-address key")
  if key.isOk:
    let readBack = fetchExtractionJobRecord(transport, "owner/repo", key.get)
    expect(readBack.isOk, "J5 verified re-read succeeds: " &
      (if readBack.isErr: readBack.error else: ""))
    if readBack.isOk:
      expect(readBack.get == rec, "J5 re-read roundtrips every field")
      # payloadSha256 re-verification: the ledger payload bytes hash to the
      # recorded payloadSha256 AND to the content address (key == payload hash)
      let ledgerRec = fetchEvidenceRecord(transport, "owner/repo", key.get)
      expect(ledgerRec.isOk, "J5 raw ledger record readable")
      if ledgerRec.isOk:
        checkEqStr("J5 payloadSha256 = sha256(payload bytes) re-derived on read",
          ledgerRec.get.payloadSha256, sha256Hex(ledgerRec.get.payload))
        checkEqStr("J5 ledger key binds the payload bytes (content address)",
          ledgerRec.get.evidenceKey, sha256Hex(ledgerRec.get.payload))
  # exactly-once: same record again → idempotent no-op, tip unchanged
  let tipBefore = backend.tip
  let again = appendExtractionJobRecord(transport, "owner/repo", rec, StoredAt)
  expect(again.isOk and again.get.alreadyPresent, "J5 identical re-append is an idempotent no-op")
  expect(backend.tip == tipBefore, "J5 idempotent no-op leaves the tip unchanged")
  expect(backend.entries.len == 1, "J5 no duplicate entry landed")
  # distinct record (different LLBC) → distinct key → new entry
  var rec2 = fixtureRecord()
  rec2.llbcDigest = hexOf("llbc-2", 64)
  let landed2 = appendExtractionJobRecord(transport, "owner/repo", rec2, StoredAt)
  expect(landed2.isOk and not landed2.get.alreadyPresent, "J5 distinct record lands as a new entry")
  expect(extractionJobKey(rec2).get != key.get, "J5 distinct LLBC → distinct content address")
  expect(backend.entries.len == 2, "J5 ledger holds both records")
  # malformed record never touches the transport
  var bad = fixtureRecord()
  bad.charonPinCommit = "nothex"
  let posts = backend.postCalls
  let refused = appendExtractionJobRecord(transport, "owner/repo", bad, StoredAt)
  expect(refused.isErr, "J6 malformed record refused")
  expect(backend.postCalls == posts, "J6 refused record wrote nothing (no transport calls)")

# ---------------------------------------------------------------------------
# J6 — tamper detection on the stored job record
# ---------------------------------------------------------------------------
echo "=== J6: tamper on stored evidence → detection ==="
block:
  let backend = FakeBackend(tip: "", entries: @[], counter: 0)
  let transport = makeBackend(backend)
  let rec = fixtureRecord()
  let landed = appendExtractionJobRecord(transport, "owner/repo", rec, StoredAt)
  expect(landed.isOk, "J6 setup append lands")
  let key = extractionJobKey(rec).get
  # flip ONE byte of the stored payload (inside the recorded llbcDigest hex —
  # the JSON stays parseable) → the ledger's re-hash must fail closed
  var tampered = false
  for i in 0 ..< backend.entries.len:
    if backend.entries[i].path == key & ".json":
      let marker = rec.llbcDigest
      let at = backend.entries[i].content.find(marker)
      expect(at >= 0, "J6 setup found the llbcDigest bytes in the stored payload")
      if at >= 0:
        let flippedChar = if backend.entries[i].content[at] == 'a': 'b' else: 'a'
        backend.entries[i].content[at] = flippedChar
        tampered = true
  expect(tampered, "J6 setup found the stored entry to tamper with")
  let readBack = fetchExtractionJobRecord(transport, "owner/repo", key)
  expect(readBack.isErr, "J6 tampered payload fails closed on re-read")
  expect(readBack.error.contains("fail-closed"), "J6 tamper reason is fail-closed")
  # a key that was never landed → fail closed (never a guessed record)
  let absent = fetchExtractionJobRecord(transport, "owner/repo", hexOf("absent", 64))
  expect(absent.isErr, "J6 absent key fails closed")

# ---------------------------------------------------------------------------
# J7 — attestation-time re-compare gate (pure; three fail-closed semantics)
# ---------------------------------------------------------------------------
echo "=== J7: re-compare gate — match / mismatch / absent-measurement ==="
proc measuredEnv(): MeasuredExtractionEnvironment =
  MeasuredExtractionEnvironment(
    fingerprint: fixtureFingerprint(),
    charonPinCommit: PinnedCharonPinCommit,
    charonVersion: PinnedCharonVersion)

block:
  let verdict = verifyExtractionEnvironment(fixtureRecord(), measuredEnv())
  expect(verdict.isOk, "J7 identical record + measured environment → verified")
block:
  # mismatch: recorded charon pin commit differs from the measured one
  var measured = measuredEnv()
  measured.charonPinCommit = hexOf("other-pin", 40)
  let verdict = verifyExtractionEnvironment(fixtureRecord(), measured)
  expect(verdict.isErr and verdict.error.contains("charon pin commit"),
    "J7 charon pin mismatch fails closed (violation)")
block:
  var measured = measuredEnv()
  measured.charonVersion = "0.1.999"
  let verdict = verifyExtractionEnvironment(fixtureRecord(), measured)
  expect(verdict.isErr and verdict.error.contains("charon version"),
    "J7 charon version mismatch fails closed (violation)")
block:
  var measured = measuredEnv()
  measured.fingerprint.rustcHash = hexOf("other-rustc", 64)
  let verdict = verifyExtractionEnvironment(fixtureRecord(), measured)
  expect(verdict.isErr and verdict.error.contains("rustc fingerprint"),
    "J7 rustc binary mismatch fails closed (violation)")
block:
  var measured = measuredEnv()
  measured.fingerprint.components = @["cargo", "rustc"]
  let verdict = verifyExtractionEnvironment(fixtureRecord(), measured)
  expect(verdict.isErr and verdict.error.contains("component set"),
    "J7 component-set mismatch fails closed (violation)")
block:
  # unverifiability: the corresponding measurement is ABSENT — never a match
  var measured = measuredEnv()
  measured.charonPinCommit = ""
  let verdict = verifyExtractionEnvironment(fixtureRecord(), measured)
  expect(verdict.isErr and verdict.error.contains("unverifiable"),
    "J7 absent charon pin measurement fails closed (unverifiable)")
block:
  var measured = measuredEnv()
  measured.fingerprint.rustVersion = ""
  let verdict = verifyExtractionEnvironment(fixtureRecord(), measured)
  expect(verdict.isErr and verdict.error.contains("absent"),
    "J7 absent rustVersion measurement fails closed (unverifiable)")
block:
  var measured = measuredEnv()
  measured.fingerprint.componentsHash = ""
  let verdict = verifyExtractionEnvironment(fixtureRecord(), measured)
  expect(verdict.isErr and verdict.error.contains("unverifiable"),
    "J7 absent componentsHash measurement fails closed (unverifiable)")
block:
  var measured = measuredEnv()
  measured.fingerprint.components = @[]
  let verdict = verifyExtractionEnvironment(fixtureRecord(), measured)
  expect(verdict.isErr and verdict.error.contains("absent"),
    "J7 absent component set fails closed (unverifiable)")

# ---------------------------------------------------------------------------
# J8 — evidence wire v2 (identity folding + record-level binding contract)
# ---------------------------------------------------------------------------
echo "=== J8: evidenceBundleWire v2 — extraction binding folds into evidenceDigest ==="
block:
  let token = rustToolchainIdentityToken(fixtureFingerprint())
  let nimLane = fixtureEvidence("", "")
  let rustLane = fixtureEvidence(hexOf("llbc", 64), token)
  # v1-shaped 13-field records remain valid v2 records (no Rust binding)
  expect(validateAttestationInputs(nimLane).len == 0,
    "J8 no-LLBC lane record validates (both binding fields empty)")
  expect(validateAttestationInputs(rustLane).len == 0,
    "J8 Rust-lane record validates (binding pair well-formed)")
  # negative contrast: each folded member change moves evidenceDigest
  let base = evidenceBundleDigest(rustLane)
  var flipLlbc = rustLane
  flipLlbc.llbcDigest = hexOf("llbc-2", 64)
  expect(evidenceBundleDigest(flipLlbc) != base,
    "J8 llbcDigest change → evidenceDigest change (LLBC bytes are identity)")
  var flipToken = rustLane
  flipToken.rustToolchainIdentity = token.replace("channel=nightly-2026-09-17-x86_64-unknown-linux-gnu", "channel=stable")
  expect(evidenceBundleDigest(flipToken) != base,
    "J8 rustToolchainIdentity change → evidenceDigest change")
  var flipToolchain = rustLane
  flipToolchain.toolchainIdentity = flipToolchain.toolchainIdentity & "-x"
  expect(evidenceBundleDigest(flipToolchain) != base,
    "J8 toolchainIdentity change → evidenceDigest change (v2 folds it into the wire)")
  # wire text carries the LLBC digest
  expect(evidenceBundleWire(rustLane).contains(hexOf("llbc", 64)),
    "J8 wire text binds the llbcDigest bytes")
  checkEqStr("J8 digest = sha256 over the canonical wire",
    evidenceBundleDigest(rustLane), sha256Hex(evidenceBundleWire(rustLane)))
  # record-level all-or-nothing binding
  var halfBound = rustLane
  halfBound.rustToolchainIdentity = ""
  expect(validateAttestationInputs(halfBound).len > 0,
    "J8 half-bound record (llbcDigest only) rejected")
  var halfBound2 = rustLane
  halfBound2.llbcDigest = ""
  expect(validateAttestationInputs(halfBound2).len > 0,
    "J8 half-bound record (token only) rejected")
  var badDigest = rustLane
  badDigest.llbcDigest = "nothex"
  expect(validateAttestationInputs(badDigest).len > 0,
    "J8 non-hex llbcDigest rejected")
  var badToken = rustLane
  badToken.rustToolchainIdentity = "rustc-version=v1.0"
  expect(validateAttestationInputs(badToken).len > 0,
    "J8 malformed identity token rejected")
  # parser: v2 15-field record roundtrips with the binding intact
  let decoded = inputsFromJson(evidenceRecordJson(rustLane))
  expect(decoded.isOk, "J8 v2 record with binding parses: " &
    (if decoded.isErr: decoded.error else: ""))
  if decoded.isOk:
    checkEqStr("J8 parsed llbcDigest preserved", decoded.get.llbcDigest, rustLane.llbcDigest)
    checkEqStr("J8 parsed rustToolchainIdentity preserved",
      decoded.get.rustToolchainIdentity, token)
  # parser: 13-field v2 embedding (witness bundle form) roundtrips with
  # honest empty binding
  let legacyShape = evidenceRecordJson(nimLane)
  legacyShape.delete("llbcDigest")
  legacyShape.delete("rustToolchainIdentity")
  let decodedLegacy = inputsFromJson(legacyShape)
  expect(decodedLegacy.isOk, "J8 13-field v2 record parses (optional presence)")
  if decodedLegacy.isOk:
    checkEqStr("J8 absent binding folds to empty", decodedLegacy.get.llbcDigest, "")
  # parser: present-but-mistyped binding rejected (fresh node — no aliasing)
  let mistyped = evidenceRecordJson(nimLane)
  mistyped["llbcDigest"] = %42
  expect(inputsFromJson(mistyped).isErr, "J8 non-string llbcDigest rejected")
  # parser: the v1 generation is refused wholesale (coherent cutover)
  let v1 = evidenceRecordJson(nimLane)
  v1["schemaVersion"] = %"axiom.attestation.evidence.v1"
  let v1Parsed = inputsFromJson(v1)
  expect(v1Parsed.isErr and v1Parsed.error.contains("schemaVersion"),
    "J8 v1 schemaVersion rejected (coherent generation cutover, fail-closed)")
block:
  # stage-e input contract: the pinned identity carries the charon segment,
  # and a charon flip is a DIFFERENT pinned identity (the full-chain
  # atToolchainMismatch enforcement is exercised in
  # tests/verification/test_attestation.nim P6/P7)
  let pinned = pinnedToolchainIdentity()
  let segment = charonIdentitySegment()
  expect(pinned.len >= segment.len and
    pinned[pinned.len - segment.len .. ^1] == segment,
    "J8 pinned identity ends with the charon segment")
  expect(pinned.contains("charon-pin-" & PinnedCharonPinCommit),
    "J8 pinned identity carries the Aeneas-side charon pin commit")
  expect(pinned.contains("charon-" & PinnedCharonVersion),
    "J8 pinned identity carries the pinned charon version")
  let flipped = pinned.replace("charon-" & PinnedCharonVersion, "charon-9.9.999")
  expect(flipped != pinned, "J8 charon flip → different pinned identity")

# ---------------------------------------------------------------------------
echo ""
if failures == 0:
  echo "✅ test_extraction_provenance PASSED"
else:
  echo "❌ test_extraction_provenance FAILED — " & $failures & " failure(s)"
  quit(1)
