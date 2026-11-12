import std/[algorithm, base64, json, os, strutils, tables]
import core/crypto/hash_kernel
import core/deterministic_cas_key
import core/results
import verification/accounting/execution_context
import verification/attestation_orchestrator
import verification/canonical_json
import verification/evidence_ledger
import verification/judgment_cas
import verification/ledger_side_ref
import verification/obligation/golden_fixture_ir
import verification/semantic_set_derivation
import verification/tested_tree_closure

## Judgment CAS unit tests (s1a — verification/judgment_cas.nim).
##
## v5 outcome semantics (2026-10-21): verified-REUSED is an admissible lane
## outcome for EVERY subject — an all-REUSED lane is green when each row
## passed the 5 contract conditions; only a zero-outcome lane (no EXECUTED
## and no verified-REUSED) is fail-closed. The lane guard in
## .github/workflows/admission-check.yml enforces exactly this vocabulary.
##
## The judgment identity, the payload contract, the plan decision, the
## record build + reuse re-verification, and the witness binding — the
## pieces that make "same verification → reuse, anything different → the
## original verification runs" enforceable.
##
## Isolation: ledger interactions run through the injectable LedgerTransport
## (in-memory FakeBackend — the test_attestation_evidence_cas pattern); no
## network call and no real ledger ref is ever touched. The plan and epoch
## groups derive the REAL judgment closure over this workspace (transitive
## test hash, golden fixtures, recipe, bundle digest, and the semantic set
## S = TreeUniverse(R) − N of the tested probe tree — component ⑤ v3) and
## therefore require the toolchain bundle to be measurable AND the tested
## tree to resolve in this workspace's object store — each guarded, skipped
## honestly when lean/lake/git are unavailable (the same convention as the
## evidence CAS test). The changed-tree drill additionally needs history
## beyond a shallow clone's depth-1 fetch and skips without it.

var failures = 0

proc expect(cond: bool; msg: string) =
  if cond:
    echo "  [PASS] " & msg
  else:
    inc failures
    echo "  FAIL: " & msg

proc expectErr(name: string; res: Result[string, string]; needle: string = "") =
  if res.isErr and (needle.len == 0 or res.error.contains(needle)):
    echo "  [PASS] " & name
  else:
    inc failures
    echo "  FAIL: " & name & "\n      got: " &
      (if res.isErr: "err(" & res.error & ")" else: "ok(" & res.get & ")") &
      (if needle.len > 0: "\n      expected err containing: " & needle else: "")

proc skip(name: string; reason: string) =
  echo "  [SKIP] " & name & " (" & reason & ")"

proc hex64(seed: int): string =
  sha256Hex("jcas-fixture-" & $seed)

proc hex40(seed: int): string =
  sha256Hex("jcas-oid-" & $seed)[0 ..< 40]

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

proc validClosure(seed: int): JudgmentClosure =
  ## A well-formed closure over synthetic digests + the REAL golden keys.
  JudgmentClosure(
    testSourceClosure: hex64(seed),
    goldenFixtures: hex64(seed + 1),
    toolchainBundle: hex64(seed + 2),
    semanticSetDigest: hex64(seed + 3),
    envSnapshot: hex64(seed + 4),
    recipe: hex64(seed + 5),
    compilerPins: hex64(seed + 6),
    completenessKeys: goldenCompletenessKeys(),
    schemaVersion: $VERIFICATION_SCHEMA_VERSION,
    executionConfig: hex64(seed + 8))

proc canonicalPayload(executionEpoch: string): JsonNode =
  ## A contract-valid judgment projection (canonical counts + distribution,
  ## seeded identities, real completeness keys, given epoch).
  %*{
    "schemaVersion": JudgmentPayloadSchema,
    "verdict": JudgmentVerdictAcceptAll,
    "kernelAcceptCount": 17,
    "probeCount": 14,
    "acceptsByTheorem": {
      "identityPostcondition_post": 3,
      "mulDivRoundtrip_post": 2,
      "normalizeMaxWorkers_post": 1,
      "subPostcondition_post": 11},
    "fold": {
      "inputHash": hex64(100),
      "irHash": hex64(101),
      "obligationHash": hex64(102),
      "leanSourceHash": hex64(103),
      "kaaIdentity": hex64(104),
      "artifactIdentity": hex64(105)},
    "cle": {
      "cleKaaDigest": hex64(107),
      "cleCanonicalKaaJson": hex64(108),
      "cleToolchainFingerprint": hex64(109)},
    "completenessKeys": goldenCompletenessKeys(),
    "executionEpoch": executionEpoch}

proc payloadBytes(executionEpoch: string): string =
  canonicalJsonString(canonicalPayload(executionEpoch))

# ---------------------------------------------------------------------------
# Fake transport backend (in-memory git object store — evidence CAS pattern)
# ---------------------------------------------------------------------------

type
  LedgerEntry = object
    path: string
    content: string
    sha: string

  FakeBackend = ref object
    tip: string
    entries: seq[LedgerEntry]
    counter: int
    pendingSha: string
    pendingPath: string
    pendingContent: string

proc fakeSha(prefix: string; b: FakeBackend): string =
  inc b.counter
  sha256Hex(prefix & $b.counter & "judgment-cas-fixture")[0 ..< 40]

const NonEmptyFakeTreeSha = "f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1"

proc makeTransport(b: FakeBackend): LedgerTransport =
  var fetch: JsonFetcher = proc(url: string): Result[JsonNode, string] {.raises: [CatchableError, OSError, Exception].} =
    if url.contains("/git/commits/"):
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
    b.entries.add(LedgerEntry(path: b.pendingPath, content: b.pendingContent,
      sha: b.pendingSha))
    b.tip = newSha
    ok(%*{"object": {"type": "commit", "sha": newSha}})
  var tip: LedgerTipFetcher = proc(repo: string): Result[string, string] {.raises: [CatchableError, OSError, Exception].} =
    ok(b.tip)
  LedgerTransport(fetch: fetch, post: post, patch: patch, tip: tip)

proc freshBackend(): FakeBackend =
  FakeBackend(tip: "", entries: @[], counter: 0)

# ---------------------------------------------------------------------------
# Env contract helpers (each group owns its env state)
# ---------------------------------------------------------------------------

proc clearJudgmentEnv() =
  delEnv(JudgmentEnabledEnv)
  delEnv(JudgmentTestedTreeOidEnv)
  delEnv(JudgmentRecordPathEnv)
  delEnv(JudgmentDecisionPathEnv)
  delEnv("AXIOM_JUDGMENT_CAS_EVIDENCE_PATH")
  delEnv(JudgmentForceExecutionEnv)
  # the force gate's belt trigger — cleared so the groups below decide the
  # venue deterministically instead of inheriting the runner's event name
  # (a merge_group Actions run would otherwise arm the gate implicitly)
  delEnv("GITHUB_EVENT_NAME")

proc seedRecord(b: FakeBackend; key, payload: string): bool =
  ## Append a judgment record to the fake ledger under key. The evidenceDigest
  ## mirrors production buildJudgmentRecord: the judgment module's single
  ## definition (judgmentProjectionDigest over the projection bytes).
  let built = makeEvidenceRecord(key, payload, newJObject(),
    "2026-10-08T00:00:00Z", judgmentProjectionDigest(payload))
  if built.isErr:
    inc failures
    echo "  FAIL: seedRecord: " & built.error
    return false
  let appended = appendEvidence(makeTransport(b), resolveEvidenceCasRepo(),
    built.get, EvidenceCasRefName)
  if appended.isErr:
    inc failures
    echo "  FAIL: seedRecord append: " & appended.error
    return false
  true

# ---------------------------------------------------------------------------
# G1 — key determinism + component sensitivity (pure)
# ---------------------------------------------------------------------------

echo "G1 — judgment key determinism + component sensitivity"
block:
  let a = deriveJudgmentKey(validClosure(1))
  let b = deriveJudgmentKey(validClosure(1))
  expect(a == b, "identical closures derive the identical key")
  expect(a.len == 64, "the key is 64 hex chars")
  var sensitive = 0
  var c = validClosure(1)
  c.testSourceClosure = hex64(50)
  if deriveJudgmentKey(c) != a: inc sensitive
  c = validClosure(1); c.goldenFixtures = hex64(51)
  if deriveJudgmentKey(c) != a: inc sensitive
  c = validClosure(1); c.toolchainBundle = hex64(52)
  if deriveJudgmentKey(c) != a: inc sensitive
  c = validClosure(1); c.semanticSetDigest = hex64(53)
  if deriveJudgmentKey(c) != a: inc sensitive
  c = validClosure(1); c.executionConfig = hex64(59)
  if deriveJudgmentKey(c) != a: inc sensitive
  c = validClosure(1); c.envSnapshot = hex64(54)
  if deriveJudgmentKey(c) != a: inc sensitive
  c = validClosure(1); c.recipe = hex64(55)
  if deriveJudgmentKey(c) != a: inc sensitive
  c = validClosure(1); c.compilerPins = hex64(56)
  if deriveJudgmentKey(c) != a: inc sensitive
  c = validClosure(1)
  c.completenessKeys[0] = hex64(57)
  if deriveJudgmentKey(c) != a: inc sensitive
  c = validClosure(1); c.schemaVersion = "1"
  if deriveJudgmentKey(c) != a: inc sensitive
  expect(sensitive == 10, "every closure member is key-sensitive (got " &
    $sensitive & "/10)")

  expect(validateJudgmentClosure(validClosure(1)) == "",
    "a well-formed closure validates clean")
  c = validClosure(1); c.testSourceClosure = "nothex"
  expect(validateJudgmentClosure(c).contains("testSourceClosure"),
    "a non-hex digest member is rejected")
  c = validClosure(1); c.semanticSetDigest = hex40(60)
  expect(validateJudgmentClosure(c).contains("semanticSetDigest"),
    "a 40-hex semanticSetDigest (not a 64-hex set digest) is rejected")
  c = validClosure(1); c.schemaVersion = "1"
  expect(validateJudgmentClosure(c).contains("schemaVersion"),
    "a stale schemaVersion is rejected")

# ---------------------------------------------------------------------------
# G2 — the payload contract (validateJudgmentPayloadNode)
# ---------------------------------------------------------------------------

echo "G2 — judgment payload contract"
block:
  let okNode = canonicalPayload(hex64(70))
  let okRes = validateJudgmentPayloadNode(okNode)
  expect(okRes.isOk, "a canonical payload validates")
  if okRes.isOk:
    expect(okRes.get.kernelAcceptCount == 17 and okRes.get.probeCount == 14,
      "the canonical counts round-trip")
    expect(okRes.get.facts.acceptsByTheorem == CanonicalAcceptsByTheorem,
      "the canonical distribution round-trips")

  proc violated(name: string; mutate: proc(n: JsonNode)) =
    let node = parseJson(payloadBytes(hex64(70)))
    mutate(node)
    expect(validateJudgmentPayloadNode(node).isErr, name)

  violated("wrong schemaVersion is rejected",
    proc(n: JsonNode) = n["schemaVersion"] = %"axiom.judgment.cas.v0")
  violated("a non-accept verdict is rejected (timeout FAIL is never reusable)",
    proc(n: JsonNode) = n["verdict"] = %"KERNEL_TIMEOUT")
  violated("kernelAcceptCount != 17 is rejected",
    proc(n: JsonNode) = n["kernelAcceptCount"] = %16)
  violated("probeCount != 14 is rejected",
    proc(n: JsonNode) = n["probeCount"] = %13)
  violated("a missing theorem count is rejected",
    proc(n: JsonNode) = n["acceptsByTheorem"].delete("subPostcondition_post"))
  violated("a distribution sum != 17 is rejected",
    proc(n: JsonNode) = n["acceptsByTheorem"]["subPostcondition_post"] = %12)
  violated("a non-canonical theorem key is rejected",
    proc(n: JsonNode) = n["acceptsByTheorem"]["extraTheorem_post"] = %0)
  violated("a non-hex fold member is rejected",
    proc(n: JsonNode) = n["fold"]["inputHash"] = %"zz")
  violated("a non-hex CLE member is rejected",
    proc(n: JsonNode) = n["cle"]["cleKaaDigest"] = %"")
  violated("a run-scope CLE member re-entering the payload is rejected " &
    "(the R2 evidenceId can never grow back)",
    proc(n: JsonNode) = n["cle"]["evidenceId"] = %hex64(106))
  violated("an extra non-canonical top-level field is rejected " &
    "(extra bytes would break same-closure ⇒ same-payload)",
    proc(n: JsonNode) = n["runReceiptDigest"] = %hex64(110))
  violated("an extra fold member is rejected",
    proc(n: JsonNode) = n["fold"]["extraIdentity"] = %hex64(111))
  violated("diverging completenessKeys are rejected (component ⑧ cross-check)",
    proc(n: JsonNode) = n["completenessKeys"].elems[0] = %hex64(71))
  violated("a non-hex executionEpoch is rejected",
    proc(n: JsonNode) = n["executionEpoch"] = %"0")
  violated("an empty payload object is rejected",
    proc(n: JsonNode) = n.fields = initOrderedTable[string, JsonNode]())

# ---------------------------------------------------------------------------
# G3 — the evidence-file flush (armed/unarmed, canary, round-trip)
# ---------------------------------------------------------------------------

echo "G3 — evidence file flush"
block:
  let tmpDir = getTempDir() / "jcas-test-" & $getCurrentProcessId()
  createDir(tmpDir)
  let evidencePath = tmpDir / "s1a-evidence.json"
  delEnv("AXIOM_JUDGMENT_CAS_EVIDENCE_PATH")
  let unarmed = writeJudgmentEvidenceFile(JudgmentMeasuredEvidence(
    kernelAcceptCount: 17, probeCount: 14,
    facts: aggregateAcceptFacts(@[]), fold: JudgmentFoldIdentity(),
    cle: JudgmentCleIdentity()))
  expectErr("an unarmed flush is refused", unarmed, "not armed")

  putEnv("AXIOM_JUDGMENT_CAS_EVIDENCE_PATH", evidencePath)
  let nonCanonical = JudgmentMeasuredEvidence(
    kernelAcceptCount: 16, probeCount: 14,
    facts: aggregateAcceptFacts(@[]), fold: JudgmentFoldIdentity(),
    cle: JudgmentCleIdentity())
  expectErr("a non-canonical measured count is refused (golden contract canary)",
    writeJudgmentEvidenceFile(nonCanonical), "not the canonical judgment set")
  expect(not fileExists(evidencePath),
    "a refused flush mints no evidence file (no write before validation)")

  let epoch = captureReuseVerificationContext().currentEpoch
  let valid = JudgmentMeasuredEvidence(
    kernelAcceptCount: 17,
    probeCount: 14,
    facts: JudgmentAcceptFacts(acceptsByTheorem: CanonicalAcceptsByTheorem,
      unknownTheorems: @[]),
    fold: JudgmentFoldIdentity(inputHash: hex64(100), irHash: hex64(101),
      obligationHash: hex64(102), leanSourceHash: hex64(103),
      kaaIdentity: hex64(104), artifactIdentity: hex64(105)),
    cle: JudgmentCleIdentity(cleKaaDigest: hex64(107),
      cleCanonicalKaaJson: hex64(108), cleToolchainFingerprint: hex64(109)))
  let written = writeJudgmentEvidenceFile(valid)
  expect(written.isOk, "an armed canonical flush writes the evidence file")
  if written.isOk:
    let reparsed = parseJudgmentEvidenceFile(evidencePath)
    expect(reparsed.isOk and reparsed.get == written.get,
      "the flushed bytes re-parse byte-identically")
    let node = parseJson(readFile(evidencePath))
    let storedEpoch = node{"executionEpoch"}
    expect(not storedEpoch.isNil and storedEpoch.getStr() == epoch,
      "the flushed projection carries the CURRENT execution epoch")

  writeFile(evidencePath, written.get.replace(hex64(100)[0 ..< 8], "zzzzzzzz"))
  expect(fileExists(evidencePath),
    "the tampered evidence file stays on disk (inspection over silent cleanup)")
  expectErr("a tampered evidence file is refused (fail-closed)",
    parseJudgmentEvidenceFile(evidencePath))
  expect(not fileExists(tmpDir / "absent.json"),
    "the missing-file drill really targets an absent path")
  expectErr("a missing evidence file is refused",
    parseJudgmentEvidenceFile(tmpDir / "absent.json"), "not found")

  delEnv("AXIOM_JUDGMENT_CAS_EVIDENCE_PATH")
  removeDir(tmpDir)

# ---------------------------------------------------------------------------
# G4 — the witness judgment binding
# ---------------------------------------------------------------------------

echo "G4 — witness judgment binding"
block:
  let projection = payloadBytes(hex64(80))
  let node = judgmentWitnessNode(JudgmentWitnessBasisExecuted, hex64(81), projection)
  expect(validateJudgmentWitnessNode(node) == "",
    "a well-formed judgment witness binding validates clean")
  var tampered = parseJson($node)
  tampered["projectionSha256"] = %hex64(82)
  expect(validateJudgmentWitnessNode(tampered).contains("projectionSha256"),
    "a digest that does not bind the projection bytes is rejected")
  tampered = parseJson($node)
  tampered["basis"] = %"SKIPPED"
  expect(validateJudgmentWitnessNode(tampered).contains("basis"),
    "a foreign basis label is rejected")
  tampered = parseJson($node)
  tampered["evidenceKey"] = %"short"
  expect(validateJudgmentWitnessNode(tampered).contains("evidenceKey"),
    "a non-64-hex evidenceKey is rejected")
  tampered = parseJson($node)
  tampered["projection"] = %""
  expect(validateJudgmentWitnessNode(tampered).contains("projection"),
    "an empty projection is rejected")
  expect(validateJudgmentWitnessNode(%"[]").contains("JSON object"),
    "a non-object binding is rejected")

# ---------------------------------------------------------------------------
# Bundle measurement availability (plan/epoch groups)
# ---------------------------------------------------------------------------

let bundleRes = collectToolchainBundleDigest()
let bundleAvailable = bundleRes.isOk

# Real git trees — component ⑤ v3 derives the SEMANTIC SET from the PROBE
# tree (b-probe-tree), so the closure-derived groups need a tree that
# resolves in THIS workspace's object store. Honesty rule: no resolvable
# tree → the groups skip exactly like the unmeasurable bundle does. The
# changed-tree drill probes a PINNED history pair (below) whose objects a
# shallow clone's depth-1 fetch does not carry — it skips honestly there.
proc resolveRealTree(spec: string): string =
  ## spec must be a single argv token (no spaces, no shell metachars) — the
  ## derivation boundary spawns git WITHOUT a shell (Q-012 raw capture,
  ## docs/spec/nim_2_2_10_stdlib_quirks.md).
  let r = runGitOrErr(".", "rev-parse " & spec)
  let t =
    if r.isOk: r.get.strip()
    else: ""
  if isHexLen(t, 40): t else: ""

let realTestedTree = resolveRealTree("HEAD^{tree}")
let treesAvailable = realTestedTree.len == 40

const
  ## G10(e) changed-universe probe pair — PINNED history, never the checkout's
  ## incidental HEAD~1. The pre-fix drill derived the second closure from
  ## HEAD~1^{tree}: at a docs-only tip the parent delta is universe-EXCLUDED
  ## (NoEffectExtensionRules exclude .md prose), so both trees derived the SAME
  ## judgment key (proven 2026-10-17 on the clean tree: both f2e87c3ec18a8dcf…
  ## for de2ce1645c vs 73ddf035f7 at the docs-only #891 tip) and the `k3 != k1`
  ## premise failed — a tip-shape hermeticity defect, not a contract change.
  ## This pair's delta is fully universe-affecting (src/cli/cert_cli.nim +
  ## src/verification/judgment_cas.nim — .nim is never excluded), so its two
  ## keys provably differ forever, measured via the production derivation
  ## (collectJudgmentClosureFor → deriveJudgmentKey):
  ##   c9cca2655^{tree} → f2e87c3ec18a8dcf1e77d89cf5a2d8e840d534c79f3f07a00b53288fcab5a260
  ##   48a33ede4^{tree} → 9b66955050754130f2f2ccfae60e4b754ac17b243afcb8f4e799a4cf2d38e3ce
  ## (residual register: docs/evidence/mg_evidence_gate_followup_2026-10-17.md §5.2)
  g10eProbeBaseCommit = "c9cca26554cd963152b7b4eaffcbaf89246bfd7d"
  g10eProbeChangedCommit = "48a33ede439335bd53c44649e1e71b4de2e9f15c"

let probeBaseTree = resolveRealTree(g10eProbeBaseCommit & "^{tree}")
let probeChangedTree = resolveRealTree(g10eProbeChangedCommit & "^{tree}")
let probePairAvailable = probeBaseTree.len == 40 and probeChangedTree.len == 40 and
  probeBaseTree != probeChangedTree

echo "G5 — record build + reuse re-verification"
block:
  if not bundleAvailable:
    skip("G5", "toolchain bundle unmeasurable")
  else:
    let key = hex64(90)
    let epoch = captureReuseVerificationContext().currentEpoch
    let payload = payloadBytes(epoch)
    let built = buildJudgmentRecord(key, payload)
    expect(built.isOk, "a judgment record builds from the projection")
    if built.isOk:
      let record = built.get
      expect(record.evidenceKey == key and record.payload == payload,
        "the record binds the key and the exact projection bytes")
      expect(record.payloadSha256 == sha256Hex(payload),
        "payloadSha256 is the digest of the payload bytes")
      let reuse = verifyJudgmentReuse(record, key)
      expect(reuse.ok and reuse.payload == payload,
        "a fresh record re-verifies for reuse")
      expect(not verifyJudgmentReuse(record, hex64(91)).ok,
        "a different requested key fails the binding")
      var spliced = record
      spliced.payload = payloadBytes(hex64(92))
      expect(not verifyJudgmentReuse(spliced, key).ok,
        "a spliced payload fails the contract")
      let stalePayload = payloadBytes(hex64(93))
      let staleBuilt = makeEvidenceRecord(key, stalePayload, newJObject(),
        "2026-10-08T00:00:00Z", judgmentProjectionDigest(stalePayload))
      if staleBuilt.isOk:
        expect(not verifyJudgmentReuse(staleBuilt.get, key).ok,
          "a stale executionEpoch fails §15.3(e)")
      else:
        inc failures
        echo "  FAIL: stale record fixture build: " & staleBuilt.error

echo "G6 — the plan decision (injectable transport)"
block:
  clearJudgmentEnv()
  var plan = planJudgmentCasWithTransport(makeTransport(freshBackend()))
  expect(plan.mode == jOff, "env unset → jOff (zero behavior change)")

  putEnv(JudgmentEnabledEnv, "1")
  plan = planJudgmentCasWithTransport(makeTransport(freshBackend()))
  expect(plan.mode == jExecuted and
    plan.reason.contains(JudgmentTestedTreeOidEnv),
    "armed without a tested tree OID → jExecuted (fail-closed)")

  putEnv(JudgmentEnabledEnv, "2")
  plan = planJudgmentCasWithTransport(makeTransport(freshBackend()))
  expect(plan.mode == jExecuted and plan.reason.contains("is not '1'"),
    "an unexpected enabled value → jExecuted (fail-closed)")
  putEnv(JudgmentEnabledEnv, "1")
  plan = planJudgmentCasWithTransport(makeTransport(freshBackend()))
  expect(plan.mode == jExecuted and plan.reason.contains(JudgmentTestedTreeOidEnv),
    "armed without a tested tree OID → jExecuted (fail-closed)")
  putEnv(JudgmentTestedTreeOidEnv, hex40(95))
  plan = planJudgmentCasWithTransport(makeTransport(freshBackend()))
  expect(plan.mode == jExecuted and plan.reason.contains(JudgmentRecordPathEnv),
    "armed without a record path → jExecuted (fail-closed)")
  putEnv(JudgmentRecordPathEnv, getTempDir() / ("jcas-record-" & $getCurrentProcessId() & ".json"))

  if not bundleAvailable:
    skip("G6 closure-derived cases", "toolchain bundle unmeasurable")
    clearJudgmentEnv()
  elif not treesAvailable:
    skip("G6 closure-derived cases",
      "no resolvable tested tree in this workspace (git object store unavailable)")
    clearJudgmentEnv()
  else:
    let testedOid = realTestedTree   ## component ⑤ derives S from this probe
    putEnv(JudgmentTestedTreeOidEnv, testedOid)
    let collected = collectJudgmentClosure(testedOid)
    if collected.isErr:
      inc failures
      echo "  FAIL: closure collection: " & collected.error
      clearJudgmentEnv()
    else:
      let key = deriveJudgmentKey(collected.get)
      let epoch = captureReuseVerificationContext().currentEpoch

      # (a) empty ledger → EXECUTED (fresh judgment)
      plan = planJudgmentCasWithTransport(makeTransport(freshBackend()))
      expect(plan.mode == jExecuted and plan.reason.contains("no record"),
        "an empty ledger → jExecuted (the s1a runs)")
      expect(plan.evidenceKey == key,
        "the plan derives the same key as the direct closure derivation")

      # (b) a valid record under the current key → REUSED
      var b = freshBackend()
      if seedRecord(b, key, payloadBytes(epoch)):
        plan = planJudgmentCasWithTransport(makeTransport(b))
        expect(plan.mode == jReused,
          "a valid current-epoch record → jReused (got " & plan.reason & ")")

      # (c) a contract-violating stored payload → EXECUTED
      var tamperedPayload = parseJson(payloadBytes(epoch))
      tamperedPayload["fold"]["irHash"] = %"not-hex"
      b = freshBackend()
      if seedRecord(b, key, canonicalJsonString(tamperedPayload)):
        plan = planJudgmentCasWithTransport(makeTransport(b))
        expect(plan.mode == jExecuted and
          plan.reason.contains("judgment contract"),
          "a contract-violating stored payload → jExecuted")

      # (d) a stale executionEpoch → EXECUTED (§15.3(e))
      b = freshBackend()
      if seedRecord(b, key, payloadBytes(hex64(95))):
        plan = planJudgmentCasWithTransport(makeTransport(b))
        expect(plan.mode == jExecuted and plan.reason.contains("executionEpoch"),
          "a stale executionEpoch → jExecuted")

      # (e) a corrupted record → EXECUTED (never a guessed reuse)
      b = freshBackend()
      var wrongKeyPayload = payloadBytes(epoch)
      if seedRecord(b, hex64(96), wrongKeyPayload):
        plan = planJudgmentCasWithTransport(makeTransport(b))
        expect(plan.mode == jExecuted and plan.reason.contains("no record"),
          "a record under a different key is not this closure's record → jExecuted")
    clearJudgmentEnv()

echo "G7 — the attest-stage judgment branch"
block:
  clearJudgmentEnv()
  delEnv("GITHUB_TOKEN")
  let unarmed = runJudgmentAttestBranch()
  expect(unarmed.isOk and not unarmed.get.armed,
    "unarmed env → the branch is off (legacy witness bytes)")

  putEnv(JudgmentEnabledEnv, "1")
  let noDecision = runJudgmentAttestBranch()
  expectErr("an armed attest without a decision file is refused",
    (if noDecision.isErr: Result[string, string](ok: false, err: noDecision.error)
     else: Result[string, string](ok: true, value: "armed")),
    JudgmentDecisionPathEnv)

  let tmpDir = getTempDir() / "jcas-test-" & $getCurrentProcessId()
  createDir(tmpDir)
  let decisionPath = tmpDir / "decision.json"
  let recordPath = tmpDir / "judgment-record.json"
  let evidencePath = tmpDir / "s1a-evidence.json"
  putEnv(JudgmentDecisionPathEnv, decisionPath)
  let absentDecision = runJudgmentAttestBranch()
  expectErr("a decision file that does not exist is refused",
    (if absentDecision.isErr: Result[string, string](ok: false, err: absentDecision.error)
     else: Result[string, string](ok: true, value: "armed")),
    "not found")

  if not bundleAvailable:
    skip("G7 closure-derived cases", "toolchain bundle unmeasurable")
    clearJudgmentEnv()
    removeDir(tmpDir)
  elif not treesAvailable:
    skip("G7 closure-derived cases",
      "no resolvable tested tree in this workspace (git object store unavailable)")
    clearJudgmentEnv()
    removeDir(tmpDir)
  else:
    let testedOid = realTestedTree   ## component ⑤ derives S from this probe
    putEnv(JudgmentTestedTreeOidEnv, testedOid)
    putEnv(JudgmentRecordPathEnv, recordPath)
    let collected = collectJudgmentClosure(testedOid)
    if collected.isErr:
      inc failures
      echo "  FAIL: G7 closure collection: " & collected.error
    else:
      let key = deriveJudgmentKey(collected.get)
      let epoch = captureReuseVerificationContext().currentEpoch

      # (a) decision key != fresh key → refused
      writeFile(decisionPath, canonicalJsonString(%*{
        "basis": "EXECUTED", "evidenceKey": hex64(99), "reason": "test"}))
      let mismatch = runJudgmentAttestBranch()
      expectErr("a decision key that diverges from the fresh closure is refused",
        (if mismatch.isErr: Result[string, string](ok: false, err: mismatch.error)
         else: Result[string, string](ok: true, value: "armed")),
        "different closures")

      # (b) EXECUTED without an evidence file → refused
      writeFile(decisionPath, canonicalJsonString(%*{
        "basis": "EXECUTED", "evidenceKey": key, "reason": "test"}))
      delEnv("AXIOM_JUDGMENT_CAS_EVIDENCE_PATH")
      let noEvidence = runJudgmentAttestBranch()
      expectErr("an EXECUTED basis without an evidence file is refused",
        (if noEvidence.isErr: Result[string, string](ok: false, err: noEvidence.error)
         else: Result[string, string](ok: true, value: "armed")),
        "AXIOM_JUDGMENT_CAS_EVIDENCE_PATH")

      # (c) EXECUTED with the evidence file → the record publishes + binds
      putEnv("AXIOM_JUDGMENT_CAS_EVIDENCE_PATH", evidencePath)
      writeFile(evidencePath, payloadBytes(epoch))
      let executed = runJudgmentAttestBranch()
      expect(executed.isOk and executed.get.armed and
        executed.get.basis == JudgmentWitnessBasisExecuted,
        "an EXECUTED branch with its evidence proceeds")
      if executed.isOk and executed.get.armed:
        expect(executed.get.evidenceKey == key,
          "the branch binds the freshly re-derived key")
        expect(validateJudgmentWitnessNode(executed.get.node) == "",
          "the branch's witness binding validates clean")
        let node = parseJson($executed.get.node)
        expect(node{"projection"}.getStr() == payloadBytes(epoch),
          "the witness projection is the exact evidence-file bytes")
        expect(fileExists(recordPath), "the record file was published")
        let recordNode = parseJson(readFile(recordPath))
        expect(recordNode{"evidenceKey"}.getStr() == key and
          recordNode{"payload"}.getStr() == payloadBytes(epoch) and
          recordNode{"payloadSha256"}.getStr() == sha256Hex(payloadBytes(epoch)),
          "the published record binds key + payload + payloadSha256")

      # (d) REUSED without GITHUB_TOKEN → refused (the decision carries a
      #     well-shaped rootRecord marker so the shape check passes and the
      #     token check is the one that fires — G7(g) covers the marker-less
      #     rejection that now precedes it)
      writeFile(decisionPath, canonicalJsonString(%*{
        "basis": "REUSED", "evidenceKey": key, "reason": "test",
        "rootRecord": {"evidenceKey": key, "payloadSha256": hex64(971),
                        "executionEpoch": "e-g7d"}}))
      delEnv("AXIOM_JUDGMENT_CAS_EVIDENCE_PATH")
      delEnv("GITHUB_TOKEN")
      let noToken = runJudgmentAttestBranch()
      expectErr("a REUSED basis without GITHUB_TOKEN is refused",
        (if noToken.isErr: Result[string, string](ok: false, err: noToken.error)
         else: Result[string, string](ok: true, value: "armed")),
        "GITHUB_TOKEN")

      # (e) an OFF decision under an armed attest → refused
      writeFile(decisionPath, canonicalJsonString(%*{
        "basis": "OFF", "evidenceKey": key, "reason": "unarmed plan"}))
      let offDecision = runJudgmentAttestBranch()
      expectErr("an OFF decision under an armed attest is refused",
        (if offDecision.isErr: Result[string, string](ok: false, err: offDecision.error)
         else: Result[string, string](ok: true, value: "armed")),
        "basis")

      # (f) p3 provenance — a decision naming a DIFFERENT probe tree than the
      #     current env probe is refused (one admission run = one tree; the
      #     probe string is compared before any derivation, so a non-git
      #     40-hex stand-in is enough here)
      writeFile(decisionPath, canonicalJsonString(%*{
        "basis": "EXECUTED", "evidenceKey": key, "reason": "test",
        "probeTreeOid": hex40(98)}))
      let wrongProbe = runJudgmentAttestBranch()
      expectErr("a decision probeTreeOid that differs from the current probe is refused (p3)",
        (if wrongProbe.isErr: Result[string, string](ok: false, err: wrongProbe.error)
         else: Result[string, string](ok: true, value: "armed")),
        "probeTreeOid")

      # (g) redecision 2026-10-18 — a REUSED decision WITHOUT the rootRecord
      #     provenance marker is refused at the shape check BEFORE any ledger
      #     IO (the skip's root EXECUTED record is unattributable → fail-
      #     closed). A dummy token proves the rejection precedes the transport.
      writeFile(decisionPath, canonicalJsonString(%*{
        "basis": "REUSED", "evidenceKey": key, "reason": "test"}))
      putEnv("GITHUB_TOKEN", "test-token-marker-shape")
      let noMarker = runJudgmentAttestBranch()
      expectErr("a REUSED decision without the rootRecord marker is refused before any ledger IO (fail-closed)",
        (if noMarker.isErr: Result[string, string](ok: false, err: noMarker.error)
         else: Result[string, string](ok: true, value: "armed")),
        "rootRecord")
      # (h) the marker binding contract (pure): a well-shaped marker that
      #     binds the record checks clean; a tampered payloadSha256 or a
      #     foreign root key is refused (provenance mismatch)
      let boundRecord = makeEvidenceRecord(key, payloadBytes(epoch), newJObject(),
        "2026-10-08T00:00:00Z", judgmentProjectionDigest(payloadBytes(epoch)))
      expect(boundRecord.isOk, "the marker-binding fixture record builds")
      if boundRecord.isOk:
        let payloadNode = parseJson(payloadBytes(epoch))
        let goodMarker = %*{
          "evidenceKey": key, "payloadSha256": sha256Hex(payloadBytes(epoch)),
          "executionEpoch": epoch}
        expect(judgmentRootRecordMarkerMismatch(goodMarker, boundRecord.get,
            payloadNode) == "",
          "a correct rootRecord marker binds the record (binding check clean)")
        var tamperedSha = %*{
          "evidenceKey": key, "payloadSha256": hex64(911),
          "executionEpoch": epoch}
        expect(judgmentRootRecordMarkerMismatch(tamperedSha, boundRecord.get,
            payloadNode).contains("payloadSha256"),
          "a tampered marker payloadSha256 is refused (provenance mismatch, fail-closed)")
        var foreignKey = %*{
          "evidenceKey": hex64(912), "payloadSha256": sha256Hex(payloadBytes(epoch)),
          "executionEpoch": epoch}
        expect(judgmentRootRecordMarkerMismatch(foreignKey, boundRecord.get,
            payloadNode).contains("evidenceKey"),
          "a marker naming a foreign root key is refused (provenance mismatch, fail-closed)")
      delEnv("GITHUB_TOKEN")
    clearJudgmentEnv()
    removeDir(tmpDir)

# ---------------------------------------------------------------------------
# G8 — the extension subjects (proof_integrity / d2_golden / d2_persist)
# ---------------------------------------------------------------------------

proc proofIntegrityPayload(epoch: string): JsonNode =
  ## A contract-valid proof-integrity projection (canonical checkpoint set).
  var verdicts = newJObject()
  for i, name in CanonicalProofIntegrityCheckpoints:
    verdicts[name] = %CanonicalProofIntegrityVerdicts[i]
  %*{
    "schemaVersion": ProofIntegrityPayloadSchema,
    "verdict": JudgmentVerdictPredicatePassAll,
    "kernelRunCount": 0,
    "checkpointCount": ProofIntegrityCheckpointCount,
    "checkpointVerdicts": verdicts,
    "executionEpoch": epoch}

proc d2GoldenPayload(epoch: string): JsonNode =
  ## A contract-valid d2_golden projection (receipt identity 4 + 5-fold chain).
  %*{
    "schemaVersion": D2GoldenPayloadSchema,
    "verdict": JudgmentVerdictAcceptAll,
    "kernelRunCount": D2GoldenKernelRunCount,
    "theoremIdentity": D2GoldenTheoremIdentity,
    "receipt": {
      "executableDigest": hex64(200),
      "inputIdentity": hex64(201),
      "artifactIdentity": hex64(202),
      "toolchainFingerprint": hex64(203)},
    "identityChain": {
      "artifact": hex64(204),
      "execution": hex64(205),
      "kaa": hex64(206),
      "decision": hex64(207),
      "result": hex64(208)},
    "executionEpoch": epoch}

proc d2PersistPayload(epoch: string): JsonNode =
  ## A contract-valid d2_persist projection (loop checkpoints all true).
  var loops = newJObject()
  for name in CanonicalD2PersistLoopCheckpoints:
    loops[name] = %true
  %*{
    "schemaVersion": D2PersistPayloadSchema,
    "verdict": JudgmentVerdictPersistLoopVerified,
    "kernelRunCount": D2PersistKernelRunCount,
    "theoremIdentity": D2GoldenTheoremIdentity,
    "irHash": hex64(210),
    "loopCheckpoints": loops,
    "executionEpoch": epoch}

echo "G8 — extension subjects: schemas, closure, plan (per subject)"
block:
  let epoch = captureReuseVerificationContext().currentEpoch

  # (a) the canonical extension payloads validate through the dispatch
  expect(validateJudgmentPayloadNode(proofIntegrityPayload(epoch)).isOk,
    "a canonical proof_integrity payload validates through the dispatch")
  expect(validateJudgmentPayloadNode(d2GoldenPayload(epoch)).isOk,
    "a canonical d2_golden payload validates through the dispatch")
  expect(validateJudgmentPayloadNode(d2PersistPayload(epoch)).isOk,
    "a canonical d2_persist payload validates through the dispatch")

  proc xViolated(name: string; mutate: proc(n: JsonNode)) =
    for (label, builder) in [("proof_integrity", proofIntegrityPayload),
                             ("d2_golden", d2GoldenPayload),
                             ("d2_persist", d2PersistPayload)]:
      let node = builder(hex64(70))
      mutate(node)
      let r = validateJudgmentPayloadNode(node)
      expect(r.isErr, name & " [" & label & "]")

  xViolated("a wrong schemaVersion is rejected",
    proc(n: JsonNode) = n["schemaVersion"] = %"axiom.judgment.cas.v0")
  xViolated("a non-reusable verdict is rejected",
    proc(n: JsonNode) = n["verdict"] = %"KERNEL_TIMEOUT")
  xViolated("a wrong kernelRunCount is rejected",
    proc(n: JsonNode) = n["kernelRunCount"] = %99)
  # the non-hex identity member is subject-specific (each subject owns its
  # identity fields): proof_integrity — none (string verdicts only);
  # d2_golden — receipt.inputIdentity; d2_persist — irHash.
  block:
    let node = d2GoldenPayload(hex64(70))
    node["receipt"]["inputIdentity"] = %"zz"
    expect(validateJudgmentPayloadNode(node).isErr,
      "a non-hex receipt identity member is rejected [d2_golden]")
  block:
    let node = d2PersistPayload(hex64(70))
    node["irHash"] = %"zz"
    expect(validateJudgmentPayloadNode(node).isErr,
      "a non-hex irHash member is rejected [d2_persist]")
  block:
    let node = proofIntegrityPayload(hex64(70))
    node["checkpointVerdicts"]["admissionAdmit"] = %"varReject"
    expect(validateJudgmentPayloadNode(node).isErr,
      "a deviating checkpoint verdict is rejected [proof_integrity]")
  block:
    let node = d2PersistPayload(hex64(70))
    node["loopCheckpoints"]["writerPersisted"] = %false
    expect(validateJudgmentPayloadNode(node).isErr,
      "a false loop checkpoint is rejected [d2_persist]")
  block:
    let node = d2GoldenPayload(hex64(70))
    node["kernelRunCount"] = %13
    expect(validateJudgmentPayloadNode(node).isErr,
      "a kernel count off the canonical 14 is rejected [d2_golden]")
  xViolated("an extra non-canonical top-level field is rejected " &
    "(extra bytes would break same-closure ⇒ same-payload)",
    proc(n: JsonNode) = n["runReceiptDigest"] = %hex64(110))
  xViolated("an empty payload object is rejected",
    proc(n: JsonNode) = n.fields = initOrderedTable[string, JsonNode]())

  # (b) per-subject closure collection is well-formed and subject-separated
  if not bundleAvailable:
    skip("G8 closure-derived cases", "toolchain bundle unmeasurable")
  elif not treesAvailable:
    skip("G8 closure-derived cases",
      "no resolvable tested tree in this workspace (git object store unavailable)")
  else:
    let testedOid = realTestedTree   ## component ⑤ derives S from this probe
    var keys: array[4, string]
    var keyOk = true
    for s in allJudgmentSubjects():
      let collected = collectJudgmentClosureFor(s, testedOid)
      if collected.isErr:
        inc failures
        echo "  FAIL: closure collection [" & subjectName(s) & "]: " & collected.error
        keyOk = false
      else:
        keys[int(s)] = deriveJudgmentKey(collected.get)
        expect(validateJudgmentClosure(collected.get) == "",
          "the " & subjectName(s) & " closure validates clean")
    if keyOk:
      # subject separation: 4 distinct keys over the same tree
      var distinctPairs = 0
      for i in 0 ..< 4:
        for j in (i + 1) ..< 4:
          if keys[i] != keys[j]: inc distinctPairs
      expect(distinctPairs == 6, "the 4 subject keys are pairwise distinct (got " & $distinctPairs & "/6)")
      # the s1a closure stays byte-identical to its landed derivation
      let s1aDirect = collectJudgmentClosure(testedOid)
      expect(s1aDirect.isOk and deriveJudgmentKey(s1aDirect.get) == keys[int(jsS1aGolden)],
        "the s1a subject dispatch derives the landed s1a key (wire unchanged)")

      # (c) per-subject plan drills: 부재→실행 / 타주체 레코드→실행 / 정상→REUSED / 변조→거부
      putEnv(JudgmentEnabledEnv, "1")
      putEnv(JudgmentTestedTreeOidEnv, testedOid)
      putEnv(subjectRecordPathEnv(jsProofIntegrity), getTempDir() / ("jcas-pi-record-" & $getCurrentProcessId() & ".json"))
      putEnv(subjectRecordPathEnv(jsD2Golden), getTempDir() / ("jcas-d2g-record-" & $getCurrentProcessId() & ".json"))
      putEnv(subjectRecordPathEnv(jsD2Persist), getTempDir() / ("jcas-d2p-record-" & $getCurrentProcessId() & ".json"))
      putEnv(JudgmentRecordPathEnv, getTempDir() / ("jcas-s1a-record-" & $getCurrentProcessId() & ".json"))

      for (subject, payloadBuilder) in [(jsProofIntegrity, proofIntegrityPayload),
                                        (jsD2Golden, d2GoldenPayload),
                                        (jsD2Persist, d2PersistPayload)]:
        let key = keys[int(subject)]
        # 부재 → 실행
        var plan = planJudgmentCasForSubjectWithTransport(subject, makeTransport(freshBackend()))
        expect(plan.mode == jExecuted and plan.reason.contains("no record"),
          "[" & subjectName(subject) & "] an empty ledger → jExecuted (the test runs)")
        expect(plan.subject == subjectName(subject),
          "[" & subjectName(subject) & "] the plan names its subject")
        # 타주체 키의 레코드 → 이 클로저의 레코드 아님 → 실행
        var b = freshBackend()
        if seedRecord(b, keys[int(jsS1aGolden)], payloadBytes(epoch)):
          plan = planJudgmentCasForSubjectWithTransport(subject, makeTransport(b))
          expect(plan.mode == jExecuted and plan.reason.contains("no record"),
            "[" & subjectName(subject) & "] a record under another subject's key is not this closure's record → jExecuted")
        # 정상 → REUSED
        b = freshBackend()
        if seedRecord(b, key, canonicalJsonString(payloadBuilder(epoch))):
          plan = planJudgmentCasForSubjectWithTransport(subject, makeTransport(b))
          expect(plan.mode == jReused,
            "[" & subjectName(subject) & "] a valid current-epoch record → jReused (got " & plan.reason & ")")
        # 변조 → 거부
        var tampered = payloadBuilder(epoch)
        if subject == jsProofIntegrity:
          tampered["checkpointVerdicts"]["admissionAdmit"] = %"varReject"
        elif subject == jsD2Golden:
          tampered["receipt"]["inputIdentity"] = %"not-hex"
        else:
          tampered["loopCheckpoints"]["writerPersisted"] = %false
        b = freshBackend()
        if seedRecord(b, key, canonicalJsonString(tampered)):
          plan = planJudgmentCasForSubjectWithTransport(subject, makeTransport(b))
          expect(plan.mode == jExecuted and plan.reason.contains("judgment contract"),
            "[" & subjectName(subject) & "] a tampered stored payload → jExecuted")
        # 스테일 epoch → 거부
        b = freshBackend()
        if seedRecord(b, key, canonicalJsonString(payloadBuilder(hex64(95)))):
          plan = planJudgmentCasForSubjectWithTransport(subject, makeTransport(b))
          expect(plan.mode == jExecuted and plan.reason.contains("executionEpoch"),
            "[" & subjectName(subject) & "] a stale executionEpoch → jExecuted")
    clearJudgmentEnv()

echo "G9 — extension flushes (armed round-trip + canary)"
block:
  let tmpDir = getTempDir() / "jcas-test-" & $getCurrentProcessId()
  createDir(tmpDir)
  let epoch = captureReuseVerificationContext().currentEpoch

  # proof_integrity: armed round-trip + a deviating observation is refused
  putEnv(subjectEvidencePathEnv(jsProofIntegrity), tmpDir / "pi-evidence.json")
  var pi = ProofIntegrityJudgmentEvidence()
  for i, v in CanonicalProofIntegrityVerdicts:
    pi.checkpointVerdicts[i] = v
  let piWritten = writeProofIntegrityJudgmentEvidenceFile(pi)
  expect(piWritten.isOk, "the armed proof_integrity flush writes the evidence file")
  if piWritten.isOk:
    let reparsed = parseJudgmentEvidenceFile(getEnv(subjectEvidencePathEnv(jsProofIntegrity), ""))
    expect(reparsed.isOk and reparsed.get == piWritten.get,
      "the proof_integrity flushed bytes re-parse byte-identically")
  var piBad = pi
  piBad.checkpointVerdicts[0] = "varReject"
  expectErr("a deviating proof_integrity observation is refused (canary)",
    writeProofIntegrityJudgmentEvidenceFile(piBad), "deviates from the canonical")

  # d2_golden: armed round-trip + a non-canonical count is refused
  putEnv(subjectEvidencePathEnv(jsD2Golden), tmpDir / "d2g-evidence.json")
  let d2g = D2GoldenJudgmentEvidence(
    receiptExecutableDigest: hex64(200), receiptInputIdentity: hex64(201),
    receiptArtifactIdentity: hex64(202), receiptToolchainFingerprint: hex64(203),
    chainArtifact: hex64(204), chainExecution: hex64(205), chainKaa: hex64(206),
    chainDecision: hex64(207), chainResult: hex64(208))
  let d2gWritten = writeD2GoldenJudgmentEvidenceFile(d2g, D2GoldenKernelRunCount)
  expect(d2gWritten.isOk, "the armed d2_golden flush writes the evidence file")
  if d2gWritten.isOk:
    let reparsed = parseJudgmentEvidenceFile(getEnv(subjectEvidencePathEnv(jsD2Golden), ""))
    expect(reparsed.isOk and reparsed.get == d2gWritten.get,
      "the d2_golden flushed bytes re-parse byte-identically")
  expectErr("a non-canonical d2_golden kernel count is refused (canary)",
    writeD2GoldenJudgmentEvidenceFile(d2g, 13), "not the canonical d2_golden set")

  # d2_persist: armed round-trip + a false loop checkpoint is refused
  putEnv(subjectEvidencePathEnv(jsD2Persist), tmpDir / "d2p-evidence.json")
  var d2p = D2PersistJudgmentEvidence(irHash: hex64(210))
  for i in 0 ..< CanonicalD2PersistLoopCheckpoints.len:
    d2p.loopCheckpoints[i] = true
  let d2pWritten = writeD2PersistJudgmentEvidenceFile(d2p, D2PersistKernelRunCount)
  expect(d2pWritten.isOk, "the armed d2_persist flush writes the evidence file")
  if d2pWritten.isOk:
    let reparsed = parseJudgmentEvidenceFile(getEnv(subjectEvidencePathEnv(jsD2Persist), ""))
    expect(reparsed.isOk and reparsed.get == d2pWritten.get,
      "the d2_persist flushed bytes re-parse byte-identically")
  var d2pBad = d2p
  d2pBad.loopCheckpoints[0] = false
  expectErr("a false d2_persist loop checkpoint is refused (canary)",
    writeD2PersistJudgmentEvidenceFile(d2pBad, D2PersistKernelRunCount), "never a reusable judgment")

  # unarmed flushes are refused (the caller checks the armed state)
  delEnv(subjectEvidencePathEnv(jsProofIntegrity))
  delEnv(subjectEvidencePathEnv(jsD2Golden))
  delEnv(subjectEvidencePathEnv(jsD2Persist))
  expectErr("an unarmed proof_integrity flush is refused",
    writeProofIntegrityJudgmentEvidenceFile(pi), "not armed")
  expectErr("an unarmed d2_golden flush is refused",
    writeD2GoldenJudgmentEvidenceFile(d2g, D2GoldenKernelRunCount), "not armed")
  expectErr("an unarmed d2_persist flush is refused",
    writeD2PersistJudgmentEvidenceFile(d2p, D2PersistKernelRunCount), "not armed")

  # the extension witness node names its subject and validates clean
  let piNode = judgmentWitnessNodeFor(jsProofIntegrity, JudgmentWitnessBasisExecuted,
    hex64(81), piWritten.get)
  expect(validateJudgmentWitnessNode(piNode) == "",
    "a subject-tagged witness binding validates clean")
  expect(piNode{"subject"}.getStr() == "proof_integrity",
    "the extension witness binding carries its subject name")
  let s1aNode = judgmentWitnessNodeFor(jsS1aGolden, JudgmentWitnessBasisExecuted,
    hex64(81), payloadBytes(epoch))
  expect(s1aNode{"subject"}.isNil,
    "the s1a witness binding keeps its landed no-subject shape")

  removeDir(tmpDir)

# ---------------------------------------------------------------------------
# G10 — payload purity: same closure ⇒ same key + same payload bytes (R2)
# ---------------------------------------------------------------------------

echo "G10 — payload purity (the exactly-once ledger accepts a re-derived judgment)"
block:
  if not bundleAvailable:
    skip("G10", "toolchain bundle unmeasurable")
  elif not treesAvailable:
    skip("G10", "no resolvable tested tree in this workspace (git object store unavailable)")
  else:
    let tmpDir = getTempDir() / "jcas-test-" & $getCurrentProcessId()
    createDir(tmpDir)
    let evidencePath = tmpDir / "s1a-evidence.json"
    putEnv("AXIOM_JUDGMENT_CAS_EVIDENCE_PATH", evidencePath)
    putEnv(JudgmentEnabledEnv, "1")
    let testedOid = realTestedTree   ## component ⑤ derives S from this probe
    putEnv(JudgmentTestedTreeOidEnv, testedOid)

    proc measuredEvidence(): JudgmentMeasuredEvidence =
      ## The measured judgment evidence the s1a flush aggregates (canonical
      ## counts + a captured identity set — synthetic members here; the wire
      ## is field-determined, so they exercise the identical bytes path).
      JudgmentMeasuredEvidence(
        kernelAcceptCount: 17, probeCount: 14,
        facts: JudgmentAcceptFacts(acceptsByTheorem: CanonicalAcceptsByTheorem,
          unknownTheorems: @[]),
        fold: JudgmentFoldIdentity(inputHash: hex64(100), irHash: hex64(101),
          obligationHash: hex64(102), leanSourceHash: hex64(103),
          kaaIdentity: hex64(104), artifactIdentity: hex64(105)),
        cle: JudgmentCleIdentity(cleKaaDigest: hex64(107),
          cleCanonicalKaaJson: hex64(108), cleToolchainFingerprint: hex64(109)))

    # (a) same closure collected twice → the SAME judgment key
    let c1 = collectJudgmentClosureFor(jsS1aGolden, testedOid)
    let c2 = collectJudgmentClosureFor(jsS1aGolden, testedOid)
    expect(c1.isOk and c2.isOk, "the closure collects twice")
    if c1.isOk and c2.isOk:
      let k1 = deriveJudgmentKey(c1.get)
      let k2 = deriveJudgmentKey(c2.get)
      expect(k1 == k2, "same closure ⇒ same judgment key")
      expect(validateJudgmentClosure(c1.get) == "", "the closure validates clean")

      # (b) same closure flushed TWICE → byte-identical payload (the core
      #     new invariant: the payload is a pure function of the closure)
      let w1 = writeJudgmentEvidenceFile(measuredEvidence())
      let w2 = writeJudgmentEvidenceFile(measuredEvidence())
      expect(w1.isOk and w2.isOk, "both armed flushes write")
      if w1.isOk and w2.isOk:
        expect(w1.get == w2.get,
          "same closure ⇒ byte-identical payload (flush twice, same bytes)")
        let p1 = parseJudgmentEvidenceFile(evidencePath)
        expect(p1.isOk and p1.get == w1.get,
          "the flushed bytes re-validate byte-identically")

        # (c) ledger exactly-once across runs: the second run of the same
        #     closure appends the same (key, payload) → idempotent no-op —
        #     the R2 same-key/different-payload failure is gone.
        var b = freshBackend()
        let r1 = buildJudgmentRecord(k1, w1.get)
        expect(r1.isOk, "record #1 builds from flush #1")
        if r1.isOk:
          let a1 = appendEvidence(makeTransport(b), resolveEvidenceCasRepo(),
            r1.get, EvidenceCasRefName)
          expect(a1.isOk and not a1.get.alreadyPresent, "record #1 appends fresh")
          let r2 = buildJudgmentRecord(k2, w2.get)
          expect(r2.isOk, "record #2 builds from flush #2")
          if r2.isOk:
            let a2 = appendEvidence(makeTransport(b), resolveEvidenceCasRepo(),
              r2.get, EvidenceCasRefName)
            expect(a2.isOk and a2.get.alreadyPresent,
              "the same closure's second run is an idempotent no-op (same key + same payload bytes)")

            # (d) the guard stays armed: same key, DIFFERENT payload → refused
            var tamperedNode = parseJson(w1.get)
            tamperedNode["fold"]["irHash"] = %hex64(120)
            let tamperedPayload = canonicalJsonString(tamperedNode)
            let tamperedBuilt = makeEvidenceRecord(k1,
              tamperedPayload, newJObject(),
              "2026-10-08T00:00:00Z", judgmentProjectionDigest(tamperedPayload))
            if tamperedBuilt.isOk:
              let a3 = appendEvidence(makeTransport(b), resolveEvidenceCasRepo(),
                tamperedBuilt.get, EvidenceCasRefName)
              expect(a3.isErr and a3.error.contains("DIFFERENT payload bytes"),
                "same key + different payload bytes is still refused (guard intact)")
            else:
              inc failures
              echo "  FAIL: tampered record fixture: " & tamperedBuilt.error

        # (e) a changed closure (different tested tree) → different key →
        #     no record → the original execution runs (폐쇄 변경 → 실행).
        #     Both probe trees are PINNED history commits (g10eProbe*Commit):
        #     their delta is fully universe-affecting, so the two derived keys
        #     differ deterministically — regardless of the checkout's tip
        #     shape (the pre-fix HEAD~1 probe collapsed to the same key at
        #     docs-only tips). Each tree must RESOLVE in this object store
        #     (the v3 derivation fails closed otherwise); a shallow depth-1
        #     fetch carries neither pinned object and the drill skips
        #     honestly there.
        if not probePairAvailable:
          skip("G10(e) changed-tree drill",
            "pinned probe pair unresolvable (shallow clone / single-commit repo)")
        else:
          putEnv(JudgmentTestedTreeOidEnv, probeBaseTree)
          let c3a = collectJudgmentClosureFor(jsS1aGolden, probeBaseTree)
          expect(c3a.isOk, "the pinned base closure collects")
          putEnv(JudgmentTestedTreeOidEnv, probeChangedTree)
          let c3 = collectJudgmentClosureFor(jsS1aGolden, probeChangedTree)
          expect(c3.isOk, "the changed closure collects")
          if c3a.isOk and c3.isOk:
            let kBase = deriveJudgmentKey(c3a.get)
            let k3 = deriveJudgmentKey(c3.get)
            expect(k3 != kBase,
              "a changed universe (pinned pair) derives a different key")
            # the ledger semantics, fully pinned: the BASE closure's record
            # is on a fresh ledger; the changed closure's key must miss it →
            # jExecuted (the original execution runs)
            putEnv(JudgmentRecordPathEnv, tmpDir / "record.json")
            putEnv(JudgmentTestedTreeOidEnv, probeBaseTree)
            let wBase = writeJudgmentEvidenceFile(measuredEvidence())
            expect(wBase.isOk, "the base closure's payload flushes")
            var eb = freshBackend()
            if wBase.isOk:
              let rBase = buildJudgmentRecord(kBase, wBase.get)
              expect(rBase.isOk, "the base record builds")
              if rBase.isOk:
                let aBase = appendEvidence(makeTransport(eb),
                  resolveEvidenceCasRepo(), rBase.get, EvidenceCasRefName)
                expect(aBase.isOk and not aBase.get.alreadyPresent,
                  "the base record appends fresh")
                putEnv(JudgmentTestedTreeOidEnv, probeChangedTree)
                let plan = planJudgmentCasForSubjectWithTransport(jsS1aGolden,
                  makeTransport(eb))
                expect(plan.mode == jExecuted and plan.reason.contains("no record"),
                  "a changed closure → jExecuted (the original execution runs)")

    clearJudgmentEnv()

echo "G12 — the refined landing-venue reuse (REUSED-on-MG with root-EXECUTED provenance)"
block:
  # The redecision 2026-10-18 (docs/evidence/mg_reuse_policy_redecision_
  # 2026-10-18.md): the old force-execution block is a VENUE MARKER — the
  # merge_group plan consults the ledger like any other venue, an eligible
  # REUSED is admissible on the landing venue, and every jReused plan carries
  # the rootRecord provenance marker binding the re-fetched record.
  # SCOPE: the landing-venue REUSED pose is asserted on a NON-s1a subject
  # (proof_integrity) here; G13 pins the s1a subject's OWN landing-venue
  # pose. Since v1.0.5 the s1a subject is no longer excluded from the
  # landing venue (the 2026-10-18 redecision became the contract): it takes
  # the SAME 5-condition path as every other subject. Every assertion below
  # keeps its strength; the landing-venue reuse + rootRecord provenance
  # contract stays covered for both subject classes.
  expect(not judgmentLandingVenueMarker("", ""),
    "neither trigger → not a landing venue")
  expect(judgmentLandingVenueMarker("1", ""),
    "the explicit landing trigger marks the venue")
  expect(judgmentLandingVenueMarker("", JudgmentMergeGroupEvent),
    "the merge_group belt marks the venue (marker — never a consult block)")
  expect(not judgmentLandingVenueMarker("", "pull_request"),
    "the PR venue is never a landing venue")
  expect(not judgmentLandingVenueMarker("0", "workflow_call"),
    "an explicit 0 + workflow_call → no marker (the marker keys on merge_group only)")

  # the marker wire-shape + binding helpers (pure — the attest consumes the
  # shape check BEFORE any ledger IO)
  let goodMarker = %*{
    "evidenceKey": hex64(700),
    "payloadSha256": hex64(701),
    "executionEpoch": "e-marker"}
  expect(judgmentRootRecordMarkerShape(goodMarker) == "",
    "a well-formed rootRecord marker passes the shape check")
  expect(judgmentRootRecordMarkerShape(nil).contains("JSON object"),
    "a missing marker is refused by the shape check")
  var thinMarker = %*{"evidenceKey": hex64(700), "payloadSha256": hex64(701)}
  expect(judgmentRootRecordMarkerShape(thinMarker).contains("executionEpoch"),
    "a marker missing a field is refused by the shape check (fail-closed)")
  var badHex = %*{"evidenceKey": "not-hex", "payloadSha256": hex64(701),
    "executionEpoch": "e-marker"}
  expect(judgmentRootRecordMarkerShape(badHex).contains("64 lowercase hex"),
    "a non-hex marker identity field is refused by the shape check")

  # p2 wire-shape regression pin (v1.0.4) — pure, always runs: the closure
  # wire is a FIXED member JSON object — exactly these keys — and NO
  # tree-OID-typed member may ever re-enter it (§4.1 p2: the type is the
  # contract; v3's verifierIdentity member was the B^{tree} re-entry path).
  # v5 adds ONE member: pinIdentity (narrowing-only — the pinned external
  # dependency identities; §4.2.3 of the contract).
  block:
    let wireNode = parseJson(closureWire(validClosure(1)))
    var wireKeys: seq[string] = @[]
    for k in wireNode.keys: wireKeys.add(k)
    wireKeys.sort()
    expect(wireKeys == @["compilerPins", "completenessKeys", "envSnapshot",
        "executionConfig", "goldenFixtures", "pinIdentity", "recipe", "schema",
        "schemaVersion", "semanticSetDigest", "testSourceClosure", "toolchainBundle"],
      "closureWire is the FIXED member set + the schema separator " &
      "(no tree-OID-typed member — p2; v5 adds the narrowing-only pinIdentity)")
    expect(wireNode{"schema"}.getStr() == JudgmentKeyScheme,
      "the closure wire carries the current scheme constant (v5)")

  if not bundleAvailable:
    skip("G12 closure-derived cases", "toolchain bundle unmeasurable")
    clearJudgmentEnv()
  elif not treesAvailable:
    skip("G12 closure-derived cases",
      "no resolvable tested tree in this workspace (git object store unavailable)")
    clearJudgmentEnv()
  else:
    let testedOid = realTestedTree   ## component ⑤ derives S from this probe
    putEnv(JudgmentEnabledEnv, "1")
    putEnv(JudgmentTestedTreeOidEnv, testedOid)
    putEnv(subjectRecordPathEnv(jsProofIntegrity),
      getTempDir() / ("jcas-g12-pi-record-" & $getCurrentProcessId() & ".json"))
    let collected = collectJudgmentClosureFor(jsProofIntegrity, testedOid)
    if collected.isErr:
      inc failures
      echo "  FAIL: G12 closure collection: " & collected.error
      clearJudgmentEnv()
    else:
      let key = deriveJudgmentKey(collected.get)
      let epoch = captureReuseVerificationContext().currentEpoch
      let storedPayload = canonicalJsonString(proofIntegrityPayload(epoch))
      let decPath = getTempDir() / ("jcas-g12-decision-" & $getCurrentProcessId() & ".json")

      # (1) same-key + eligible on the merge_group venue → REUSED + marker
      #     (belt-only marking — no explicit env; the G11 §4-1 block is gone)
      var b = freshBackend()
      if not seedRecord(b, key, storedPayload):
        inc failures
        echo "  FAIL: G12(1) seed"
      else:
        putEnv("GITHUB_EVENT_NAME", "merge_group")
        var plan = planJudgmentCasForSubjectWithTransport(jsProofIntegrity, makeTransport(b))
        expect(plan.mode == jReused,
          "MG venue + eligible same-key record → jReused (no pre-consult block; got " & plan.reason & ")")
        expect(plan.landingVenue == JudgmentMergeGroupEvent,
          "the venue marker is on the plan")
        expect(plan.rootEvidenceKey == key and
          plan.rootPayloadSha256 == sha256Hex(storedPayload) and
          plan.rootExecutionEpoch == epoch,
          "the rootRecord marker binds the re-fetched record (key+payloadSha256+epoch)")
        # the explicit landing trigger alone behaves identically
        putEnv(JudgmentForceExecutionEnv, "1")
        plan = planJudgmentCasForSubjectWithTransport(jsProofIntegrity, makeTransport(b))
        expect(plan.mode == jReused and plan.landingVenue == JudgmentMergeGroupEvent,
          "the explicit landing trigger marks the venue without blocking (got " & plan.reason & ")")
        # the decision file seals landingVenue + rootRecord
        discard writeJudgmentDecisionFile(plan, decPath)
        let dec = parseJson(readFile(decPath))
        expect(dec{"landingVenue"}.getStr() == JudgmentMergeGroupEvent,
          "the MG decision file carries landingVenue")
        expect(dec{"rootRecord"}.kind == JObject and
          dec{"rootRecord"}{"evidenceKey"}.getStr() == key and
          dec{"rootRecord"}{"payloadSha256"}.getStr() == sha256Hex(storedPayload) and
          dec{"rootRecord"}{"executionEpoch"}.getStr() == epoch,
          "the MG decision file seals the full rootRecord provenance marker")
        # the marker binds a rebuilt record through the pure binding check
        let rebuilt = makeEvidenceRecord(key, storedPayload, newJObject(),
          "2026-10-08T00:00:00Z", judgmentProjectionDigest(storedPayload))
        expect(rebuilt.isOk and judgmentRootRecordMarkerMismatch(
          dec{"rootRecord"}, rebuilt.get, parseJson(storedPayload)) == "",
          "the sealed marker binds the record (pure binding check clean — J1: the re-adopted projection IS the stored bytes)")
        delEnv(JudgmentForceExecutionEnv)
        # the PR venue: REUSED preserved, NO landing marker, marker still binds
        putEnv("GITHUB_EVENT_NAME", "pull_request")
        let planPR = planJudgmentCasForSubjectWithTransport(jsProofIntegrity, makeTransport(b))
        expect(planPR.mode == jReused and planPR.landingVenue == "" and
          planPR.rootEvidenceKey == key,
          "the PR venue → jReused, no landing marker, rootRecord still bound")
        discard writeJudgmentDecisionFile(planPR, decPath)
        let decPR = parseJson(readFile(decPath))
        expect(decPR{"landingVenue"}.isNil and
          decPR{"rootRecord"}{"evidenceKey"}.getStr() == key,
          "the PR decision carries no landingVenue but keeps rootRecord (legacy venue shape preserved)")
        putEnv("GITHUB_EVENT_NAME", "merge_group")

        # (2) no record on the landing venue → EXECUTED (the test runs;
        #     the venue marker is independent of the outcome)
        var empty = planJudgmentCasForSubjectWithTransport(jsProofIntegrity,
          makeTransport(freshBackend()))
        expect(empty.mode == jExecuted and empty.reason.contains("no record"),
          "MG venue + empty ledger → jExecuted")
        expect(empty.landingVenue == JudgmentMergeGroupEvent,
          "the venue marker survives on a jExecuted plan")

        # (3) foreign generation (stale epoch) on the landing venue → EXECUTED
        var fb = freshBackend()
        if seedRecord(fb, key, canonicalJsonString(proofIntegrityPayload(hex64(601)))):
          let stale = planJudgmentCasForSubjectWithTransport(jsProofIntegrity, makeTransport(fb))
          expect(stale.mode == jExecuted and stale.reason.contains("executionEpoch"),
            "MG venue + stale-epoch record → jExecuted (fail-closed)")

        # (4) corrupt payload on the landing venue → EXECUTED
        var tamperedPayload = parseJson(storedPayload)
        tamperedPayload["checkpointVerdicts"]["admissionAdmit"] = %"varReject"
        var cb = freshBackend()
        if seedRecord(cb, key, canonicalJsonString(tamperedPayload)):
          let corrupt = planJudgmentCasForSubjectWithTransport(jsProofIntegrity, makeTransport(cb))
          expect(corrupt.mode == jExecuted and corrupt.reason.contains("judgment contract"),
            "MG venue + contract-violating payload → jExecuted (fail-closed)")

        # (5) a record under a different key is not this closure's record
        var kb = freshBackend()
        if seedRecord(kb, hex64(602), storedPayload):
          let foreign = planJudgmentCasForSubjectWithTransport(jsProofIntegrity, makeTransport(kb))
          expect(foreign.mode == jExecuted and foreign.reason.contains("no record"),
            "MG venue + foreign-key record → jExecuted (fail-closed)")

        # (6) reuse-of-reuse is structurally unrepresentable: a jReused plan's
        #     marker ALWAYS names a ledger record (checks above), and a marker
        #     naming a DIFFERENT root than the re-fetched record is refused —
        #     there is no expression of "REUSED whose root is a REUSED".
        var mismatchMarker = %*{
          "evidenceKey": hex64(603),
          "payloadSha256": sha256Hex(storedPayload),
          "executionEpoch": epoch}
        expect(judgmentRootRecordMarkerMismatch(mismatchMarker, rebuilt.get,
            parseJson(storedPayload)).contains("provenance mismatch"),
          "a marker naming a foreign root is refused by the binding check (reuse-of-reuse unrepresentable)")
        var staleEpochMarker = %*{
          "evidenceKey": key,
          "payloadSha256": sha256Hex(storedPayload),
          "executionEpoch": hex64(604)}
        expect(judgmentRootRecordMarkerMismatch(staleEpochMarker, rebuilt.get,
            parseJson(storedPayload)).contains("executionEpoch"),
          "a marker naming a foreign-generation epoch is refused by the binding check (fail-closed)")

      clearJudgmentEnv()

echo "G11 — the landing-venue marker (merge_group) + the SSOT subject projection"
block:
  # The SSOT subject projection — exact canonical bytes, exact SSOT order
  expect(allJudgmentSubjectsJson() ==
    "{\"subjects\":[\"s1a\",\"proof_integrity\",\"d2_golden\",\"d2_persist\"]}",
    "the SSOT projection is the exact 4-subject canonical JSON in SSOT order")

  if not bundleAvailable:
    skip("G11 closure-derived cases", "toolchain bundle unmeasurable")
  elif not treesAvailable:
    skip("G11 closure-derived cases",
      "no resolvable tested tree in this workspace (git object store unavailable)")
  else:
    let testedOid = realTestedTree   ## component ⑤ derives S from this probe
    putEnv(JudgmentEnabledEnv, "1")
    putEnv(JudgmentTestedTreeOidEnv, testedOid)
    putEnv(JudgmentRecordPathEnv, getTempDir() / ("jcas-g11-s1a-record-" & $getCurrentProcessId() & ".json"))
    putEnv(subjectRecordPathEnv(jsProofIntegrity), getTempDir() / ("jcas-g11-pi-record-" & $getCurrentProcessId() & ".json"))
    putEnv(subjectRecordPathEnv(jsD2Golden), getTempDir() / ("jcas-g11-d2g-record-" & $getCurrentProcessId() & ".json"))
    putEnv(subjectRecordPathEnv(jsD2Persist), getTempDir() / ("jcas-g11-d2p-record-" & $getCurrentProcessId() & ".json"))
    var keys: array[4, string]
    var keysOk = true
    for s in allJudgmentSubjects():
      let collected = collectJudgmentClosureFor(s, testedOid)
      if collected.isErr:
        inc failures
        echo "  FAIL: G11 closure collection [" & subjectName(s) & "]: " & collected.error
        keysOk = false
      else:
        keys[int(s)] = deriveJudgmentKey(collected.get)
    if keysOk:
      let epoch = captureReuseVerificationContext().currentEpoch

      proc subjectWire(s: JudgmentSubject; epoch: string): string =
        ## the subject's canonical reusable payload bytes
        if s == jsS1aGolden: payloadBytes(epoch)
        elif s == jsProofIntegrity: canonicalJsonString(proofIntegrityPayload(epoch))
        elif s == jsD2Golden: canonicalJsonString(d2GoldenPayload(epoch))
        else: canonicalJsonString(d2PersistPayload(epoch))

      # (i) the merge_group belt (marker only — redecision 2026-10-18) with a
      #     valid current-epoch reusable record → REUSED for the EXTENSION
      #     subjects, each plan carrying the landing marker + the rootRecord
      #     provenance. The s1a subject is the landing venue's TERMINAL
      #     acceptance judgment: its plan is ALWAYS EXECUTED there (the
      #     s1a-scoped landing force is GONE — v1.0.5 makes the s1a subject
      #     take the SAME landing-venue REUSED pose as every other subject
      #     (G13 pins the exact shape), so all four subjects are asserted
      #     alike here.
      putEnv("GITHUB_EVENT_NAME", "merge_group")
      for s in allJudgmentSubjects():
        var sb = freshBackend()
        if seedRecord(sb, keys[int(s)], subjectWire(s, epoch)):
          let plan = planJudgmentCasForSubjectWithTransport(s, makeTransport(sb))
          if s == jsS1aGolden:
            # v1.0.5: the s1a-scoped landing force is GONE — the s1a
            # judgment follows the SAME 5-condition path as every other
            # subject, landing venue included.
            expect(plan.mode == jReused and
              plan.landingVenue == JudgmentMergeGroupEvent and
              plan.rootEvidenceKey == keys[int(s)],
              "[s1a] MG venue (belt-only) + valid record → jReused with the landing marker + the rootRecord provenance (the s1a landing force is gone; got " & plan.reason & ")")
          else:
            expect(plan.mode == jReused and
              plan.landingVenue == JudgmentMergeGroupEvent,
              "[" & subjectName(s) & "] MG venue (belt-only) + valid record → jReused with the landing marker (got " & plan.reason & ")")
            expect(plan.rootEvidenceKey == keys[int(s)],
              "[" & subjectName(s) & "] the rootRecord marker binds the re-fetched record")

      # (ii) PR venue → REUSED preserved for EVERY subject, no landing marker
      #      (the reuse pose is byte-identical to the pre-redecision PR path)
      delEnv("GITHUB_EVENT_NAME")
      for s in allJudgmentSubjects():
        var sb = freshBackend()
        if seedRecord(sb, keys[int(s)], subjectWire(s, epoch)):
          let plan = planJudgmentCasForSubjectWithTransport(s, makeTransport(sb))
          expect(plan.mode == jReused and plan.landingVenue == "",
            "[" & subjectName(s) & "] PR venue → jReused preserved, no landing marker (got " & plan.reason & ")")

      # (iii)+(iv) the marker env does NOT touch the attest leg's fail-closed
      #            legs: under the marker env the EXECUTED evidence contract
      #            and the REUSED token/marker contracts behave exactly as
      #            G7's (parity — a venue env never loosens a fail-closed leg)
      let tmpDir = getTempDir() / "jcas-g11-" & $getCurrentProcessId()
      createDir(tmpDir)
      let decisionPath = tmpDir / "decision.json"
      let recordPath = tmpDir / "judgment-record.json"
      let evidencePath = tmpDir / "s1a-evidence.json"
      putEnv(JudgmentForceExecutionEnv, "1")
      putEnv("GITHUB_EVENT_NAME", "merge_group")
      putEnv(JudgmentDecisionPathEnv, decisionPath)
      putEnv(JudgmentRecordPathEnv, recordPath)
      let key = keys[int(jsS1aGolden)]

      # (iii) EXECUTED decision + missing evidence file → refused, naming the
      #       subject's evidence-path env; no record written (the writer runs
      #       only after the evidence parses and the record builds)
      writeFile(decisionPath, canonicalJsonString(%*{
        "basis": "EXECUTED", "evidenceKey": key, "reason": "test"}))
      delEnv(subjectEvidencePathEnv(jsS1aGolden))
      let miss = runJudgmentAttestBranch()
      expectErr("marker-env attest: EXECUTED without evidence is refused, naming the evidence-path env",
        (if miss.isErr: Result[string, string](ok: false, err: miss.error)
         else: Result[string, string](ok: true, value: "armed")),
        subjectEvidencePathEnv(jsS1aGolden))
      expect(not fileExists(recordPath),
        "a failed attest publishes no record file (writer runs only after success)")

      # (iv-a) EXECUTED + evidence present → armed EXECUTED basis (parity with
      #        G7(c): the marker env neither minted nor loosened anything)
      putEnv(subjectEvidencePathEnv(jsS1aGolden), evidencePath)
      writeFile(evidencePath, payloadBytes(epoch))
      let executed = runJudgmentAttestBranch()
      expect(executed.isOk and executed.get.armed and
        executed.get.basis == JudgmentWitnessBasisExecuted,
        "marker-env attest: EXECUTED + evidence → armed EXECUTED basis")

      # (iv-b) the REUSED attest leg is NOT loosened: a marker-less REUSED
      #        decision is refused at the shape check BEFORE any ledger IO
      #        (G7(g) parity — the venue env never manufactures provenance)
      writeFile(decisionPath, canonicalJsonString(%*{
        "basis": "REUSED", "evidenceKey": key, "reason": "test"}))
      delEnv("GITHUB_TOKEN")
      let noMarker = runJudgmentAttestBranch()
      expectErr("marker-env attest: REUSED without the rootRecord marker is still refused (shape before IO)",
        (if noMarker.isErr: Result[string, string](ok: false, err: noMarker.error)
         else: Result[string, string](ok: true, value: "armed")),
        "rootRecord")
      # (iv-c) a well-marked REUSED without a token is still refused at the
      #        token check (G7(d) parity)
      writeFile(decisionPath, canonicalJsonString(%*{
        "basis": "REUSED", "evidenceKey": key, "reason": "test",
        "rootRecord": {"evidenceKey": key, "payloadSha256": hex64(501),
                        "executionEpoch": epoch}}))
      let noToken = runJudgmentAttestBranch()
      expectErr("marker-env attest: well-marked REUSED without GITHUB_TOKEN is still refused (leg unchanged)",
        (if noToken.isErr: Result[string, string](ok: false, err: noToken.error)
         else: Result[string, string](ok: true, value: "armed")),
        "GITHUB_TOKEN")

      removeDir(tmpDir)
    clearJudgmentEnv()

# ---------------------------------------------------------------------------
# G13 — the v5 evidence identity: the s1a landing-venue REUSED (the force is
# gone) + the scheme cut
# ---------------------------------------------------------------------------
# v1.0.5 (contract §3/§5): the s1a judgment is reusable under the SAME 5
# conditions as every other subject — the 2026-10-18 redecision became the
# contract and the s1a-scoped landing force was REMOVED from the plan. The
# landing venue (merge_group) is no longer an exception: an eligible s1a
# REUSED is admissible there, carrying the rootRecord provenance marker, and
# the workflow's s1a REUSED rejection + EXECUTED+PASS requirement were removed
# in the same generation.

echo "G13 — the v5 evidence identity (the s1a landing-venue REUSED + the scheme cut)"
block:
  clearJudgmentEnv()

  # (0) the subject vocabulary is closed and non-empty: an empty subject is
  #     NOT a subject and is never resolved to s1a.
  expect(parseJudgmentSubject("").isErr,
    "an empty subject is not a resolvable judgment subject (never folded into s1a)")
  let s1aSubjectParse = parseJudgmentSubject("s1a")
  expect(s1aSubjectParse.isOk and s1aSubjectParse.get == jsS1aGolden,
    "the s1a subject name resolves to the s1a subject")
  var emptyTags = 0
  for s in allJudgmentSubjects():
    if subjectName(s).len == 0: inc emptyTags
  expect(emptyTags == 0,
    "no judgment subject maps to an empty subject tag (the plan's subject tag is never empty)")

  # (0a) the v5 SCHEME CUT — the wire's "schema" member separates the eras.
  #      A v4-era record can never re-verify as a v5 record: the keys differ
  #      for the SAME closure, so the ledger's 64-hex membership lookup misses
  #      every v4 record (the natural orphaning of the v2→v3→v4 precedent).
  expect(JudgmentKeyScheme == "axiom.judgment.cas.key.v5",
    "the judgment key scheme is the v5 era (the wire's schema member)")
  block:
    let v5Closure = validClosure(1)
    let v5Wire = parseJson(closureWire(v5Closure))
    expect(v5Wire{"schema"}.getStr() == "axiom.judgment.cas.key.v5",
      "the closure wire's schema member carries the v5 era")
    # the SAME closure serialized under the v4 scheme — the v4 record's key
    var v4Closure = v5Closure
    let v4Wire = canonicalJsonString(%*{
      "schema": "axiom.judgment.cas.key.v4",
      "testSourceClosure": v5Closure.testSourceClosure,
      "goldenFixtures": v5Closure.goldenFixtures,
      "toolchainBundle": v5Closure.toolchainBundle,
      "semanticSetDigest": v5Closure.semanticSetDigest,
      "envSnapshot": v5Closure.envSnapshot,
      "recipe": v5Closure.recipe,
      "compilerPins": v5Closure.compilerPins,
      "executionConfig": v5Closure.executionConfig,
      "completenessKeys": v5Closure.completenessKeys,
      "schemaVersion": v5Closure.schemaVersion})
    expect(sha256Hex(v4Wire) != deriveJudgmentKey(v5Closure),
      "a v4-era wire and a v5-era wire of the SAME closure have different keys " &
      "(the v4 records are orphaned by the scheme cut alone)")
    # and the pin identity is part of the v5 wire (a narrowing-only member):
    # a changed pin identity moves the key (it can only turn a REUSED into an
    # EXECUTED — it never resurrects an older record).
    var pinned = v5Closure
    pinned.pinIdentity = "checksums@0.2.2#rev#sha1"
    var repinned = v5Closure
    repinned.pinIdentity = "checksums@0.2.3#rev#sha1"
    expect(deriveJudgmentKey(pinned) != deriveJudgmentKey(repinned),
      "the narrowing-only pin identity member moves the key (a pin change " &
      "invalidates the reuse)")
    expect(deriveJudgmentKey(v5Closure) != deriveJudgmentKey(pinned),
      "an unset pin identity and a set one are different closures")

  # (0b) the EMPTY subject (the legacy wire shape) keeps the legacy decision
  #      shape: NO "subject" field is written — the empty subject is never
  #      reclassified as "s1a" on the wire, and it carries no s1a force reason.
  let emptySubjectPath = getTempDir() / ("jcas-g13-empty-subject-" & $getCurrentProcessId() & ".json")
  let emptySubjectPlan = JudgmentPlan(mode: jExecuted,
    reason: "legacy wire (no subject field) — the empty subject is not a subject",
    evidenceKey: hex64(900), recordPath: "/dev/null",
    repo: "a/b", refName: "refs/heads/evidence", subject: "")
  let emptySubjectWritten = writeJudgmentDecisionFile(emptySubjectPlan, emptySubjectPath)
  expect(emptySubjectWritten.isOk, "the empty-subject plan writes its decision file")
  if emptySubjectWritten.isOk:
    let emptySubjectDecision = parseJson(readFile(emptySubjectPath))
    expect(emptySubjectDecision{"subject"}.isNil,
      "the empty subject is written as NO subject field (never reclassified as s1a)")
    expect(not emptySubjectDecision{"reason"}.getStr().contains("terminal acceptance judgment"),
      "the empty-subject decision carries no s1a force reason (the force is gone)")
  if fileExists(emptySubjectPath):
    removeFile(emptySubjectPath)

  if not bundleAvailable:
    skip("G13 closure-derived cases", "toolchain bundle unmeasurable")
    clearJudgmentEnv()
  elif not treesAvailable:
    skip("G13 closure-derived cases",
      "no resolvable tested tree in this workspace (git object store unavailable)")
    clearJudgmentEnv()
  else:
    let testedOid = realTestedTree   ## component ⑤ derives S from this probe
    let epoch = captureReuseVerificationContext().currentEpoch
    let s1aCollected = collectJudgmentClosureFor(jsS1aGolden, testedOid)
    let piCollected = collectJudgmentClosureFor(jsProofIntegrity, testedOid)
    if s1aCollected.isErr or piCollected.isErr:
      inc failures
      echo "  FAIL: G13 closure collection: " &
        (if s1aCollected.isErr: s1aCollected.error else: piCollected.error)
      clearJudgmentEnv()
    else:
      let s1aKey = deriveJudgmentKey(s1aCollected.get)
      let piKey = deriveJudgmentKey(piCollected.get)
      let s1aPayload = payloadBytes(epoch)
      let piPayload = canonicalJsonString(proofIntegrityPayload(epoch))
      let g13Dir = getTempDir() / "jcas-g13-" & $getCurrentProcessId()
      createDir(g13Dir)
      putEnv(JudgmentEnabledEnv, "1")
      putEnv(JudgmentTestedTreeOidEnv, testedOid)
      putEnv(JudgmentRecordPathEnv, g13Dir / "s1a-record.json")
      putEnv(subjectRecordPathEnv(jsProofIntegrity), g13Dir / "pi-record.json")
      putEnv(JudgmentDecisionPathEnv, g13Dir / "s1a-decision.json")
      putEnv(subjectDecisionPathEnv(jsProofIntegrity), g13Dir / "pi-decision.json")

      # (1) merge_group + s1a + an existing VALID record → REUSED (v1.0.5:
      #     the s1a-scoped landing force is GONE — the s1a judgment takes the
      #     same 5-condition path as every other subject, landing venue
      #     included, and carries the rootRecord provenance marker)
      putEnv("GITHUB_EVENT_NAME", "merge_group")
      var b = freshBackend()
      if not seedRecord(b, s1aKey, s1aPayload):
        inc failures
        echo "  FAIL: G13(1) seed"
      else:
        let plan = planJudgmentCasForSubjectWithTransport(jsS1aGolden, makeTransport(b))
        expect(plan.mode == jReused,
          "MG venue + s1a + an existing valid record → jReused (the 5-condition " &
          "path applies to s1a on the landing venue too; got " & plan.reason & ")")
        expect(not plan.reason.contains("terminal acceptance judgment"),
          "the s1a landing plan carries no force reason (the force is gone)")
        expect(plan.landingVenue == JudgmentMergeGroupEvent,
          "the landing-venue marker is on the reused plan")
        expect(plan.evidenceKey == s1aKey,
          "the reused plan still carries the freshly derived key (the decision file's key stays re-derivable)")
        expect(plan.rootEvidenceKey == s1aKey and plan.rootPayloadSha256.len == 64 and
          plan.rootExecutionEpoch == epoch,
          "the s1a landing REUSED plan carries the rootRecord provenance marker")
        # the decision file the attest consumes: the REUSED basis + the legacy
        # no-subject wire shape + the landing-venue marker + the rootRecord
        expect(writeJudgmentDecisionFile(plan, g13Dir / "s1a-decision.json").isOk,
          "the reused s1a plan's decision file writes")
        if fileExists(g13Dir / "s1a-decision.json"):
          let dec = parseJson(readFile(g13Dir / "s1a-decision.json"))
          expect(dec{"basis"}.getStr() == JudgmentWitnessBasisReused,
            "the landing-venue s1a decision is a REUSED basis (v1.0.5)")
          expect(dec{"landingVenue"}.getStr() == JudgmentMergeGroupEvent,
            "the landing-venue s1a decision carries the venue marker")
          expect(dec{"subject"}.isNil,
            "the s1a decision keeps the legacy no-subject wire shape")
          expect(dec{"rootRecord"}{"evidenceKey"}.getStr() == s1aKey,
            "the landing-venue s1a decision seals the rootRecord marker")
          expect(not dec{"reason"}.getStr().contains("terminal acceptance judgment"),
            "the landing-venue s1a decision carries no terminal-judgment reason")

      # (2) merge_group + s1a + NO record → EXECUTED (the consult finds no
      #     record — the fresh judgment runs; the venue is irrelevant)
      let empty = planJudgmentCasForSubjectWithTransport(jsS1aGolden,
        makeTransport(freshBackend()))
      expect(empty.mode == jExecuted,
        "MG venue + s1a + an empty ledger → jExecuted (the judgment runs)")
      expect(empty.reason.contains("no record"),
        "the empty-ledger landing plan names the missing record (got " & empty.reason & ")")
      expect(empty.evidenceKey == s1aKey,
        "the empty-ledger landing plan still carries the freshly derived key")

      # (3) merge_group + a NON-s1a subject + an existing valid record → REUSED
      #     (unchanged — s1a and the probe subjects now share one machinery)
      var pb = freshBackend()
      if not seedRecord(pb, piKey, piPayload):
        inc failures
        echo "  FAIL: G13(3) seed"
      else:
        let plan = planJudgmentCasForSubjectWithTransport(jsProofIntegrity, makeTransport(pb))
        expect(plan.mode == jReused,
          "MG venue + proof_integrity + an existing valid record → jReused (got " & plan.reason & ")")
        expect(not plan.reason.contains("terminal acceptance judgment"),
          "the non-s1a landing plan carries no s1a force reason")
        expect(plan.landingVenue == JudgmentMergeGroupEvent and
          plan.rootEvidenceKey == piKey,
          "the non-s1a landing plan keeps the venue marker + the rootRecord provenance")

      # (4) the EMPTY subject (the legacy wire) is not reclassified as s1a.
      #     The plan's own subject tag is subjectName(s) — total and never
      #     empty — so the empty subject exists ONLY on the decision-file
      #     wire (the legacy no-subject-field shape). The attest's subject
      #     resolution keeps the EXISTING path there: the s1a branch accepts
      #     the subject-less legacy decision (its own legacy wire, no s1a
      #     force reason), while an extension subject REFUSES it — the empty
      #     subject is never inherited as another subject's. The landing-venue
      #     env changes neither leg (a venue env never reclassifies).
      let legacyDecisionPath = g13Dir / "legacy-decision.json"
      writeFile(legacyDecisionPath, canonicalJsonString(%*{
        "basis": JudgmentWitnessBasisExecuted, "evidenceKey": s1aKey,
        "reason": "legacy wire (no subject field)"}))
      putEnv(JudgmentDecisionPathEnv, legacyDecisionPath)
      putEnv(subjectEvidencePathEnv(jsS1aGolden), g13Dir / "s1a-evidence.json")
      writeFile(g13Dir / "s1a-evidence.json", s1aPayload)
      let legacyS1a = runJudgmentAttestBranch()
      expect(legacyS1a.isOk and legacyS1a.get.armed and
        legacyS1a.get.basis == JudgmentWitnessBasisExecuted,
        "the empty-subject legacy wire takes the existing s1a attest path (armed, EXECUTED)")
      if legacyS1a.isOk:
        expect(not legacyS1a.get.reason.contains("terminal acceptance judgment"),
          "the empty-subject legacy wire carries no s1a force reason")
        expect(legacyS1a.get.subject == subjectName(jsS1aGolden),
          "the legacy wire stays the s1a subject's own wire (no reclassification)")
      putEnv(subjectDecisionPathEnv(jsProofIntegrity), legacyDecisionPath)
      let legacyPi = runJudgmentAttestBranchForSubject(jsProofIntegrity)
      expectErr("the empty subject is not inherited by another subject (the extension branch refuses the subject-less decision)",
        (if legacyPi.isErr: Result[string, string](ok: false, err: legacyPi.error)
         else: Result[string, string](ok: true, value: "armed")),
        "decision file subject")

      # (5) the PR venue (no force env) + s1a + an existing valid record →
      #     REUSED: the preflight reuse pose is preserved (the force is
      #     landing-only)
      delEnv(JudgmentForceExecutionEnv)
      putEnv("GITHUB_EVENT_NAME", "pull_request")
      var rb = freshBackend()
      if not seedRecord(rb, s1aKey, s1aPayload):
        inc failures
        echo "  FAIL: G13(5) seed"
      else:
        let plan = planJudgmentCasForSubjectWithTransport(jsS1aGolden, makeTransport(rb))
        expect(plan.mode == jReused,
          "PR venue + s1a + an existing valid record → jReused (the preflight reuse pose is preserved; got " & plan.reason & ")")
        expect(plan.landingVenue == "",
          "the PR venue carries no landing marker")
        expect(plan.rootEvidenceKey == s1aKey,
          "the PR-venue reuse keeps the rootRecord provenance")

      clearJudgmentEnv()
      removeDir(g13Dir)

# ---------------------------------------------------------------------------
# G14 — the tested-tree closure (v5): the multi-hop walk, the R-NT
# classification, and the changed-closure invalidation
# ---------------------------------------------------------------------------
# The v5 ① is derived from the TESTED TREE's git objects, not the working
# directory: the walk is multi-hop (the v4 one-hop walk never resolved a
# package-style import — 19 files, depth ≥ 2 = 0) and every import is
# classified under the R-NT rule. The fixture is a THROWAWAY git repo (the
# test_judgment_set_derivation.nim pattern) so the expected closure set is
# exact and the (d) hit is provoked on purpose.

echo "G14 — the tested-tree closure (the multi-hop walk + the R-NT rule)"
block:
  let fixtureDir = getTempDir() / ("jcas-g14-fixture-" & $getCurrentProcessId())
  var fixtureSourceDigest = ""   ## the fixture's ① digest (the (5) baseline)

  proc fixtureRepo(files: openArray[(string, string)]): string =
    ## A throwaway git repo holding the given files; returns its HEAD tree
    ## OID ("" on any failure). `git` is spawned WITHOUT a shell (Q-012).
    let dir = fixtureDir
    if dirExists(dir):
      removeDir(dir)
    createDir(dir)
    for (rel, content) in files:
      let p = dir / rel
      createDir(p.parentDir)
      writeFile(p, content)
    if runGitOrErr(dir, "-c init.defaultBranch=main init -q").isErr:
      return ""
    if runGitOrErr(dir, "add -A -f").isErr:
      return ""
    if runGitOrErr(dir, "-c user.name=g14 -c user.email=g14@axiom.dev" &
        " -c commit.gpgsign=false -c core.hooksPath=/dev/null commit -q -m g14").isErr:
      return ""
    let t = runGitOrErr(dir, "rev-parse HEAD^{tree}")
    if t.isErr:
      return ""
    t.get.strip()

  const FixtureLock = """{
  "version": 2,
  "packages": {
    "checksums": {
      "version": "0.2.2",
      "vcsRevision": "0845c735a9746188b2257ee2cff672eb6ec26e8a",
      "checksums": { "sha1": "6357ab195ec23e0e0a54d4d8b5e0212456bf899a" }
    }
  },
  "tasks": {}
}
"""

  let fixtureTree = fixtureRepo([
    ("src/pkg/root.nim", "import pkg/child\nimport std/os\n"),
    ("src/pkg/child.nim", "import pkg/grandchild\n"),
    ("src/pkg/grandchild.nim", "import checksums/sha2\n"),
    ("src/pkg/unresolved.nim", "import mystery_package/thing\n"),
    ("nimble.lock", FixtureLock)])
  if fixtureTree.len != 40:
    skip("G14 fixture cases", "the throwaway fixture repo could not be created (git unavailable)")
  else:
    # (1) the MULTI-HOP resolution — the expected closure set is exact:
    #     root → child → grandchild (depth 2 hops below the entry), the
    #     stdlib import contributes NO member, and the pinned external
    #     module contributes the lock entry identity (NOT a tree member).
    let derived = deriveTestedTreeClosure(fixtureDir, fixtureTree,
      @["src/pkg/root.nim"], @[])
    if derived.isErr:
      inc failures
      echo "  FAIL: G14(1) derivation: " & derived.error
    else:
      var paths: seq[string] = @[]
      for m in derived.get.members:
        paths.add(m.path)
      paths.sort()
      expect(paths == @["src/pkg/child.nim", "src/pkg/grandchild.nim",
          "src/pkg/root.nim"],
        "the closure is the MULTI-HOP set (root → child → grandchild) — " &
        $paths)
      expect(derived.get.nonReusable.len == 0,
        "the fixture closure is reusable (no (c)/(d) hit)")
      expect(derived.get.pinIdentity ==
          "checksums@0.2.2#0845c735a9746188b2257ee2cff672eb6ec26e8a" &
          "#6357ab195ec23e0e0a54d4d8b5e0212456bf899a",
        "the pinned external module's lock entry identity is the closure's pin record")
      var sawStdlib = false
      var sawPinned = false
      for d in derived.get.dependencies:
        if d.klass == dcStdlib: sawStdlib = true
        if d.klass == dcPinnedExternal and d.rawImport == "checksums/sha2":
          sawPinned = true
      expect(sawStdlib,
        "the stdlib import is classified as the stdlib class (bound by ⑧, not a closure input)")
      expect(sawPinned,
        "the nimble-package import is classified as (b) pinned external")
      # the fixture's ① digest is a pure function of the tree — the SAME
      # tree yields the SAME digest, and the tree OID is not in the digest.
      let derived2 = deriveTestedTreeClosure(fixtureDir, fixtureTree,
        @["src/pkg/root.nim"], @[])
      expect(derived2.isOk and derived2.get.sourceDigest == derived.get.sourceDigest,
        "the closure digest is deterministic over the same tree")
      expect(derived.get.sourceDigest.len == 64,
        "the closure digest is a 64-hex digest")
      fixtureSourceDigest = derived.get.sourceDigest

    # (2) a (d)-classified import — unresolvable AND unpinned — makes the
    #     closure NOT reusable: the caller falls back to EXECUTED.
    let unresolved = deriveTestedTreeClosure(fixtureDir, fixtureTree,
      @["src/pkg/unresolved.nim"], @[])
    if unresolved.isErr:
      inc failures
      echo "  FAIL: G14(2) derivation: " & unresolved.error
    else:
      var sawD = false
      for n in unresolved.get.nonReusable:
        if n.startsWith("d|mystery_package/thing|"): sawD = true
      expect(sawD,
        "an unresolvable, unpinned import is a (d) hit — the closure is not reusable")
      expect(unresolved.get.notes.len > 0,
        "the (d) hit is RECORDED (never a silent skip)")

    # (3) the fixture repo is disposable — the (d) hit above already proved
    #     the fail-closed path (the judgment's collector turns a (d) hit into
    #     a jExecuted plan).
    removeDir(fixtureDir)

  # (4) the REAL closure — the R-NT classification over the workspace's
  #     tested tree: the multi-hop depth (the v4 one-hop walk had depth
  #     ≥ 2 = 0), the pinned external entries, and the build-generated hit.
  if not treesAvailable:
    skip("G14 real-closure cases",
      "no resolvable tested tree in this workspace (git object store unavailable)")
  else:
    var realFixturePaths: seq[string] = @[]
    for f in GoldenFixturePaths:
      realFixturePaths.add(f)
    let real = deriveTestedTreeClosure(".", realTestedTree,
      @["tests/unit/test_s1a_lean_golden.nim"], realFixturePaths)
    if real.isErr:
      inc failures
      echo "  FAIL: G14(4) derivation: " & real.error
    else:
      var memberPaths: seq[string] = @[]
      for m in real.get.members:
        memberPaths.add(m.path)
      expect(memberPaths.len > 100,
        "the s1a closure is the MULTI-HOP set (" & $memberPaths.len &
        " members — the v4 one-hop walk measured 19)")
      expect("src/core/crypto/hash_kernel.nim" in memberPaths,
        "a depth ≥ 3 member is present (the s1a test → judgment_cas → " &
        "semantic_set_derivation → hash_kernel chain — the v4 walk could not see it)")
      expect("src/verification/judgment_cas.nim" in memberPaths,
        "the closure's own module is a member")
      expect(real.get.nonReusable.len == 0,
        "the real closure has no (c)/(d) hit (the build-generated module is admissible)")
      var sawBuildGenerated = false
      var sawCompilerPin = false
      for d in real.get.dependencies:
        if d.klass == dcBuildGenerated and d.rawImport == "generated/build_env":
          sawBuildGenerated = true
        if d.klass == dcPinnedExternal and d.rawImport.startsWith("compiler/"):
          sawCompilerPin = true
      expect(sawBuildGenerated,
        "the build-generated module is classified (c) — the committed template binds it")
      expect(sawCompilerPin,
        "the compiler-shipped modules are classified (b) — the 'nim' lock entry pins them")
      expect(real.get.pinIdentity.contains("checksums@") and
        real.get.pinIdentity.contains("nim@"),
        "the pin identity records the lock entries the closure rests on")

      # (5) a CHANGED closure invalidates the reuse: the ① member is a
      #     closure input, so a byte change in a closure member moves the
      #     key — the stored record can no longer be found (a REUSED is
      #     never granted for a changed closure).
      let mutated = fixtureRepo([
        ("src/pkg/root.nim", "import pkg/child\nimport std/os\n# changed\n"),
        ("src/pkg/child.nim", "import pkg/grandchild\n"),
        ("src/pkg/grandchild.nim", "import checksums/sha2\n"),
        ("src/pkg/unresolved.nim", "import mystery_package/thing\n"),
        ("nimble.lock", FixtureLock)])
      if mutated.len == 40:
        let mutatedDerived = deriveTestedTreeClosure(fixtureDir, mutated,
          @["src/pkg/root.nim"], @[])
        expect(mutatedDerived.isOk and
          mutatedDerived.get.sourceDigest != fixtureSourceDigest,
          "a changed closure member moves the ① digest (the changed closure " &
          "can never be reused)")

# leave the process env as we found it
clearJudgmentEnv()
delEnv("GITHUB_TOKEN")

echo ""
if failures == 0:
  echo "=== All judgment CAS tests PASSED ==="
else:
  echo "=== " & $failures & " judgment CAS test assertion(s) FAILED ==="
  quit(1)
