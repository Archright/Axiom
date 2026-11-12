## Rust lane extraction-provenance issuance linkage (feat/rust-subject-v1,
## Phase 2-D integration — 2.5-I).
##
## Drives the REAL Charon probe through `rustSubjectIssuance` with the
## extraction provenance stage ARMED (subjectRoot + llbcPath + an EvidenceCas
## `LedgerTransport`), over the same environment gates as
## rust_subject_three_cases_test.nim (rustc present; explicit skip, not
## failure). The probe crate is a committed in-repo fixture
## (tests/fixtures/rust/axiom_rust_probe/ — no fixture-absent skip). The
## ledger talks through the injectable
## LedgerTransport against an in-memory FakeBackend (same approach as
## tests/unit/test_extraction_provenance.nim and tests/verification/
## test_evidence_ledger.nim) — no network, no real refs touched.
##
## Coverage:
##   P1  normal case: the job record LANDS in the ledger (content address ==
##       sha256(canonical record bytes)); the record binds the consumed LLBC
##       raw bytes, the measured rustc fingerprint, the subject exact-commit
##       git identity of the materialized repo, and the RECORDED extraction
##       contract (translated.options/target_information); issuance mints.
##   P2  negative contrast: changing the LLBC bytes changes both the job
##       record's content address (new ledger entry) and the certificate
##       evidenceId — the LLBC bytes are certificate identity.
##   P3  absent job record (the append provably never landed a retrievable
##       entry) → issuance FAILS CLOSED at the provenance stage, no cert.
##   P4  tampered job record (one flipped stored payload byte) → the ledger's
##       payloadSha256 re-verification refuses the re-append at issuance →
##       fail-closed, no cert.
##   P5  recorded-vs-pinned mismatch (LLBC header charon_version tampered to
##       9.9.999 → the record records it) → verifyExtractionEnvironment
##       refuses (recorded != pinned) → fail-closed, no cert.
##   P6  pure units: recordedExtractionContract (verbatim canonical-JSON
##       members, empty contract when absent) and the armed/unarmed
##       execution-contract digest split (unarmed stays the landed formula).
##   P7  declared-lane counterexample confirmation (z3-gated): the mutant's
##       spec is declined BY THE KERNEL and the declined obligation is
##       CONFIRMED — z3's refuting model is replayed on the real rustc
##       harness — so the record carries counterexampleConfirmed == true
##       with a non-empty confirmedPayload, blockStage "kernel" and the
##       "counterexample CONFIRMED" blockReason; the positive control stays
##       issued with NO confirmation (nothing to confirm).

import std/[base64, json, os, osproc, sequtils, strutils, options, unittest]

import core/crypto/hash_kernel
import core/results
import core/trusted/axiom_ir
import core/trusted/axiom_ir_helpers
import verification/evidence_ledger
import verification/extraction_provenance
import verification/ledger_side_ref
import verification/rust_replay_adapter       ## RustToolchainFingerprint
import verification/rust_rust_pipeline
import verification/verification_subject      ## isHexOfLen

proc repoRoot(): string =
  ## tests/gateway/<file> -> project root (location-based, so the compiled
  ## binary resolves the fixture from any CWD — the pattern of
  ## hermetic_policy_feature_test.nim)
  absolutePath("../..", currentSourcePath().parentDir)

let
  RepoRoot = repoRoot()
  FixtureDir = RepoRoot / "tests" / "fixtures" / "rust" / "axiom_rust_probe"
  ProbePath = FixtureDir / "axiom_rust_probe.llbc"
  ProbeSourcePath = FixtureDir / "src" / "lib.rs"

let rustcPresent = findExe("rustc").len > 0
let z3Present = findExe("z3").len > 0 or
    fileExists(getHomeDir() / ".local" / "bin" / "z3")

if not rustcPresent:
  echo "SKIP: rustc not on PATH — the extraction fingerprint is unmeasurable " &
    "and the provenance lane fails closed by design (explicit skip, not a failure)"
if not z3Present:
  echo "SKIP: z3 not found — the counterexample-confirmation suite (P7) " &
    "skips (explicit skip, not a failure)"

proc specAddAdd(): IRExpr =
  ## The spec under test: f(a,b) = a+b (same shape as the three-cases suite).
  let bv64 = irTypeBitVec64()
  irEq(irVar("result", bv64), irAdd(irVar("a", bv64), irVar("b", bv64)))

proc materializeProbeSubject(dirName: string): string =
  ## The provenance stage binds the subject through the adapter's read-only
  ## git queries and FAILS CLOSED on an unbindable root, and the fixture
  ## tree is part of the Axiom repo (it must never be written, nor bound to
  ## Axiom's own git identity) — so the fixture's REAL content is copied
  ## UNCHANGED into a throwaway git repo (the same honest handling the
  ## three-cases suite established). The copy mirrors the crate layout —
  ## Cargo.toml, Cargo.lock and src/lib.rs — because the Phase 1-A input
  ## contract (which arms the provenance stage) requires the Cargo crate
  ## identity and the LLBC↔source file-set equivalence (src/lib.rs).
  let root = getTempDir() / dirName
  removeDir(root)
  createDir(root / "src")
  copyFile(ProbeSourcePath, root / "src" / "lib.rs")
  copyFile(FixtureDir / "Cargo.toml", root / "Cargo.toml")
  copyFile(FixtureDir / "Cargo.lock", root / "Cargo.lock")
  discard execCmdEx("git -C \"" & root & "\" init -q")
  discard execCmdEx("git -C \"" & root & "\" add -A")
  discard execCmdEx("git -C \"" & root &
    "\" -c user.name=ax -c user.email=ax@test commit -q -m init")
  root

# ---------------------------------------------------------------------------
# Fake ledger backend (in-memory git object store; proven in
# tests/unit/test_extraction_provenance.nim) + the absent-landing switch.
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
    dropAppends: bool   ## true = every append "succeeds" on the wire but no
                        ## entry is ever stored (the record is absent)
    pendingSha: string
    pendingPath: string
    pendingContent: string

proc fakeSha(b: FakeBackend; seed: string): string =
  inc b.counter
  sha256Hex(seed & ":" & $b.counter & ":" & $b.tip)

proc makeBackend(b: FakeBackend): LedgerTransport =
  var fetch: JsonFetcher = proc(url: string): Result[JsonNode, string] {.raises: [CatchableError, OSError, Exception].} =
    if url.contains("/git/commits/"):
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
    let newSha = parseJson(body).getOrDefault("sha").getStr("")
    if not b.dropAppends:
      b.entries.add(EvidenceEntry(path: b.pendingPath, content: b.pendingContent,
                                  sha: b.pendingSha))
    b.tip = newSha
    ok(%*{"object": {"type": "commit", "sha": newSha}})
  var tip: LedgerTipFetcher = proc(repo: string): Result[string, string] {.raises: [CatchableError, OSError, Exception].} =
    ok(b.tip)
  LedgerTransport(fetch: fetch, post: post, patch: patch, tip: tip)

proc storedEntry(b: FakeBackend; path: string): string =
  for e in b.entries:
    if e.path == path:
      return e.content
  ""

proc tamperStoredLlbcByte(b: FakeBackend; key, llbcDigest: string): bool =
  ## Flip ONE hex char of the stored record's llbcDigest — the JSON stays
  ## parseable but the payload bytes no longer hash to payloadSha256.
  for i in 0 ..< b.entries.len:
    if b.entries[i].path == key & ".json":
      let at = b.entries[i].content.find(llbcDigest)
      if at >= 0:
        let flipped = if b.entries[i].content[at] == 'a': 'b' else: 'a'
        b.entries[i].content[at] = flipped
        return true
  false

proc issuanceCertDir(name: string): string =
  result = getTempDir() / ("axiom_rust_prov_iss_" & name & "_" &
    $getCurrentProcessId())
  removeDir(result)
  createDir(result)

proc countCertFiles(dir: string): int =
  for p in walkPattern(dir / "*.json"):
    inc result

proc gitHead(repo: string): string =
  let (outp, code) = execCmdEx("git -C \"" & repo & "\" rev-parse HEAD")
  if code == 0: outp.strip() else: ""

if rustcPresent:
  let probeText = readFile(ProbePath)

  suite "rust_subject provenance issuance — record landing + evidence binding (real probe)":

    test "P1: normal case — job record lands; evidence binds the LLBC bytes; cert mints":
      let repo = materializeProbeSubject("axiom_rust_prov_pos")
      let certDir = issuanceCertDir("pos")
      let backend = FakeBackend(tip: "", entries: @[], counter: 0)
      let rec = rustSubjectIssuance(
        probeText, "add_u8", specAddAdd(), certDir,
        repo / "src" / "lib.rs", readFile(repo / "src" / "lib.rs"),
        subjectRoot = repo,
        llbcPath = ProbePath,
        extractionLedger = some(makeBackend(backend)),
        extractionLedgerRepo = "owner/repo")
      check rec.attempted
      check rec.issued
      check rec.blockStage == ""
      check isHexOfLen(rec.extractionJobKey, 64)
      check fileExists(rec.certPath)
      # the record exists in the ledger under its content address and
      # re-reads through the ledger's full identity chain
      let readBack = fetchExtractionJobRecord(makeBackend(backend),
                                              "owner/repo",
                                              rec.extractionJobKey)
      check readBack.isOk
      # the landed envelope carries the extraction job schemaVersion
      check storedEntry(backend, rec.extractionJobKey & ".json").contains(
        ExtractionJobRecordSchema)
      if readBack.isOk:
        let record = readBack.get
        # the record binds the CONSUMED LLBC raw bytes
        check record.llbcDigest == sha256Hex(probeText)
        # the record binds the subject exact-commit identity + module bytes
        check record.subjectGitRef == gitHead(repo)
        check record.moduleSha256 == sha256Hex(readFile(repo / "src" / "lib.rs"))
        check record.charonPinCommit == PinnedCharonPinCommit
        check record.charonVersion == PinnedCharonVersion
        # the RECORDED extraction contract carries the embedded LLBC members
        check record.extractionContract{"translated.options"}.kind == JString
        check record.extractionContract{"translated.target_information"}.kind == JString
        # the envelope re-hash holds: payloadSha256 == sha256(payload bytes)
        let ledgerRec = fetchEvidenceRecord(makeBackend(backend), "owner/repo",
                                            rec.extractionJobKey)
        check ledgerRec.isOk
        if ledgerRec.isOk:
          check ledgerRec.get.payloadSha256 == sha256Hex(ledgerRec.get.payload)
      let cert = parseFile(rec.certPath)
      check cert["evidenceId"].getStr().len == 64
      removeDir(certDir)

    test "P2: changed LLBC bytes → new job-record key AND new certificate evidenceId":
      let repo = materializeProbeSubject("axiom_rust_prov_contrast")
      # run 1: the probe as-is
      let certDir1 = issuanceCertDir("c1")
      let b1 = FakeBackend(tip: "", entries: @[], counter: 0)
      let rec1 = rustSubjectIssuance(
        probeText, "add_u8", specAddAdd(), certDir1,
        repo / "src" / "lib.rs", readFile(repo / "src" / "lib.rs"),
        subjectRoot = repo, llbcPath = ProbePath,
        extractionLedger = some(makeBackend(b1)),
        extractionLedgerRepo = "owner/repo")
      check rec1.issued
      let evidenceId1 = parseFile(rec1.certPath)["evidenceId"].getStr()
      # run 2: ONE extra byte in the LLBC file AND the consumed text (same
      # canonical JSON — the canonical/irHash is unchanged; the raw bytes and
      # therefore the provenance binding are not)
      let tamperedText = probeText & " "
      let tamperedPath = getTempDir() / ("axiom_rust_prov_tampered_" &
        $getCurrentProcessId() & ".llbc")
      writeFile(tamperedPath, tamperedText)
      let certDir2 = issuanceCertDir("c2")
      let b2 = FakeBackend(tip: "", entries: @[], counter: 0)
      let rec2 = rustSubjectIssuance(
        tamperedText, "add_u8", specAddAdd(), certDir2,
        repo / "src" / "lib.rs", readFile(repo / "src" / "lib.rs"),
        subjectRoot = repo, llbcPath = tamperedPath,
        extractionLedger = some(makeBackend(b2)),
        extractionLedgerRepo = "owner/repo")
      check rec2.issued
      let evidenceId2 = parseFile(rec2.certPath)["evidenceId"].getStr()
      check rec2.extractionJobKey != rec1.extractionJobKey
      check evidenceId2 != evidenceId1
      # each ledger holds exactly its own run's record
      check storedEntry(b1, rec1.extractionJobKey & ".json").contains(sha256Hex(probeText))
      check storedEntry(b2, rec2.extractionJobKey & ".json").contains(sha256Hex(tamperedText))
      removeDir(certDir1)
      removeDir(certDir2)
      try:
        removeFile(tamperedPath)
      except CatchableError:
        discard  # axiom:best-effort(test temp cleanup — a residual tampered fixture file must not mask the assertion verdict)

  suite "rust_subject provenance issuance — fail-closed semantics (real probe)":

    test "P3: absent job record → issuance fails closed at provenance, NO cert":
      let repo = materializeProbeSubject("axiom_rust_prov_absent")
      let certDir = issuanceCertDir("absent")
      let transport = makeBackend(FakeBackend(tip: "", entries: @[], counter: 0, dropAppends: true))
      let rec = rustSubjectIssuance(
        probeText, "add_u8", specAddAdd(), certDir,
        repo / "src" / "lib.rs", readFile(repo / "src" / "lib.rs"),
        subjectRoot = repo, llbcPath = ProbePath,
        extractionLedger = some(transport), extractionLedgerRepo = "owner/repo")
      check rec.attempted
      check not rec.issued
      check rec.blockStage == "provenance"
      check rec.blockReason.contains("fetchExtractionJobRecord")
      check countCertFiles(certDir) == 0
      removeDir(certDir)

    test "P4: tampered job record → the ledger refuses at issuance, fail-closed":
      let repo = materializeProbeSubject("axiom_rust_prov_tamper")
      let certDir = issuanceCertDir("tamper")
      let backend = FakeBackend(tip: "", entries: @[], counter: 0)
      # run 1 lands the record and mints
      let rec1 = rustSubjectIssuance(
        probeText, "add_u8", specAddAdd(), certDir,
        repo / "src" / "lib.rs", readFile(repo / "src" / "lib.rs"),
        subjectRoot = repo, llbcPath = ProbePath,
        extractionLedger = some(makeBackend(backend)),
        extractionLedgerRepo = "owner/repo")
      check rec1.issued
      let llbcDigest = sha256Hex(probeText)
      check tamperStoredLlbcByte(backend, rec1.extractionJobKey, llbcDigest)
      # run 2 (identical inputs): the append re-reads the existing entry, the
      # payloadSha256 re-verification detects the flipped byte, and issuance
      # fails closed at the provenance stage
      let rec2 = rustSubjectIssuance(
        probeText, "add_u8", specAddAdd(), certDir,
        repo / "src" / "lib.rs", readFile(repo / "src" / "lib.rs"),
        subjectRoot = repo, llbcPath = ProbePath,
        extractionLedger = some(makeBackend(backend)),
        extractionLedgerRepo = "owner/repo")
      check rec2.attempted
      check not rec2.issued
      check rec2.blockStage == "provenance"
      check rec2.blockReason.contains("fail-closed")
      check countCertFiles(certDir) == 1  # only run 1's cert exists
      removeDir(certDir)

    test "P5: recorded charon_version != pinned → verifyExtractionEnvironment " &
        "refuses issuance (fail-closed)":
      # The LLBC header is the recorded provenance source: tamper it and the
      # job record records 9.9.999, which the pinned identity refuses.
      let tamperedHeader = probeText.replace(
        "\"charon_version\":\"" & PinnedCharonVersion & "\"",
        "\"charon_version\":\"9.9.999\"")
      check tamperedHeader != probeText
      let tamperedPath = getTempDir() / ("axiom_rust_prov_hdr_" &
        $getCurrentProcessId() & ".llbc")
      writeFile(tamperedPath, tamperedHeader)
      let repo = materializeProbeSubject("axiom_rust_prov_pinned")
      let certDir = issuanceCertDir("pinned")
      let backend = FakeBackend(tip: "", entries: @[], counter: 0)
      let rec = rustSubjectIssuance(
        tamperedHeader, "add_u8", specAddAdd(), certDir,
        repo / "src" / "lib.rs", readFile(repo / "src" / "lib.rs"),
        subjectRoot = repo, llbcPath = tamperedPath,
        extractionLedger = some(makeBackend(backend)),
        extractionLedgerRepo = "owner/repo")
      check rec.attempted
      check not rec.issued
      check rec.blockStage == "provenance"
      check rec.blockReason.contains("charon version")
      check rec.blockReason.contains("fail-closed")
      # the tampered record DID land (it is well-formed, merely not pinned) —
      # the gate refused at attestation time, nothing was minted
      check storedEntry(backend, rec.extractionJobKey & ".json").contains("9.9.999")
      check countCertFiles(certDir) == 0
      removeDir(certDir)
      try:
        removeFile(tamperedPath)
      except CatchableError:
        discard  # axiom:best-effort(test temp cleanup — a residual tampered fixture file must not mask the assertion verdict)

  if z3Present:
    suite "rust_subject provenance issuance — declared-lane counterexample " &
        "confirmation (real probe, z3-gated)":

      test "P7: mutant + armed provenance → kernel decline CONFIRMED by the " &
          "replayed refuting model; NO certificate":
        let repo = materializeProbeSubject("axiom_rust_prov_confirmed")
        let certDir = issuanceCertDir("confirmed")
        let backend = FakeBackend(tip: "", entries: @[], counter: 0)
        let rec = rustSubjectIssuance(
          probeText, "add_u8_mutant", specAddAdd(), certDir,
          repo / "src" / "lib.rs", readFile(repo / "src" / "lib.rs"),
          subjectRoot = repo,
          llbcPath = ProbePath,
          extractionLedger = some(makeBackend(backend)),
          extractionLedgerRepo = "owner/repo")
        # The spec f(a,b)=a+b is false for the mutant: the FIRST blocking
        # point is still the kernel — but the decline is now CONFIRMED, not
        # unconfirmed: z3's refuting candidate is replayed on the real
        # rustc harness and reproduces the violation.
        check rec.attempted
        check not rec.issued
        check rec.blockStage == "kernel"
        check rec.blockSite.len > 0
        check rec.counterexampleConfirmed
        check rec.blockReason.contains("spec declined by kernel; " &
          "counterexample CONFIRMED")
        # the confirmed payload names the replayed input + the reproduced
        # violation (the replay adapter's own record folds — no bare model)
        check rec.confirmedPayload.len > 0
        check rec.confirmedPayload.anyIt(it.startsWith("input.a="))
        check rec.confirmedPayload.anyIt(it.startsWith("input.b="))
        check rec.confirmedPayload.anyIt(it == "replay.verdict=rvAgree")
        # NOTHING was written — a confirmed violation mints no certificate.
        check countCertFiles(certDir) == 0
        removeDir(certDir)

      test "P7 control: the positive add_u8 stays ISSUED with nothing to " &
          "confirm (counterexampleConfirmed false, empty payload)":
        let repo = materializeProbeSubject("axiom_rust_prov_ctrl")
        let certDir = issuanceCertDir("ctrl")
        let backend = FakeBackend(tip: "", entries: @[], counter: 0)
        let rec = rustSubjectIssuance(
          probeText, "add_u8", specAddAdd(), certDir,
          repo / "src" / "lib.rs", readFile(repo / "src" / "lib.rs"),
          subjectRoot = repo,
          llbcPath = ProbePath,
          extractionLedger = some(makeBackend(backend)),
          extractionLedgerRepo = "owner/repo")
        check rec.attempted
        check rec.issued
        check rec.blockStage == ""
        check not rec.counterexampleConfirmed
        check rec.confirmedPayload.len == 0
        check fileExists(rec.certPath)
        removeDir(certDir)

  suite "rust_subject provenance issuance — pure units":

    test "P6: recordedExtractionContract records embedded members verbatim; " &
        "absent members → empty contract":
      let withMembers = parseJson(
        "{\"charon_version\":\"0.1.281\",\"translated\":{\"options\":{\"ullbc\":false,\"rustc_args\":[]},\"target_information\":[{\"key\":\"x86_64-unknown-linux-gnu\"}]}}")
      let contract = recordedExtractionContract(withMembers)
      check contract.kind == JObject
      check contract.len == 2
      check contract{"translated.options"}.getStr() ==
        "{\"rustc_args\":[],\"ullbc\":false}"   # RFC 8785 canonical text
      check contract{"translated.target_information"}.getStr().contains(
        "x86_64-unknown-linux-gnu")
      let noTranslated = parseJson("{\"charon_version\":\"0.1.281\"}")
      check recordedExtractionContract(noTranslated).len == 0
      check recordedExtractionContract(parseJson("[1]")).len == 0
      check recordedExtractionContract(nil).len == 0

    test "P6: unarmed execution-contract digest stays the landed formula; " &
        "the armed binding moves it":
      let h = sha256Hex("theorem p : True := trivial")
      check rustLaneExecutionContractDigest(h) ==
            rustLaneExecutionContractDigest(h, "")
      check rustLaneExecutionContractDigest(h) !=
          rustLaneExecutionContractDigest(h, sha256Hex("extraction-evidence"))

echo ""
