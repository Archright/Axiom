import std/[base64, json, os, strutils]
import core/crypto/hash_kernel
import core/results
import verification/attestation_orchestrator
import verification/canonical_json
import verification/evidence_cas
import verification/evidence_ledger
import verification/extraction_agreement
import verification/kernel_reexecution
import verification/ledger_side_ref
import verification/subject_store
import verification/verification_subject

## Attestation chain × Evidence CAS integration tests (SL-15 admission
## evidence identity reuse).
##
## Isolation: the plan is resolved through the injectable LedgerTransport
## (in-memory FakeBackend — same approach as test_evidence_ledger.nim), so no
## network call and no real ledger ref is ever touched. The EvidenceKey is the
## REAL derived key (collectEvidenceKeyInputs over this workspace's canonical
## artifact set + fixture tree OIDs), because identity reuse is only
## meaningful against the true derivation.
##
## Coverage:
##   T1  env unset → casOff plan; attestWitnessChainCas ≡ attestChain parity
##       (subject-mismatch fixture, no kernel needed; agreement untouched)
##   T2  HIT: seeded ledger record under the REAL derived key → stages (b)+(c)
##       are the sanctioned §15.3 skip (poisoned tool paths would fail them if
##       they ran), reusedIrHash comes from the stored payload, (d)(e)(f) still
##       run fresh, exact HIT log line, rebound record = same key + payload,
##       rebound evidenceDigest == this run's evidenceBundleDigest (Condition A)
##   T3  MISS: fresh ledger → full chain (real lean/z3/ircheck, availability
##       guarded) → record file written/parseable/valid, payload bound to this
##       run's evidence + all-pass verdicts + 64-hex irHash; record
##       evidenceDigest == evidenceBundleDigest == independently re-hashed
##       canonical 7-member wire (wire-definition), != sha256(payload)
##       (non-confusion); a stripped (old-format) record fails the parse
##       (fail-closed backstop)
##   T4  corruption: tampered stored payload byte → plan casError → chain
##       atInternalError (never PASS); stored non-pass verdicts → reuse error
##   T5  formatter: exact HIT/MISS wire strings; casOff/casError are silent
##   T6  identity determinism: the provenance set is the EXECUTED members
##       only — a synthetic repoRoot with every fail-closed input but NO
##       bin/gate_hook yields the same key and the same successful plan as
##       the same root WITH the build-only binaries present (the 2026-10-06
##       incident shape); record provenance carries exactly ircheck
##   T7  fail-closed: a missing ircheck (the executed member) still errors —
##       collector err + plan casError

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

proc expectVerdict(name: string; got: AttestationResult; exp: AttestationVerdict) =
  if got.verdict == exp:
    echo "  [PASS] " & name
  else:
    inc failures
    echo "  FAIL: " & name & "\n      got: " & $got.verdict & ": " & got.reason &
      "\n      exp: " & $exp

proc skip(name: string; reason: string) =
  echo "  [SKIP] " & name & " (" & reason & ")"

# ---------------------------------------------------------------------------
# Fixtures (mirrors test_attestation.nim's witness-surface harness)
# ---------------------------------------------------------------------------

proc findRepoRoot(): string =
  var dir = getCurrentDir()
  while dir.len > 0:
    if fileExists(dir / ".axiom_root"):
      return dir
    let parent = parentDir(dir)
    if parent == dir: break
    dir = parent
  result = getCurrentDir()

let repoRoot = findRepoRoot()
let runId = $getCurrentProcessId()
let leanAvailable = findExe("lake").len > 0 and findExe("lean").len > 0
let z3Available = fileExists(getHomeDir() / ".local" / "bin" / "z3") or findExe("z3").len > 0
let workerAvailable = fileExists(repoRoot / "proofs" / ".lake" / "build" / "bin" / "ircheck")

const AttestInc3 = """
func inc3(a: int): int =
  let b = a + 1
  let c = b * 2
  c - 1
"""
const AttestLeanPass = "theorem axiom_attest_prop : True := by trivial"
const AttestSmtUnsat = "(declare-const x Int)\n(assert (and (> x 0) (< x 0)))\n(check-sat)"

proc hex40(seed: int): string =
  sha256Hex("candidate" & $seed & runId)[0 ..< 40]
proc hex64(seed: int): string =
  sha256Hex("seed" & $seed & runId)
proc hex40a(seed: int): string =
  sha256Hex("base" & $seed & runId)[0 ..< 40]
proc hex64a(seed: int): string =
  sha256Hex("env" & $seed & runId)

proc makeWitnessFixture(seed: int): tuple[subject: VerificationSubject, evidence: AttestationInputs] =
  ## Subject + evidence honoring the REAL subject-register invariant: the
  ## subject's evidenceDigest is sha256 over the evidence bundle wire, and the
  ## policy/scope digests come from the real lock files (stage-d/f compare
  ## against them without any kernel execution).
  let base = hex40a(seed)
  var ev = AttestationInputs(
    schemaVersion: EvidenceScheme,
    subjectId: "",
    prNumber: seed,
    prHeadSha: hex40(seed),
    leanSource: AttestLeanPass,
    smtlib2: AttestSmtUnsat,
    funcSource: AttestInc3,
    funcPath: "",
    funcName: "inc3",
    envDigest: hex64a(seed + 200),
    policyDigest: "",
    scopeDigest: "",
    toolchainIdentity: pinnedToolchainIdentity())
  ev.policyDigest = sha256Hex(readFile(repoRoot / "config" / "policy" / "merge_admission.json"))
  ev.scopeDigest = sha256Hex(readFile(repoRoot / "data" / "verification_scope.lock"))
  let made = makeSubject(base, ev.prHeadSha, hex64(seed),
    ev.policyDigest, ev.scopeDigest, evidenceBundleDigest(ev), seed,
    "2026-09-09T09:00:00Z")
  doAssert made.isOk
  let subject = made.get
  ev.subjectId = subject.subjectId
  (subject, ev)

# ---------------------------------------------------------------------------
# Fake transport backend (in-memory git object store — test_evidence_ledger)
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
    pendingSha: string
    pendingPath: string
    pendingContent: string

proc fakeSha(prefix: string; b: FakeBackend): string =
  inc b.counter
  sha256Hex(prefix & $b.counter & "evidence-cas-fixture")[0 ..< 40]

const NonEmptyFakeTreeSha = "e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1"
  ## Fixed non-empty tree sha served by the fake commit reader (zero entries
  ## ⇔ empty tree, mirroring the ledger ROOT commit).

proc makeTransport(b: FakeBackend): LedgerTransport =
  var fetch: JsonFetcher = proc(url: string): Result[JsonNode, string] {.raises: [CatchableError, OSError, Exception].} =
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
          return ok(%*{"content": encode(e.content), "encoding": "base64"})
      return err("fake fetch: unknown blob " & sha)
    err("fake fetch: unexpected " & url)
  var post: JsonPoster = proc(url: string; body: string): Result[JsonNode, string] {.raises: [CatchableError, OSError, Exception].} =
    if url.contains("/git/blobs"):
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
    let newSha = parseJson(body).getOrDefault("sha").getStr("")
    # FF commit lands: the pending object pipeline materializes as an entry.
    b.entries.add(EvidenceEntry(path: b.pendingPath, content: b.pendingContent,
      sha: b.pendingSha))
    b.tip = newSha
    ok(%*{"object": {"type": "commit", "sha": newSha}})
  var tip: LedgerTipFetcher = proc(repo: string): Result[string, string] {.raises: [CatchableError, OSError, Exception].} =
    ok(b.tip)
  LedgerTransport(fetch: fetch, post: post, patch: patch, tip: tip)

proc freshBackend(): FakeBackend =
  FakeBackend(tip: "", entries: @[], counter: 0)

# ---------------------------------------------------------------------------
# Env contract helpers (each block owns its env state)
# ---------------------------------------------------------------------------

proc clearCasEnv() =
  delEnv("AXIOM_EVIDENCE_CAS_ENABLED")
  delEnv("AXIOM_EVIDENCE_CAS_BASE_TREE_OID")
  delEnv("AXIOM_EVIDENCE_CAS_HEAD_TREE_OID")
  delEnv("AXIOM_EVIDENCE_CAS_MERGE_TREE_OID")
  delEnv("AXIOM_EVIDENCE_CAS_RECORD_PATH")

proc setCasEnv(baseOid, headOid, mergeOid, recordPath: string) =
  putEnv("AXIOM_EVIDENCE_CAS_ENABLED", "1")
  putEnv("AXIOM_EVIDENCE_CAS_BASE_TREE_OID", baseOid)
  putEnv("AXIOM_EVIDENCE_CAS_HEAD_TREE_OID", headOid)
  putEnv("AXIOM_EVIDENCE_CAS_MERGE_TREE_OID", mergeOid)
  putEnv("AXIOM_EVIDENCE_CAS_RECORD_PATH", recordPath)

proc fixtureOids(seed: int): tuple[base, head, merge: string] =
  (hex40(seed), hex40(seed + 1), hex40(seed + 2))

let tmpBase = getTempDir() / ("ax_cas_attest_" & runId)
createDir(tmpBase)

proc casOptions(subjectsDirName: string; poison: bool): AttestationOptions =
  ## Stage options for the chain: temp subject store, real policy/scope locks
  ## (digests come from the same files), and either poisoned tool paths (HIT
  ## must never execute the skipped stages) or auto-resolved real ones.
  var o = defaultAttestationOptions()
  o.subjectsDir = tmpBase / subjectsDirName
  createDir(o.subjectsDir)
  o.certDir = tmpBase / (subjectsDirName & "_certs")
  o.policyPath = repoRoot / "config" / "policy" / "merge_admission.json"
  o.scopeLockPath = repoRoot / "data" / "verification_scope.lock"
  if poison:
    o.leanExe = "/nonexistent/axiom-cas-test-lean"
    o.z3Path = "/nonexistent/axiom-cas-test-z3"
    o.ircheckExe = "/nonexistent/axiom-cas-test-ircheck"
  o

echo "=== attestation × evidence CAS tests ==="

# --- T1: env unset → casOff; chain parity with attestChain (no kernel) ---
block:
  clearCasEnv()
  let (subject, evidence) = makeWitnessFixture(11)
  let opts = casOptions("t1_subjects", poison = true)
  let saved = saveSubject(subject, opts.subjectsDir)
  expect(saved.isOk, "T1: subject persisted: " & (if saved.isErr: saved.error else: ""))
  # A subject whose store record will NOT match (altered baseSha): both chains
  # must fail at stage (a) with the identical verdict — casOff is a zero-delta
  # passthrough, and no CAS logging/mutation may occur.
  var wrongSubject = subject
  wrongSubject.baseSha = hex40a(999)
  let plan = planEvidenceCasWithTransport(repoRoot, makeTransport(freshBackend()))
  expect(plan.mode == casOff, "T1: env unset → casOff plan (got mode " & $plan.mode & ")")
  expect(plan.evidenceKey.len == 0, "T1: casOff plan carries no key")
  expect(evidenceCasReuseLogLine(plan).len == 0, "T1: casOff plan is silent")
  var agreeChain: ExtractionAgreementResult
  let rChain = attestChain(wrongSubject, evidence, opts, agreeChain)
  var agreeCas: ExtractionAgreementResult
  var reusedIgnored = ""
  let rCas = attestWitnessChainCas(wrongSubject, evidence, opts, agreeCas,
    plan, reusedIgnored)
  expectVerdict("T1: attestChain on subject mismatch → atSubjectMismatch",
    rChain, atSubjectMismatch)
  expectVerdict("T1: attestWitnessChainCas(casOff) ≡ attestChain",
    rCas, rChain.verdict)
  expect(agreeChain.nimDigest == "" and agreeCas.nimDigest == "",
    "T1: agreement untouched on stage-a failure in both chains")
  echo "Test T1 PASSED: casOff zero-delta parity"

# --- T2: HIT — stored record under the REAL derived key, §15.3 skip proven ---
block:
  let (subject, evidence) = makeWitnessFixture(21)
  let opts = casOptions("t2_subjects", poison = true)
  let saved = saveSubject(subject, opts.subjectsDir)
  expect(saved.isOk, "T2: subject persisted")
  let (baseOid, headOid, mergeOid) = fixtureOids(21)
  let recordPath = tmpBase / "t2_record.json"
  setCasEnv(baseOid, headOid, mergeOid, recordPath)
  # REAL key derivation over this workspace's canonical artifact set.
  let inputsRes = collectEvidenceKeyInputs(repoRoot, baseOid, headOid, mergeOid)
  expect(inputsRes.isOk, "T2: collectEvidenceKeyInputs: " &
    (if inputsRes.isErr: inputsRes.error else: ""))
  let casKey = deriveEvidenceKey(inputsRes.get)
  # The stored payload: this fixture's 4 bundle fields + a KNOWN irHash +
  # all-pass verdicts — exactly what the HIT re-verification accepts.
  let knownIrHash = hex64(219)
  let storedNe = NormalizedEvidence(
    funcSource: evidence.funcSource,
    funcName: evidence.funcName,
    leanSource: evidence.leanSource,
    smtlib2: evidence.smtlib2,
    irHash: knownIrHash,
    extractionVerdict: eaAgree,
    leanVerdict: krPassed,
    z3Verdict: krPassed)
  let storedPayload = normalizedEvidenceWire(storedNe)
  let storedRecRes = makeEvidenceRecord($casKey, storedPayload,
    %*{"attestation": "sha256:" & sha256Hex("t2-att")}, "2026-10-06T00:00:00Z",
    evidenceBundleDigest(evidence))
  expect(storedRecRes.isOk, "T2: stored record builds")
  let b = freshBackend()
  let seeded = appendEvidence(makeTransport(b), resolveEvidenceCasRepo(), storedRecRes.get)
  expect(seeded.isOk, "T2: ledger seed append: " &
    (if seeded.isErr: seeded.error else: ""))
  let plan = planEvidenceCasWithTransport(repoRoot, makeTransport(b))
  expect(plan.mode == casHit, "T2: seeded ledger → casHit (got " & $plan.mode & ": " & plan.reason & ")")
  if plan.mode == casHit:
    expect(plan.evidenceKey == $casKey, "T2: HIT plan carries the REAL derived key")
    expect(plan.payloadSha256 == sha256Hex(storedPayload), "T2: HIT plan payloadSha256 == sha256(stored payload)")
    expect(plan.payload == storedPayload, "T2: HIT plan payload round-trips byte-exact")
    checkEqStr("T2: exact HIT log line", evidenceCasReuseLogLine(plan),
      "AXIOM_EVIDENCE_CAS: HIT — reused + rebound record " & ($casKey)[0 ..< 12] &
      " (evidence bytes re-verified)")
  var agree: ExtractionAgreementResult
  var reusedIrHash = ""
  let r = attestWitnessChainCas(subject, evidence, opts, agree, plan, reusedIrHash)
  expectVerdict("T2: HIT chain passes WITHOUT stages (b)+(c) (poisoned tools prove the skip)",
    r, atPassed)
  checkEqStr("T2: reusedIrHash == the stored payload's irHash", reusedIrHash, knownIrHash)
  expect(agree.nimDigest == "" and agree.leanDigest == "",
    "T2: extraction agreement never ran (stage-b sanctioned skip)")
  # The rebound record (what the CLI writes on HIT): same identity, same
  # payload bytes → the trusted mint's append is an idempotent no-op.
  let rebound = buildEvidenceCasRecord(plan, plan.payload, evidence)
  expect(rebound.isOk, "T2: rebound record builds")
  if rebound.isOk:
    expect(rebound.get.evidenceKey == storedRecRes.get.evidenceKey,
      "T2: rebound record keeps the stored key")
    expect(rebound.get.payloadSha256 == storedRecRes.get.payloadSha256,
      "T2: rebound record keeps the stored payloadSha256")
    expect(rebound.get.evidenceDigest == evidenceBundleDigest(evidence),
      "T2: HIT rebound record evidenceDigest == this run's computed wire digest")
    expect(rebound.get.evidenceDigest == subject.evidenceDigest,
      "T2: HIT rebound record evidenceDigest == the witness's recorded evidenceDigest")
  clearCasEnv()
  echo "Test T2 PASSED: HIT reuse + §15.3 skip"

# --- T3: MISS — fresh production, record file emitted for the trusted mint ---
block:
  var (subject, evidence) = makeWitnessFixture(31)
  var opts = casOptions("t3_subjects", poison = false)
  opts.ircheckExe = repoRoot / "proofs" / ".lake" / "build" / "bin" / "ircheck"
  evidence.funcPath = tmpBase / ("ax_cas_ev_" & runId & ".nim")
  let saved = saveSubject(subject, opts.subjectsDir)
  expect(saved.isOk, "T3: subject persisted")
  let (baseOid, headOid, mergeOid) = fixtureOids(31)
  let recordPath = tmpBase / "t3_record.json"
  setCasEnv(baseOid, headOid, mergeOid, recordPath)
  let plan = planEvidenceCasWithTransport(repoRoot, makeTransport(freshBackend()))
  expect(plan.mode == casMiss, "T3: fresh ledger → casMiss (got " & $plan.mode & ": " & plan.reason & ")")
  if plan.mode == casMiss:
    checkEqStr("T3: exact MISS log line", evidenceCasReuseLogLine(plan),
      "AXIOM_EVIDENCE_CAS: MISS — produced + stored record " & plan.evidenceKey[0 ..< 12])
  var agree: ExtractionAgreementResult
  var reusedIrHash = ""
  if leanAvailable and z3Available and workerAvailable and plan.mode == casMiss:
    let r = attestWitnessChainCas(subject, evidence, opts, agree, plan, reusedIrHash)
    expectVerdict("T3: MISS chain runs the full (a)-(f) fresh and passes", r, atPassed)
    if r.verdict == atPassed:
      expect(agree.verdict == eaAgree and agree.nimDigest.len == 64,
        "T3: fresh agreement recorded (stages b+c ran for real)")
      expect(reusedIrHash.len == 0, "T3: MISS never reuses")
      let neRes = normalizedEvidenceForRun(evidence, agree)
      expect(neRes.isOk, "T3: normalizedEvidenceForRun: " &
        (if neRes.isErr: neRes.error else: ""))
      if neRes.isOk:
        let payload = normalizedEvidenceWire(neRes.get)
        let recRes = buildEvidenceCasRecord(plan, payload, evidence)
        expect(recRes.isOk, "T3: record builds: " &
          (if recRes.isErr: recRes.error else: ""))
        if recRes.isOk:
          let rec = recRes.get
          expect(rec.evidenceKey == plan.evidenceKey, "T3: record key == plan key")
          expect(rec.payloadSha256 == sha256Hex(payload), "T3: payloadSha256 == sha256(payload)")
          # Condition A single-definition binding: the record carries the
          # digest computed by the authority module from THIS run's inputs.
          let computedDigest = evidenceBundleDigest(evidence)
          expect(rec.evidenceDigest == computedDigest,
            "T3: record evidenceDigest == evidenceBundleDigest(this run's inputs)")
          expect(rec.evidenceDigest.len == 64, "T3: record evidenceDigest is 64 hex chars")
          expect(rec.evidenceDigest == subject.evidenceDigest,
            "T3: record evidenceDigest == the witness's .semantic.evidenceDigest (same inputs)")
          # Condition A non-confusion: the bundle-wire digest and the payload
          # hash are DIFFERENT objects — both computed here, asserted unequal.
          let payloadHash = sha256Hex(payload)
          expect(rec.evidenceDigest != payloadHash,
            "T3: non-confusion — evidenceDigest (7-member wire) != sha256(payload)")
          # D.3 wire-definition: an INDEPENDENTLY constructed canonical
          # 7-member wire hashes to the authority digest AND the record's
          # carried digest (no second definition anywhere in the chain).
          let independentWire = canonicalJsonString(%*{
            "funcSource": evidence.funcSource, "funcName": evidence.funcName,
            "leanSource": evidence.leanSource, "smtlib2": evidence.smtlib2,
            "toolchainIdentity": evidence.toolchainIdentity,
            "llbcDigest": evidence.llbcDigest,
            "rustToolchainIdentity": evidence.rustToolchainIdentity})
          checkEqStr("T3: wire-definition — sha256(independent 7-member wire) == evidenceBundleDigest",
            sha256Hex(independentWire), computedDigest)
          checkEqStr("T3: wire-definition — sha256(independent wire) == record.evidenceDigest",
            sha256Hex(independentWire), rec.evidenceDigest)
          writeFile(recordPath, evidenceRecordToCanonicalJson(rec))
          let parsed = parseEvidenceRecord(readFile(recordPath))
          expect(parsed.isOk, "T3: record file parses: " &
            (if parsed.isErr: parsed.error else: ""))
          if parsed.isOk:
            checkEqStr("T3: record validates cleanly", validateEvidenceRecord(parsed.get), "")
            let pj = parseJson(parsed.get.payload)
            expect(pj{"funcSource"}.getStr("") == evidence.funcSource and
              pj{"funcName"}.getStr("") == evidence.funcName and
              pj{"leanSource"}.getStr("") == evidence.leanSource and
              pj{"smtlib2"}.getStr("") == evidence.smtlib2,
              "T3: payload binds this run's four bundle fields byte-exact")
            expect(pj{"irHash"}.getStr() == agree.nimDigest,
              "T3: payload irHash == the fresh extraction identity")
            expect(pj{"extractionVerdict"}.getStr() == $eaAgree and
              pj{"leanVerdict"}.getStr() == $krPassed and
              pj{"z3Verdict"}.getStr() == $krPassed,
              "T3: payload verdicts restate the proven all-pass outcome")
          # REJECTION (fail-closed backstop): the same record JSON stripped of
          # evidenceDigest — an old-generation record — must fail the parse.
          var stripped = parseJson(readFile(recordPath))
          stripped.delete("evidenceDigest")
          let rejected = parseEvidenceRecord($stripped)
          expect(rejected.isErr and
            rejected.error.contains("missing or empty field 'evidenceDigest'"),
            "T3: record without evidenceDigest → parse err (fail-closed backstop)")
  else:
    skip("MISS full chain (real kernels)", "lean/z3/ircheck not available")
  clearCasEnv()
  echo "Test T3 PASSED: MISS production + record emission"

# --- T4: corruption → casError → atInternalError (never PASS) ---
block:
  let (subject, evidence) = makeWitnessFixture(41)
  let opts = casOptions("t4_subjects", poison = true)
  let saved = saveSubject(subject, opts.subjectsDir)
  expect(saved.isOk, "T4: subject persisted")
  let (baseOid, headOid, mergeOid) = fixtureOids(41)
  setCasEnv(baseOid, headOid, mergeOid, tmpBase / "t4_record.json")
  let keyInputs = collectEvidenceKeyInputs(repoRoot, baseOid, headOid, mergeOid)
  expect(keyInputs.isOk, "T4: key inputs collect")
  let casKey = deriveEvidenceKey(keyInputs.get)
  let ne = NormalizedEvidence(
    funcSource: evidence.funcSource, funcName: evidence.funcName,
    leanSource: evidence.leanSource, smtlib2: evidence.smtlib2,
    irHash: hex64(419), extractionVerdict: eaAgree,
    leanVerdict: krPassed, z3Verdict: krPassed)
  let payload = normalizedEvidenceWire(ne)
  let recRes = makeEvidenceRecord($casKey, payload, newJObject(), "2026-10-06T00:00:00Z",
    evidenceBundleDigest(evidence))
  expect(recRes.isOk, "T4: stored record builds")
  let b = freshBackend()
  expect(appendEvidence(makeTransport(b), resolveEvidenceCasRepo(), recRes.get).isOk,
    "T4: seed append lands")
  # Flip ONE byte of the stored payload: the record JSON still parses, but
  # sha256(payload) no longer matches payloadSha256 → the plan must fail
  # closed at fetch/verify, never degrade into a MISS.
  var flipped = payload
  flipped[7] = 'X'
  var stored = parseJson(b.entries[0].content)
  stored["payload"] = %flipped
  b.entries[0].content = $stored
  let plan = planEvidenceCasWithTransport(repoRoot, makeTransport(b))
  expect(plan.mode == casError, "T4: tampered payload → casError (got " & $plan.mode & ")")
  expect(plan.reason.contains("fail-closed"), "T4: casError reason is fail-closed")
  var agree: ExtractionAgreementResult
  var reused = ""
  let r = attestWitnessChainCas(subject, evidence, opts, agree, plan, reused)
  expectVerdict("T4: corrupt-ledger plan → atInternalError (a corrupt record never PASSes)",
    r, atInternalError)
  expect(r.reason.contains("evidence CAS"), "T4: internal error names the CAS cause")
  clearCasEnv()
  # Direct reuse re-verification refusals (the HIT-side fail-closed contract).
  let badJson = reuseIrHashFromPayload("{not json", evidence)
  expect(badJson.isErr and badJson.error.contains("not valid JSON"),
    "T4: unparseable stored payload → reuse error")
  let nonPass = reuseIrHashFromPayload($(%*{
    "funcSource": evidence.funcSource, "funcName": evidence.funcName,
    "leanSource": evidence.leanSource, "smtlib2": evidence.smtlib2,
    "irHash": hex64(420), "extractionVerdict": $eaMismatch,
    "leanVerdict": $krPassed, "z3Verdict": $krPassed}), evidence)
  expect(nonPass.isErr and nonPass.error.contains("ALL-PASS"),
    "T4: stored non-pass verdict → reuse error (never reusable)")
  let badHash = reuseIrHashFromPayload($(%*{
    "funcSource": evidence.funcSource, "funcName": evidence.funcName,
    "leanSource": evidence.leanSource, "smtlib2": evidence.smtlib2,
    "irHash": "nothex", "extractionVerdict": $eaAgree,
    "leanVerdict": $krPassed, "z3Verdict": $krPassed}), evidence)
  expect(badHash.isErr and badHash.error.contains("64-hex"),
    "T4: non-64-hex stored irHash → reuse error")
  let divergent = reuseIrHashFromPayload($(%*{
    "funcSource": "func other(a: int): int = a", "funcName": evidence.funcName,
    "leanSource": evidence.leanSource, "smtlib2": evidence.smtlib2,
    "irHash": hex64(421), "extractionVerdict": $eaAgree,
    "leanVerdict": $krPassed, "z3Verdict": $krPassed}), evidence)
  expect(divergent.isErr and divergent.error.contains("diverges"),
    "T4: bundle-field divergence → identity anomaly, reuse error")
  echo "Test T4 PASSED: corruption fail-closed (plan + reuse)"

# --- T5: formatter exact strings ---
block:
  let hitPlan = EvidenceCasPlan(mode: casHit, evidenceKey: sha256Hex("t5-hit"))
  checkEqStr("T5: HIT line exact", evidenceCasReuseLogLine(hitPlan),
    "AXIOM_EVIDENCE_CAS: HIT — reused + rebound record " &
    sha256Hex("t5-hit")[0 ..< 12] & " (evidence bytes re-verified)")
  let missPlan = EvidenceCasPlan(mode: casMiss, evidenceKey: sha256Hex("t5-miss"))
  checkEqStr("T5: MISS line exact", evidenceCasReuseLogLine(missPlan),
    "AXIOM_EVIDENCE_CAS: MISS — produced + stored record " &
    sha256Hex("t5-miss")[0 ..< 12])
  checkEqStr("T5: casOff is silent", evidenceCasReuseLogLine(
    EvidenceCasPlan(mode: casOff)), "")
  checkEqStr("T5: casError is silent", evidenceCasReuseLogLine(
    EvidenceCasPlan(mode: casError, reason: "x")), "")
  echo "Test T5 PASSED: log-line formatter"

# --- T6/T7 fixture: minimal repoRoot with every fail-closed collector input ---
proc makeCasFixtureRoot(name: string; withIrcheck: bool): string =
  ## The complete fail-closed input set of collectEvidenceKeyInputs over a
  ## synthetic root: recipe set, pins, draft/scope/policy files, and the
  ## executed member ircheck — NO build-only binaries (bin/ax, bin/gate_hook,
  ## …), which no verification path executes.
  let root = tmpBase / (name & "_" & runId)
  for rel in ["Makefile", "config.nims", "config/effects.nims",
              "src/gate/config.nims",
              "proofs/lean-toolchain",
              "data/policy/z3_binary_checksums.json",
              "data/certification/evidence-draft.json",
              "data/verification_scope.lock",
              "config/decision_binding.waiver.json",
              "config/policy/epoch_manifest.json",
              "config/policy/landing_required_gateway_tests.json",
              "config/policy/merge_admission.json",
              "config/trusted_writer_set.json"]:
    let p = root / rel
    let dir = p.parentDir
    if dir.len > 0: createDir(dir)
    writeFile(p, "fixture: " & rel & "\n")
  if withIrcheck:
    createDir(root / "proofs" / ".lake" / "build" / "bin")
    writeFile(root / "proofs" / ".lake" / "build" / "bin" / "ircheck",
      "fixture ircheck bytes\n")
  root

# --- T6: identity determinism — provenance set is the EXECUTED members only ---
block:
  let (baseOid, headOid, mergeOid) = fixtureOids(61)
  let recordPath = tmpBase / "t6_record.json"
  setCasEnv(baseOid, headOid, mergeOid, recordPath)
  let cold = makeCasFixtureRoot("t6_root", withIrcheck = true)
  let inCold = collectEvidenceKeyInputs(cold, baseOid, headOid, mergeOid)
  expect(inCold.isOk, "T6: key inputs collect WITHOUT build-only binaries: " &
    (if inCold.isErr: inCold.error else: ""))
  if inCold.isOk:
    let keyCold = deriveEvidenceKey(inCold.get)
    let planCold = planEvidenceCasWithTransport(cold, makeTransport(freshBackend()))
    expect(planCold.mode == casMiss, "T6: plan succeeds without bin/gate_hook (got " &
      $planCold.mode & ": " & planCold.reason & ")")
    # The build-only binaries appear on disk (warm-workspace shape): identical
    # inputs must give the identical key and the identical successful plan —
    # record provenance cannot move identity.
    createDir(cold / "bin")
    for bin in ["ax", "core_purity_gate", "gate_hook", "install_ax_cas",
                "precompile_gates"]:
      writeFile(cold / "bin" / bin, "build-only binary: " & bin & "\n")
    let inWarm = collectEvidenceKeyInputs(cold, baseOid, headOid, mergeOid)
    expect(inWarm.isOk, "T6: key inputs collect WITH build-only binaries")
    if inWarm.isOk:
      expect(deriveEvidenceKey(inWarm.get) == keyCold,
        "T6: identical inputs → identical key regardless of bin/gate_hook")
    let planWarm = planEvidenceCasWithTransport(cold, makeTransport(freshBackend()))
    expect(planWarm.mode == casMiss and planWarm.evidenceKey == planCold.evidenceKey,
      "T6: identical inputs → identical successful plan regardless of bin/gate_hook (got " &
        $planWarm.mode & "/" & $planCold.mode & ")")
    # The provenance field keeps its name and carries exactly the executed member.
    expect(planCold.verifierArtifactDigests.len == 1 and
      planCold.verifierArtifactDigests.hasKey("ircheck"),
      "T6: plan provenance carries exactly the executed member ircheck")
    let (_, t6Evidence) = makeWitnessFixture(63)
    let recRes = buildEvidenceCasRecord(planCold, "{\"irHash\":\"" & hex64(62) & "\"}",
      t6Evidence)
    expect(recRes.isOk, "T6: record builds")
    if recRes.isOk:
      expect(recRes.get.verifierArtifactDigests.len == 1 and
        recRes.get.verifierArtifactDigests.hasKey("ircheck"),
        "T6: record verifierArtifactDigests = {ircheck} (field name unchanged)")
      expect(recRes.get.evidenceDigest == evidenceBundleDigest(t6Evidence),
        "T6: record evidenceDigest == evidenceBundleDigest(fixture inputs)")
  clearCasEnv()
  echo "Test T6 PASSED: executed-member provenance — bin/gate_hook cannot move the key or the plan"

# --- T7: fail-closed — the executed member's absence is still an error ---
block:
  let (baseOid, headOid, mergeOid) = fixtureOids(71)
  setCasEnv(baseOid, headOid, mergeOid, tmpBase / "t7_record.json")
  let bare = makeCasFixtureRoot("t7_root", withIrcheck = false)
  let inRes = collectEvidenceKeyInputs(bare, baseOid, headOid, mergeOid)
  expect(inRes.isErr and inRes.error.contains("ircheck") and
    inRes.error.contains("fail-closed"),
    "T7: missing ircheck → collector fails closed (got: " &
      (if inRes.isErr: inRes.error else: "ok") & ")")
  let plan = planEvidenceCasWithTransport(bare, makeTransport(freshBackend()))
  expect(plan.mode == casError and plan.reason.contains("ircheck"),
    "T7: missing ircheck → casError plan (got " & $plan.mode & ": " & plan.reason & ")")
  clearCasEnv()
  echo "Test T7 PASSED: missing ircheck fails closed (collector + plan)"

# leave the process env as we found it
clearCasEnv()

echo ""
if failures == 0:
  echo "=== All attestation × evidence CAS tests PASSED ==="
else:
  echo "=== " & $failures & " attestation × evidence CAS test assertion(s) FAILED ==="
  quit(1)
