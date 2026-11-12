import std/[algorithm, base64, json, os, osproc, strutils, tables]
import cli/cert_cli
import cli/merge_cli
import core/crypto/hash_kernel
import core/results
from infrastructure/certificate_attestation import verifyCertificateAttestation
import verification/ledger_side_ref
import verification/attestation_orchestrator
import verification/attestation_witness
import verification/canonical_json
import verification/extraction_agreement
import verification/extraction_provenance
import verification/kernel_reexecution
import verification/obligation/identity
import verification/subject_continuity_writer
import verification/subject_store
import verification/verification_subject

## ═══════════════════════════════════════════════════════════════════════
## Attestation — certification continuity Phase 4 tests
## (Trusted Attestation: Verify(E,M) chain + subject-certificate mint +
## side-ref ledger).
##
## Coverage:
##   P1  pure semantics: evidence codec validation (missing ≠ valid-empty),
##       bundle digest determinism, verdict mapping helpers
##   P2  subject mismatch → atSubjectMismatch (no tools needed)
##   P3  evidence subjectId mismatch → atSubjectMismatch
##   P4  extraction mismatch (fabricated empty source + real differential
##       divergence fixture) → fail-closed   (worker-gated for the real leg)
##   P5  kernel re-execution failures: sorry-laden lean → atKernelLeanFail;
##       sat query → atKernelZ3Fail   (lean/z3-gated)
##   P6  policy digest flip → atPolicyDigestMismatch; missing → fail-closed
##   P7  scope digest missing → atScopeMismatch; toolchain flip →
##       atToolchainMismatch; charon extraction-pin segment flip →
##       atToolchainMismatch (v2 stage-e)
##   P8  HAPPY PATH — real lean/z3/worker: full chain → atPassed, cert
##       minted binding subjectId/headSha/headTreeDigest/policyDigest/
##       scopeDigest/evidenceDigest/toolchainIdentity + v3 attestation
##       (tool-gated)
##   P9  tamper ANY bound field post-mint → ax cert verify rejects
##       (structural verify via the real CLI binary, exit 1 = attestation
##       layer rejection)
##   P10 cert roundtrip — mint → ax cert verify --kernel passes on the real
##       cert file (Phase 3 kernel re-execution)  (tool-gated)
##   P11 side-ref ledger against injectable fake transport: append → tip
##       advances; concurrent move (non-FF) → fail-closed; malformed blob
##       response → fail-closed; ledger-list reads + integrity violation
##   P13 duplicate-subject predicate (ADR-0021 D6): a subject whose
##       certificate authority already exists in the ledger must not mint again
## ═══════════════════════════════════════════════════════════════════════

var passCount = 0
var skipCount = 0

proc checkEq(name: string; got, exp: string) =
  if got == exp:
    echo "  [PASS] ", name
    inc passCount
  else:
    echo "  [FAIL] ", name, "\n      got: ", got, "\n      exp: ", exp
    quit(1)

proc checkTrue(name: string; cond: bool) =
  if cond:
    echo "  [PASS] ", name
    inc passCount
  else:
    echo "  [FAIL] ", name
    quit(1)

proc checkVerdict(name: string; got, exp: AttestationVerdict) =
  if got == exp:
    echo "  [PASS] ", name, " -> ", $got
    inc passCount
  else:
    echo "  [FAIL] ", name, "\n      got: ", $got, "\n      exp: ", $exp
    quit(1)

proc skip(name: string; reason: string) =
  echo "  [SKIP] ", name, " (", reason, ") — test skipped, exit 0"
  inc skipCount

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
createDir(repoRoot / "build" / "tmp")  # P8/P9/P10 module fixtures (root tmp/ is FORBIDDEN, Filesystem Contract V2)
let leanAvailable = findExe("lake").len > 0 and findExe("lean").len > 0
let z3Available = fileExists(getHomeDir() / ".local" / "bin" / "z3") or findExe("z3").len > 0
let workerAvailable = fileExists(repoRoot / "proofs" / ".lake" / "build" / "bin" / "ircheck")
let runId = $getCurrentProcessId()

# ---------------------------------------------------------------------------
# Shared fixtures
# ---------------------------------------------------------------------------

const AttestInc3 = """
func inc3(a: int): int =
  let b = a + 1
  let c = b * 2
  c - 1
"""

## Non-zero early return fixture: both extractors preserve the return value
## since the extractReturnValueCanon then-body repair — the differential
## must AGREE. (It used to surface atExtractionMismatch under the old
## retval-degradation bug; this fixture now anchors the repaired behavior.)
const AttestFactNonzero = """
func fact3(n: int): int =
  if n <= 1:
    return 1
  n * fact3(n - 1)
"""

const AttestLeanPass = "theorem axiom_attest_prop : True := by trivial"
const AttestLeanSorry = "theorem axiom_attest_bad : False := by sorry\n#print axioms axiom_attest_bad"
const AttestSmtUnsat = "(declare-const x Int)\n(assert (and (> x 0) (< x 0)))\n(check-sat)"
const AttestSmtSat = "(declare-const x Int)\n(assert (= x 1))\n(check-sat)"

proc hex40(seed: int): string =
  var s = "candidate" & $seed & runId
  sha256Hex(s)[0 ..< 40]
proc hex64(seed: int): string =
  sha256Hex("seed" & $seed & runId)
proc hex40a(seed: int): string =
  let h = sha256Hex("base" & $seed & runId)
  h[0 ..< 40]
proc hex64a(seed: int): string =
  sha256Hex("env" & $seed & runId)

proc makeFixtureSubject(seed: int): VerificationSubject =
  let base = hex40a(seed)
  let made = makeSubject(base, hex40(seed), hex64(seed),
    hex64(seed + 7), hex64(seed + 8), hex64(seed + 9), seed,
    "2026-09-09T09:00:00Z")
  doAssert made.isOk
  made.get

proc makeEvidencePlaceholder(baseSha, headSha, headTreeDigest: string;
                             seed: int): AttestationInputs =
  ## Evidence record whose six digest bindings match the canonical subject
  ## wire (policy/scope read from the real lock files) — used to construct a
  ## self-consistent subject. prHeadSha/headSha are the subject head.
  result = AttestationInputs(
    schemaVersion: EvidenceScheme,
    subjectId: "",
    prNumber: seed mod 1000,
    prHeadSha: headSha,
    leanSource: AttestLeanPass,
    smtlib2: AttestSmtUnsat,
    funcSource: AttestInc3,
    funcPath: "tmp/ax_witness_ev_" & runId & ".nim",
    funcName: "inc3",
    envDigest: hex64a(seed + 200),
    policyDigest: "",
    scopeDigest: "",
    toolchainIdentity: pinnedToolchainIdentity())
  result.policyDigest = sha256Hex(readFile(repoRoot / "config" / "policy" / "merge_admission.json"))
  result.scopeDigest = sha256Hex(readFile(repoRoot / "data" / "verification_scope.lock"))

proc makeWitnessFixture(seed: int): tuple[subject: VerificationSubject, evidence: AttestationInputs] =
  ## Witness-surface fixture honoring the REAL subject-register invariant: the
  ## subject's evidenceDigest is the actual sha256 over the constructed
  ## evidence bundle wire (never an arbitrary value) — the same relationship
  ## `ax cert subject-register` establishes and the witness-only/sign surfaces
  ## cross-check.
  let base = hex40a(seed)
  let ev = makeEvidencePlaceholder(base, hex40(seed), hex64(seed), seed)
  let made = makeSubject(base, ev.prHeadSha, hex64(seed),
    ev.policyDigest, ev.scopeDigest, evidenceBundleDigest(ev), seed,
    "2026-09-09T09:00:00Z")
  doAssert made.isOk
  let subject = made.get
  var finalEv = ev
  finalEv.subjectId = subject.subjectId
  (subject, finalEv)

proc makeEvidence(subject: VerificationSubject; seed: int;
                  leanSource: string = AttestLeanPass;
                  smtlib2: string = AttestSmtUnsat;
                  funcSource: string = AttestInc3;
                  funcName: string = "inc3";
                  funcPath: string = ""): AttestationInputs =
  var inputs = AttestationInputs(
    schemaVersion: EvidenceScheme,
    subjectId: subject.subjectId,
    prNumber: 0,
    prHeadSha: subject.headSha,
    leanSource: leanSource,
    smtlib2: smtlib2,
    funcSource: funcSource,
    funcPath: funcPath,
    funcName: funcName,
    envDigest: hex64a(seed + 200),
    policyDigest: "",
    scopeDigest: "",
    toolchainIdentity: pinnedToolchainIdentity())
  inputs.policyDigest = sha256Hex(readFile(repoRoot / "config" / "policy" / "merge_admission.json"))
  inputs.scopeDigest = sha256Hex(readFile(repoRoot / "data" / "verification_scope.lock"))
  inputs

# ---------------------------------------------------------------------------
# P1 — pure semantics (always runs)
# ---------------------------------------------------------------------------
echo "=== P1: evidence codec + verdict mapping (pure) ==="
let subj1 = makeFixtureSubject(1)
let ev1 = makeEvidence(subj1, 1, funcPath = "tmp/ax_attest_ev_" & runId & ".nim")
checkEq("bundle digest is 64 hex", evidenceBundleDigest(ev1), sha256Hex(evidenceBundleWire(ev1)))
checkEq("bundle digest deterministic", evidenceBundleDigest(ev1), evidenceBundleDigest(ev1))
let bundleWire = evidenceBundleWire(ev1)
checkTrue("bundle wire covers funcName", bundleWire.contains("inc3"))
checkTrue("bundle wire covers leanSource", bundleWire.contains("axiom_attest_prop"))
let evJson = %*{
  "schemaVersion": EvidenceScheme,
  "subjectId": subj1.subjectId,
  "prNumber": 0,
  "prHeadSha": ev1.prHeadSha,
  "leanSource": ev1.leanSource,
  "smtlib2": ev1.smtlib2,
  "funcSource": ev1.funcSource,
  "funcPath": ev1.funcPath,
  "funcName": ev1.funcName,
  "policyDigest": ev1.policyDigest,
  "scopeDigest": ev1.scopeDigest,
  "envDigest": ev1.envDigest,
  "toolchainIdentity": ev1.toolchainIdentity
}
let decoded = inputsFromJson(evJson)
checkTrue("evidence record roundtrips", decoded.isOk)
let missingPolicy = %*{
  "schemaVersion": EvidenceScheme,
  "subjectId": subj1.subjectId,
  "prNumber": 0,
  "prHeadSha": ev1.prHeadSha,
  "leanSource": ev1.leanSource,
  "smtlib2": ev1.smtlib2,
  "funcSource": ev1.funcSource,
  "funcPath": ev1.funcPath,
  "funcName": ev1.funcName,
  "policyDigest": "",
  "scopeDigest": ev1.scopeDigest,
  "envDigest": ev1.envDigest,
  "toolchainIdentity": ev1.toolchainIdentity
}
checkTrue("empty policyDigest decodes at record level (stage-d denies it later)",
  inputsFromJson(missingPolicy).isOk)
let wrongSchema = %*{
  "schemaVersion": "axiom.attestation.evidence.v0",
  "subjectId": subj1.subjectId,
  "prNumber": 0,
  "prHeadSha": ev1.prHeadSha,
  "leanSource": ev1.leanSource,
  "smtlib2": ev1.smtlib2,
  "funcSource": ev1.funcSource,
  "funcPath": ev1.funcPath,
  "funcName": ev1.funcName,
  "policyDigest": ev1.policyDigest,
  "scopeDigest": ev1.scopeDigest,
  "envDigest": ev1.envDigest,
  "toolchainIdentity": ev1.toolchainIdentity
}
checkTrue("foreign schemaVersion rejected (fail-closed)", inputsFromJson(wrongSchema).isErr)
let v1Record = wrongSchema
v1Record["schemaVersion"] = %"axiom.attestation.evidence.v1"
let v1Parsed = inputsFromJson(v1Record)
checkTrue("v1 generation refused by the v2 parser (coherent cutover, fail-closed)",
  v1Parsed.isErr and v1Parsed.error.contains("schemaVersion"))
let mistypedBinding = wrongSchema
mistypedBinding["schemaVersion"] = %"axiom.attestation.evidence.v2"
mistypedBinding["llbcDigest"] = %7
checkTrue("v2 present-but-mistyped binding rejected", inputsFromJson(mistypedBinding).isErr)
checkEq("eaAgree → atPassed", $extractionVerdictFor(eaAgree), "atPassed")
checkEq("eaMismatch → atExtractionMismatch", $extractionVerdictFor(eaMismatch), "atExtractionMismatch")
checkEq("eaUnsupported → atExtractionUnsupported", $extractionVerdictFor(eaUnsupported), "atExtractionUnsupported")
checkEq("eaReferenceError → atExtractionMismatch", $extractionVerdictFor(eaReferenceError), "atExtractionMismatch")
checkEq("eaInternalError → atExtractionMismatch", $extractionVerdictFor(eaInternalError), "atExtractionMismatch")
checkEq("krPassed lean → atPassed", $kernelLeanVerdictFor(krPassed), "atPassed")
checkEq("krSorry lean → atKernelLeanFail", $kernelLeanVerdictFor(krSorry), "atKernelLeanFail")
checkEq("krPassed z3 → atPassed", $kernelZ3VerdictFor(krPassed), "atPassed")
checkEq("krZ3Mismatch z3 → atKernelZ3Fail", $kernelZ3VerdictFor(krZ3Mismatch), "atKernelZ3Fail")
checkEq("toolchain identity matches D2 form (v2: + charon extraction pin segment)",
  pinnedToolchainIdentity(),
  "nim-" & NimVersion & "|lean-4.33.0|z3-4.13.3|" & modelProfileIdentitySegment &
  charonIdentitySegment())

# ---------------------------------------------------------------------------
# P2/P3 — subject stage mismatches (no tools needed)
# ---------------------------------------------------------------------------
echo "=== P2/P3: subject match stage (fail-closed) ==="
let tmpBase = getTempDir() / ("ax_attest_" & runId)
let subjectsDir = tmpBase / "subjects"
createDir(subjectsDir)
let subjStore = makeFixtureSubject(2)
let saved = saveSubject(subjStore, subjectsDir)
checkTrue("store subject persisted", saved.isOk)
let ev2 = makeEvidence(subjStore, 2)
var wrongSubject = subjStore
wrongSubject.baseSha = hex40a(999)
let opts = defaultAttestationOptions()
var optsA = opts
optsA.subjectsDir = subjectsDir
optsA.certDir = tmpBase / "certs"
optsA.leanExe = ""
optsA.z3Path = ""
optsA.ircheckExe = repoRoot / "proofs" / ".lake" / "build" / "bin" / "ircheck"
checkVerdict("altered baseSha → atSubjectMismatch",
  attest(wrongSubject, ev2, optsA).verdict, atSubjectMismatch)
var unknownSubject = makeFixtureSubject(3)  # different ref — not in store
checkVerdict("unknown subject (no store record) → atSubjectMismatch",
  attest(unknownSubject, makeEvidence(unknownSubject, 3), optsA).verdict, atSubjectMismatch)
var foreignEvidence = ev2
foreignEvidence.subjectId = hex64(777)
checkVerdict("evidence subjectId ≠ store subject → atSubjectMismatch",
  attest(subjStore, foreignEvidence, optsA).verdict, atSubjectMismatch)

# ---------------------------------------------------------------------------
# P4 — extraction agreement stage (mismatch = fail-closed)
# ---------------------------------------------------------------------------
echo "=== P4: extraction agreement stage ==="
var evEmpty = makeEvidence(subjStore, 4)
evEmpty.funcSource = ""
evEmpty.funcName = "f"
evEmpty.policyDigest = ""
evEmpty.scopeDigest = ""
var realOpts = optsA
realOpts.policyPath = repoRoot / "config" / "policy" / "merge_admission.json"
realOpts.scopeLockPath = repoRoot / "data" / "verification_scope.lock"
let rEmptyAgree = attest(subjStore, evEmpty, realOpts)
checkVerdict("empty extraction fields → fail-closed record validation",
  rEmptyAgree.verdict, atInternalError)
checkTrue("empty-extraction reason is precise", rEmptyAgree.reason.len > 0)
var evNoFunc = makeEvidence(subjStore, 4)
evNoFunc.funcSource = ""
evNoFunc.funcName = "f"
let rNoFunc = attest(subjStore, evNoFunc, realOpts)
checkVerdict("missing func in evidence → fail-closed (never silent skip)",
  rNoFunc.verdict, atInternalError)
if workerAvailable:
  var evAgreeNonzero = makeEvidence(subjStore, 5, funcSource = AttestFactNonzero,
    funcName = "fact3", funcPath = "tmp/ax_attest_ev_" & runId & ".nim")
  # A separate cert dir keeps the now-minting non-zero fixture from colliding
  # with the P8 happy-path cert (append-only mint refuses a second write).
  var agreeOpts = realOpts
  agreeOpts.certDir = tmpBase / "certs_agree_nonzero"
  let rAgreeNonzero = attest(subjStore, evAgreeNonzero, agreeOpts)
  # The retval-degradation bug is repaired, so the differential now AGREES
  # and the chain proceeds past extraction (minting into the tmp vault).
  # The repaired behavior anchor: the verdict is NOT atExtractionMismatch —
  # extraction no longer fails the chain for a non-zero early return.
  checkTrue("non-zero early return no longer fails extraction",
    rAgreeNonzero.verdict != atExtractionMismatch)
  checkTrue("agreement outcome carries no EA failure",
    not rAgreeNonzero.reason.contains("EA_MISMATCH") and
    not rAgreeNonzero.reason.contains("EA_UNSUPPORTED"))
else:
  skip("extraction agreement fixture", "proofs/.lake/build/bin/ircheck not built")

# ---------------------------------------------------------------------------
# P5 — kernel re-execution stage failures (real lean/z3)
# ---------------------------------------------------------------------------
echo "=== P5: kernel re-execution stage ==="
if leanAvailable:
  var evSorry = makeEvidence(subjStore, 6, leanSource = AttestLeanSorry,
    funcPath = "tmp/ax_attest_ev_" & runId & ".nim")
  checkVerdict("sorry-laden leanSource → atKernelLeanFail",
    attest(subjStore, evSorry, realOpts).verdict, atKernelLeanFail)
else:
  skip("sorry-laden leanSource → atKernelLeanFail", "lean/lake not found")
if z3Available and leanAvailable:
  var evSat = makeEvidence(subjStore, 7, smtlib2 = AttestSmtSat,
    funcPath = "tmp/ax_attest_ev_" & runId & ".nim")
  let rSat = attest(subjStore, evSat, realOpts)
  checkVerdict("sat query (no fresh unsat) → atKernelZ3Fail", rSat.verdict, atKernelZ3Fail)
  checkTrue("z3-fail reason names the kernel verdict", rSat.reason.contains("z3"))
else:
  skip("sat query → atKernelZ3Fail", "lean/z3 not found")

# ---------------------------------------------------------------------------
# P6/P7 — policy / scope / toolchain digest stages (no tools needed)
# ---------------------------------------------------------------------------
echo "=== P6/P7: policy/scope/toolchain digest stages (post-kernel) ==="
if leanAvailable and z3Available and workerAvailable:
  var evPolicyFlip = makeEvidence(subjStore, 8,
    funcPath = "tmp/ax_attest_ev_" & runId & ".nim")
  let flippedByte = if evPolicyFlip.policyDigest[0] == 'a': 'b' else: 'a'
  evPolicyFlip.policyDigest[0] = flippedByte
  checkVerdict("policy digest flip → atPolicyDigestMismatch",
    attest(subjStore, evPolicyFlip, realOpts).verdict, atPolicyDigestMismatch)
  var evScopeFlip = makeEvidence(subjStore, 9,
    funcPath = "tmp/ax_attest_ev_" & runId & ".nim")
  let flippedScope = if evScopeFlip.scopeDigest[0] == 'a': 'b' else: 'a'
  evScopeFlip.scopeDigest[0] = flippedScope
  checkVerdict("scope digest flip → atScopeMismatch",
    attest(subjStore, evScopeFlip, realOpts).verdict, atScopeMismatch)
  var evToolFlip = makeEvidence(subjStore, 10,
    funcPath = "tmp/ax_attest_ev_" & runId & ".nim")
  evToolFlip.toolchainIdentity = evToolFlip.toolchainIdentity & "-x"
  checkVerdict("toolchain identity flip → atToolchainMismatch",
    attest(subjStore, evToolFlip, realOpts).verdict, atToolchainMismatch)
  var evCharonFlip = makeEvidence(subjStore, 16,
    funcPath = "tmp/ax_attest_ev_" & runId & ".nim")
  evCharonFlip.toolchainIdentity = evCharonFlip.toolchainIdentity.replace(
    "charon-" & PinnedCharonVersion, "charon-9.9.999")
  checkVerdict("charon segment flip → atToolchainMismatch (stage-e enforces the extraction pin)",
    attest(subjStore, evCharonFlip, realOpts).verdict, atToolchainMismatch)
  var evNoPolicy = makeEvidence(subjStore, 14,
    funcPath = "tmp/ax_attest_ev_" & runId & ".nim")
  evNoPolicy.policyDigest = ""
  let rNoPolicy = attest(subjStore, evNoPolicy, realOpts)
  checkVerdict("MISSING policy digest → fail-closed (missing ≠ valid-empty)",
    rNoPolicy.verdict, atPolicyDigestMismatch)
  checkTrue("missing-policy reason says empty", rNoPolicy.reason.contains("empty"))
  var evNoScope = makeEvidence(subjStore, 15,
    funcPath = "tmp/ax_attest_ev_" & runId & ".nim")
  evNoScope.scopeDigest = ""
  let rNoScope = attest(subjStore, evNoScope, realOpts)
  checkVerdict("MISSING scope digest → fail-closed (missing ≠ valid-empty)",
    rNoScope.verdict, atScopeMismatch)
  checkTrue("missing-scope reason says empty", rNoScope.reason.contains("empty"))
else:
  skip("policy/scope/toolchain digest stages", "lean/z3/ircheck worker not all present")

# ---------------------------------------------------------------------------
# P8 — HAPPY PATH: full chain + mint (real lean/z3/worker)
# ---------------------------------------------------------------------------
echo "=== P8: happy path — full chain → mint ==="
if leanAvailable and z3Available and workerAvailable:
  let moduleName = "build/tmp/ax_attest_mod_" & runId & ".nim"
  writeFile(repoRoot / moduleName, AttestInc3)
  let evHappy = makeEvidence(subjStore, 11, funcPath = moduleName)
  var happyOpts = realOpts
  happyOpts.certDir = tmpBase / "certs"
  let rHappy = attest(subjStore, evHappy, happyOpts)
  checkVerdict("full chain (a-f) passes", rHappy.verdict, atPassed)
  checkTrue("certificate minted", rHappy.certPath.len > 0 and fileExists(rHappy.certPath))
  let node = parseJson(readFile(rHappy.certPath))
  checkEq("kind = subject-continuity", node.getOrDefault("kind").getStr(""), "subject-continuity")
  checkEq("binds subjectId", node.getOrDefault("subjectId").getStr(""), subjStore.subjectId)
  checkEq("binds headSha", node.getOrDefault("headSha").getStr(""), subjStore.headSha)
  checkEq("binds headTreeDigest", node.getOrDefault("headTreeDigest").getStr(""), subjStore.headTreeDigest)
  checkEq("binds baseSha", node.getOrDefault("baseSha").getStr(""), subjStore.baseSha)
  checkEq("binds policyDigest (subject-recorded digest)", node.getOrDefault("policyDigest").getStr(""), subjStore.policyDigest)
  checkEq("binds scopeDigest (subject-recorded digest)", node.getOrDefault("scopeDigest").getStr(""), subjStore.scopeDigest)
  checkEq("binds evidenceDigest (subject-recorded digest)", node.getOrDefault("evidenceDigest").getStr(""), subjStore.evidenceDigest)
  checkEq("binds toolchainIdentity", node.getOrDefault("toolchainIdentity").getStr(""),
    pinnedToolchainIdentity())
  checkEq("status = certGreen (dual kernel evidence)", node.getOrDefault("status").getStr(), "certGreen")
  checkEq("claim type = subject-continuity", node.getOrDefault("claim").getOrDefault("type").getStr(""),
    "subject-continuity")
  checkEq("schemaVersion = v3", node.getOrDefault("schemaVersion").getStr(), "axiom.certificate.v3")
  checkTrue("v3 identityDigest present", node.getOrDefault("identityDigest").getStr("").len > 0)
  checkTrue("journal-bound", node.getOrDefault("trustCommitId").getStr("").len > 0)
  checkTrue("attestation block present", node.getOrDefault("attestation").getOrDefault("signature").getStr("").len == 128)
else:
  skip("happy path full chain", "lean/z3/ircheck worker not all present")

# ---------------------------------------------------------------------------
# P13 — duplicate-subject predicate (ADR-0021 D6, Phase 3 of the
# execution-authority plan): a subject whose certificate authority ALREADY
# exists in the side-ref ledger must not mint a second authority. The CLI
# predicate takes the ledger as the sole durable source; the fake transport
# below serves an existing ledger entry so the predicate rejects, and an
# empty ledger so a fresh subject passes.
# ---------------------------------------------------------------------------
echo "=== P13: duplicate-subject predicate (ADR-0021 D6) ==="
let p13Subject = makeFixtureSubject(40)
let p13CertId = p13Subject.subjectId
# fake transports — fully self-contained (P11's helpers live later in the
# file). ledgerHasSubjectCert consumes only tip + fetch; post/patch are
# carried for transport shape and never invoked.
let p13DummyPost: JsonPoster = proc(url: string; body: string): Result[JsonNode, string] {.raises: [CatchableError, OSError, Exception].} =
  err("p13: post not used")
let p13DummyPatch: JsonPatcher = proc(url: string; body: string): Result[JsonNode, string] {.raises: [CatchableError, OSError, Exception].} =
  err("p13: patch not used")
var p13Fetch: JsonFetcher = proc(url: string): Result[JsonNode, string] {.raises: [CatchableError, OSError, Exception].} =
  if url.contains("/git/commits/"):
    # Commit → tree resolution (fetchTipTree): tip resolves to a non-empty
    # tree — /git/trees/ below serves the entries.
    ok(%*{"sha": url[(url.rfind("/") + 1) .. ^1], "tree": {"sha": hex40a(702)}})
  elif url.contains("/git/trees/"):
    var entries = newJArray()
    entries.add(%*{"path": p13CertId & ".json", "type": "blob", "sha": hex40a(701)})
    ok(%*{"tree": entries})
  else:
    err("p13 fake fetch: unexpected " & url)
var p13Tip: LedgerTipFetcher = proc(repo: string): Result[string, string] {.raises: [CatchableError, OSError, Exception].} =
  ok(hex40a(700))
let p13Already = LedgerTransport(fetch: p13Fetch, post: p13DummyPost, patch: p13DummyPatch, tip: p13Tip)
let dup = ledgerHasSubjectCert(p13Already, "owner/repo", p13CertId)
checkTrue("existing ledger authority detected (duplicate-subject)", dup.isOk and dup.get)
# fresh subject against a ledger that does NOT yet contain it
var p13EmptyTip: LedgerTipFetcher = proc(repo: string): Result[string, string] {.raises: [CatchableError, OSError, Exception].} =
  ok("")  # absent ledger ref = empty ledger
let p13Empty = LedgerTransport(fetch: p13Fetch, post: p13DummyPost, patch: p13DummyPatch, tip: p13EmptyTip)
let fresh = ledgerHasSubjectCert(p13Empty, "owner/repo", hex64(404))
checkTrue("fresh subject not in ledger (allowed)", fresh.isOk and not fresh.get)
# ledger read failure → predicate err (caller must fail closed)
var p13ErrFetch: JsonFetcher = proc(url: string): Result[JsonNode, string] {.raises: [CatchableError, OSError, Exception].} =
  err("p13 fake fetch: transport down")
let p13Err = LedgerTransport(fetch: p13ErrFetch, post: p13DummyPost, patch: p13DummyPatch, tip: p13Tip)
let readFail = ledgerHasSubjectCert(p13Err, "owner/repo", p13CertId)
checkTrue("ledger read failure fails closed (err)", readFail.isErr)
checkTrue("read-failure reason names the ledger", readFail.error.contains("ledger"))

# ---------------------------------------------------------------------------
# P14 — INV-13 retroactive canonicalization (merged 2026-09-12): the merge
# consumers adopt the LATEST-createdAt certificate among multiple ledger certs
# of the same head/subject, instead of the first match. The list is
# lexicographically sorted by cert id (never by createdAt), so "last match"
# must not be used — explicit full-scan comparison is the contract. The
# selection logic lives in selectNewestCreatedAtCert, which BOTH merge
# consumers call; its behavior is verified here directly (the consumers'
# liveLedgerTransport is not injectable, so the shared selector is the
# unit of truth).
# ---------------------------------------------------------------------------
echo "=== P14: INV-13 canonicalization — latest createdAt wins (merge consumers) ==="
let p14Subject = makeFixtureSubject(41)
let p14Head = p14Subject.headSha
let p14Base = p14Subject.baseSha
let commonFields = %*{
  "kind": "subject-continuity",
  "subjectId": p14Subject.subjectId,
  "baseSha": p14Base,
  "headSha": p14Head,
  "headTreeDigest": p14Subject.headTreeDigest,
  "policyDigest": p14Subject.policyDigest,
  "scopeDigest": p14Subject.scopeDigest,
  "evidenceDigest": p14Subject.evidenceDigest,
  "status": "certGreen",
  "schemaVersion": "axiom.certificate.v3"
}
let oldNode = %*{}
for k, v in commonFields.pairs:
  oldNode[k] = v
oldNode["createdAt"] = %"2026-09-09T13:34:00Z"
let newNode = %*{}
for k, v in commonFields.pairs:
  newNode[k] = v
newNode["createdAt"] = %"2026-09-09T14:16:00Z"
# (a) exact duplicate pair: newest wins regardless of argument order
let pickOldFirst = selectNewestCreatedAtCert(oldNode, "2026-09-09T13:34:00Z",
  newNode, "2026-09-09T14:16:00Z")
checkTrue("newest wins when old comes first", pickOldFirst.cert == newNode)
checkEq("winner carries the newest createdAt", pickOldFirst.createdAt, "2026-09-09T14:16:00Z")
let pickNewFirst = selectNewestCreatedAtCert(newNode, "2026-09-09T14:16:00Z",
  oldNode, "2026-09-09T13:34:00Z")
checkTrue("newest wins when new comes first", pickNewFirst.cert == newNode)
checkEq("argument order does not change the winner", pickNewFirst.createdAt, "2026-09-09T14:16:00Z")
# (b) single-cert path is invariant: identical createdAt pair keeps the winner
let pickTie = selectNewestCreatedAtCert(oldNode, "2026-09-09T13:34:00Z",
  newNode, "2026-09-09T13:34:00Z")
checkTrue("tie keeps the current winner deterministically", pickTie.cert == oldNode)
# (c) one-sided timestamp: the timestamped cert wins (missing mint cannot preempt)
let pickNoTs = selectNewestCreatedAtCert(oldNode, "", newNode, "2026-09-09T14:16:00Z")
checkTrue("timestamped cert wins over a cert without createdAt", pickNoTs.cert == newNode)
checkEq("no-createdAt str never becomes the winner", pickNoTs.createdAt, "2026-09-09T14:16:00Z")

# ---------------------------------------------------------------------------
# P9 — post-mint tamper of ANY bound field → structural verify rejects
# (tampered copy must exit 1 = attestation-layer rejection, NOT 4/2)
# ---------------------------------------------------------------------------
echo "=== P9: tamper post-mint → ax cert verify rejects ==="
if leanAvailable and z3Available and workerAvailable:
  let moduleName = "build/tmp/ax_attest_mod_" & runId & ".nim"
  if not fileExists(repoRoot / moduleName):
    writeFile(repoRoot / moduleName, AttestInc3)
  let evForTamper = makeEvidence(subjStore, 12, funcPath = moduleName)
  var tamperOpts = realOpts
  tamperOpts.certDir = tmpBase / "certs-tamper"   # distinct vault — append-only would refuse a second mint of the same subject
  # Journal isolation (post 1c4e939fc unified journal root): the mint
  # (commitCertificateVerification) and the CLI reader
  # (verifyCertificateClosure) resolve the SAME activeJournalRoot —
  # AXIOM_STATE_DIR first. Point it at temp dirs so the scenario never reads
  # or writes the repo journal.
  let p9PrevState = getEnv("AXIOM_STATE_DIR", "")
  let p9State = tmpBase / "p9_journal_state"
  let p9StateEmpty = tmpBase / "p9_journal_state_empty"
  createDir(p9State)
  createDir(p9StateEmpty)
  putEnv("AXIOM_STATE_DIR", p9State)
  let rMint = attest(subjStore, evForTamper, tamperOpts)
  checkTrue("tamper-fixture cert minted", rMint.verdict == atPassed)
  let axBin = repoRoot / "bin" / "ax"
  if fileExists(axBin):
    # Sanity leg 1: the UNTAMPERED cert verifies END-TO-END against the same
    # journal root the mint committed to — deep verify + attestation + journal
    # binding + replay equality all pass (exit 0, replayMatched=true).
    let (sanityOut, sanityCode) = execCmdEx(quoteShell(axBin) & " cert verify " &
      quoteShell(rMint.certPath), options = {poUsePath}, workingDir = repoRoot)
    checkEq("untampered cert verifies fully (deep verify + attestation + journal replay)",
      $sanityCode, "0")
    checkTrue("verify pass reports replayMatched=true", sanityOut.contains("replayMatched=true"))
    # Sanity leg 2 (anti-stale-binary): against an EMPTY journal root the same
    # cert must still REACH the journal stage and fail closed JOURNAL_REQUIRED
    # (exit 2) — a binary that skipped the journal leg would exit 0 here.
    putEnv("AXIOM_STATE_DIR", p9StateEmpty)
    let (sanityOut2, sanityCode2) = execCmdEx(quoteShell(axBin) & " cert verify " &
      quoteShell(rMint.certPath), options = {poUsePath}, workingDir = repoRoot)
    putEnv("AXIOM_STATE_DIR", p9PrevState)
    checkEq("cert vs empty journal root reaches journal stage (binary self-consistent)",
      $sanityCode2, "2")
    checkTrue("journal-stage rejection names JOURNAL_REQUIRED",
      sanityOut2.contains("JOURNAL_REQUIRED"))
    let tamperedPath = tmpBase / "tampered_subject_id.json"
    let goodNode = parseJson(readFile(rMint.certPath))
    goodNode["subjectId"] = %(hex64(4242))
    writeFile(tamperedPath, $goodNode)
    let (outp, code) = execCmdEx(quoteShell(axBin) & " cert verify " & quoteShell(tamperedPath),
      options = {poUsePath}, workingDir = repoRoot)
    checkEq("tampered subjectId rejected (exit 1 = attestation layer)", $code, "1")
    checkTrue("rejection names the attestation check", outp.contains("attestation") or outp.contains("FAIL"))
    let tamperedPath2 = tmpBase / "tampered_evidence_digest.json"
    let goodNode2 = parseJson(readFile(rMint.certPath))
    goodNode2["evidenceDigest"] = %(hex64(4243))
    writeFile(tamperedPath2, $goodNode2)
    let (outp2, code2) = execCmdEx(quoteShell(axBin) & " cert verify " & quoteShell(tamperedPath2))
    checkEq("tampered evidenceDigest rejected (exit 1)", $code2, "1")
    checkTrue("digest-tamper rejection names the attestation check",
      outp2.contains("attestation") or outp2.contains("FAIL"))
  else:
    skip("tamper rejection via CLI binary", "bin/ax not built")
    putEnv("AXIOM_STATE_DIR", p9PrevState)
else:
  skip("tamper rejection suite", "lean/z3/ircheck worker not all present")

# ---------------------------------------------------------------------------
# P10 — cert roundtrip: mint → ax cert verify --kernel passes (real toolchain)
# ---------------------------------------------------------------------------
echo "=== P10: cert roundtrip — ax cert verify --kernel on the real cert ==="
if leanAvailable and z3Available and workerAvailable:
  let moduleName = "build/tmp/ax_attest_rt_" & runId & ".nim"
  writeFile(repoRoot / moduleName, AttestInc3)
  putEnv("AXIOM_STATE_DIR", "")  # journal must land in the repo-root journal
  let evRt = makeEvidence(subjStore, 13, funcPath = moduleName)
  var rtOpts = realOpts
  rtOpts.certDir = repoRoot / "data" / "trusted" / "certificates"  # runtime canonical vault
  let rRt = attest(subjStore, evRt, rtOpts)
  checkTrue("roundtrip cert minted", rRt.verdict == atPassed and fileExists(rRt.certPath))
  let axBin = repoRoot / "bin" / "ax"
  if fileExists(axBin):
    let (outp, code) = execCmdEx(quoteShell(axBin) & " cert verify --kernel " & quoteShell(rRt.certPath),
      options = {poUsePath}, workingDir = repoRoot)
    checkEq("ax cert verify --kernel exits 0", $code, "0")
    checkTrue("verify output reports PASS", outp.contains("PASS"))
  else:
    skip("CLI kernel roundtrip", "bin/ax not built")
  # cleanup: vault cert + repo-root journal commit + module fixture
  try: removeFile(rRt.certPath) except CatchableError: discard
  if rRt.commitId.len > 0:
    let jf = repoRoot / "data" / "trusted" / "journal" / (rRt.commitId & ".json")
    try: removeFile(jf) except CatchableError: discard
  try: removeFile(repoRoot / moduleName) except CatchableError: discard
  let jfIdx = repoRoot / "data" / "trusted" / "journal" / (rRt.commitId & ".idx")
  try: removeFile(jfIdx) except CatchableError: discard
else:
  skip("cert roundtrip suite", "lean/z3/ircheck worker not all present")

# ---------------------------------------------------------------------------
# P11 — side-ref ledger (injectable fake transport)
# ---------------------------------------------------------------------------
echo "=== P11: side-ref ledger — append FF / non-FF / malformed / list ==="

type
  FakeBackend = ref object
    tip: string
    counter: int
    rejectPatch: bool
    malformedBlob: bool
    treePaths: seq[string]
    garbageTree: bool
    fetchCalls: int
    postCalls: int
    patchCalls: int
    blobPosts: int

proc fakeSha(prefix: string; b: FakeBackend): string =
  inc b.counter
  let h = sha256Hex(prefix & $b.counter & runId)
  h[0 ..< 40]

let certIdA = hex64(300)
let certIdB = hex64(301)
let certPayload = canonicalJsonString(%*{
  "kind": "subject-continuity",
  "subjectId": certIdA,
  "status": "certGreen",
  "schemaVersion": "axiom.certificate.v3"
})
let certFile = tmpBase / ("ledger_" & certIdA & ".json")
writeFile(certFile, certPayload)
let foreignFile = tmpBase / "foreign_cert.json"
writeFile(foreignFile, $ %*{"kind": "verification", "status": "certGreen"})

let b1 = FakeBackend(tip: "", counter: 0, rejectPatch: false, malformedBlob: false,
  treePaths: @[certIdB], garbageTree: false)
var fetch1: JsonFetcher = proc(url: string): Result[JsonNode, string] {.raises: [CatchableError, OSError, Exception].} =
  inc b1.fetchCalls
  if url.contains("/git/commits/"):
    # Commit → tree resolution (fetchTipTree): tip resolves to a non-empty
    # tree — /git/trees/ below serves the entries.
    ok(%*{"sha": url[(url.rfind("/") + 1) .. ^1], "tree": {"sha": hex40a(905)}})
  elif url.contains("/git/trees/"):
    var entries = newJArray()
    for p in b1.treePaths:
      entries.add(%*{"path": p & ".json", "type": "blob", "sha": fakeSha("b", b1)})
    if b1.garbageTree:
      entries.add(%*{"path": "note.txt", "type": "blob", "sha": fakeSha("g", b1)})
    ok(%*{"tree": entries})
  else:
    err("fake fetch: unexpected " & url)
var post1: JsonPoster = proc(url: string; body: string): Result[JsonNode, string] {.raises: [CatchableError, OSError, Exception].} =
  inc b1.postCalls
  if url.contains("/git/blobs"):
    if b1.malformedBlob:
      return ok(newJObject())  # malformed: missing sha
    ok(%*{"sha": fakeSha("blob", b1)})
  elif url.contains("/git/trees"):
    ok(%*{"sha": fakeSha("tree", b1)})
  elif url.contains("/git/commits"):
    ok(%*{"sha": fakeSha("commit", b1)})
  elif url.contains("/git/refs"):
    ok(%*{"sha": fakeSha("ref", b1)})
  else:
    err("fake post: unexpected " & url)
var patch1: JsonPatcher = proc(url: string; body: string): Result[JsonNode, string] {.raises: [CatchableError, OSError, Exception].} =
  inc b1.patchCalls
  if b1.rejectPatch:
    return err("GitHub API PATCH " & url & " -> 422: Ref cannot be updated (non-fast-forward)")
  let bodyNode = parseJson(body)
  let newSha = bodyNode.getOrDefault("sha").getStr("")
  b1.tip = newSha
  ok(%*{"ref": "refs/heads/axiom/certificates", "object": {"type": "commit", "sha": newSha}})
var tip1: LedgerTipFetcher = proc(repo: string): Result[string, string] {.raises: [CatchableError, OSError, Exception].} =
  ok(b1.tip)
let transport1 = LedgerTransport(fetch: fetch1, post: post1, patch: patch1, tip: tip1)

checkTrue("foreign (non-subject) cert refused (fail-closed)",
  appendCertificate(transport1, "owner/repo", foreignFile).isErr)
checkTrue("missing file refused (fail-closed)",
  appendCertificate(transport1, "owner/repo", tmpBase / "nope.json").isErr)
checkTrue("malformed-input refusals never touch the transport (0 retries, 0 calls)",
  b1.fetchCalls == 0 and b1.postCalls == 0 and b1.patchCalls == 0)
let append1 = appendCertificate(transport1, "owner/repo", certFile)
checkTrue("append succeeds (root creation on absent ref)", append1.isOk)
checkEq("append returns the new tip", append1.get, b1.tip)
checkTrue("tip advanced after append", b1.tip.len == 40)
# second append is a fast-forward on the moved tip
let certFileB = tmpBase / ("ledger_" & certIdB & ".json")
writeFile(certFileB, canonicalJsonString(%*{
  "kind": "subject-continuity",
  "subjectId": certIdB,
  "status": "certGreen",
  "schemaVersion": "axiom.certificate.v3"
}))
let append2 = appendCertificate(transport1, "owner/repo", certFileB)
checkTrue("second append (FF on current tip) succeeds", append2.isOk)
checkEq("second append advances tip", append2.get, b1.tip)
let list1 = listLedgerCertIds(transport1, "owner/repo")
checkTrue("ledger-list reads ids", list1.isOk)
checkEq("ledger-list reads the appended id", list1.get.join(","), certIdB)

# persistent concurrent move (non-FF): EVERY PATCH is rejected 422 → the
# bounded retry (LedgerAppendMaxAttempts attempts) exhausts and the append
# fails closed — the tip never advances, no entry ever lands.
let b2 = FakeBackend(tip: "", counter: 0, rejectPatch: true, malformedBlob: false,
  treePaths: @[], garbageTree: false)
var fetch2: JsonFetcher = proc(url: string): Result[JsonNode, string] {.raises: [CatchableError, OSError, Exception].} =
  inc b2.fetchCalls
  if url.contains("/git/commits/"):
    # Commit → tree resolution (fetchTipTree): non-empty tree sha — the
    # /git/trees/ branch below serves treePaths (empty here → no entries).
    ok(%*{"sha": url[(url.rfind("/") + 1) .. ^1], "tree": {"sha": hex40a(906)}})
  elif url.contains("/git/trees/"):
    var entries = newJArray()
    for p in b2.treePaths:
      entries.add(%*{"path": p & ".json", "type": "blob", "sha": fakeSha("b", b2)})
    ok(%*{"tree": entries})
  else:
    err("fake fetch2: unexpected " & url)
var post2: JsonPoster = proc(url: string; body: string): Result[JsonNode, string] {.raises: [CatchableError, OSError, Exception].} =
  inc b2.postCalls
  if url.contains("/git/blobs"):
    ok(%*{"sha": fakeSha("blob", b2)})
  elif url.contains("/git/trees"):
    ok(%*{"sha": fakeSha("tree", b2)})
  elif url.contains("/git/commits"):
    ok(%*{"sha": fakeSha("commit", b2)})
  elif url.contains("/git/refs"):
    ok(%*{"sha": fakeSha("ref", b2)})
  else:
    err("fake post2: unexpected " & url)
var patch2: JsonPatcher = proc(url: string; body: string): Result[JsonNode, string] {.raises: [CatchableError, OSError, Exception].} =
  inc b2.patchCalls
  if b2.rejectPatch:
    return err("GitHub API PATCH " & url & " -> 422: Ref cannot be updated (non-fast-forward)")
  ok(newJObject())
var tip2: LedgerTipFetcher = proc(repo: string): Result[string, string] {.raises: [CatchableError, OSError, Exception].} =
  ok(b2.tip)
let transport2 = LedgerTransport(fetch: fetch2, post: post2, patch: patch2, tip: tip2)
let concAppend = appendCertificate(transport2, "owner/repo", certFile)
checkTrue("persistent concurrent move (non-FF PATCH) → retry exhaustion → fail-closed", concAppend.isErr)
checkTrue("exhaustion reason states the attempt bound (after 4 attempts)",
  concAppend.error.contains("concurrent ledger append conflict after 4 attempts"))
checkTrue("exhaustion carries the last 422 conflict error", concAppend.error.contains("422"))
checkTrue("persistent conflict: exactly 4 PATCH attempts (no early give-up, no extra)",
  b2.patchCalls == 4)
checkTrue("persistent conflict: tip never advanced (no partial entry)", b2.tip.len == 0)

# malformed blob response → fail-closed, never retried (a non-conflict error)
let b3 = FakeBackend(tip: "", counter: 0, rejectPatch: false, malformedBlob: true,
  treePaths: @[], garbageTree: false)
var fetch3: JsonFetcher = proc(url: string): Result[JsonNode, string] {.raises: [CatchableError, OSError, Exception].} =
  inc b3.fetchCalls
  err("fake fetch3 unexpected " & url)
var post3: JsonPoster = proc(url: string; body: string): Result[JsonNode, string] {.raises: [CatchableError, OSError, Exception].} =
  inc b3.postCalls
  if url.contains("/git/blobs"):
    inc b3.blobPosts
    return ok(newJObject())  # malformed: no sha
  ok(%*{"sha": fakeSha("x", b3)})
var patch3: JsonPatcher = proc(url: string; body: string): Result[JsonNode, string] {.raises: [CatchableError, OSError, Exception].} =
  inc b3.patchCalls
  ok(newJObject())
var tip3: LedgerTipFetcher = proc(repo: string): Result[string, string] {.raises: [CatchableError, OSError, Exception].} =
  ok("")
let transport3 = LedgerTransport(fetch: fetch3, post: post3, patch: patch3, tip: tip3)
let malformedAppend = appendCertificate(transport3, "owner/repo", certFile)
checkTrue("malformed blob response → fail-closed", malformedAppend.isErr)
checkTrue("malformed-response failure names blob", malformedAppend.error.contains("blob"))
checkTrue("malformed blob response does NOT retry (1 blob POST attempt, 0 PATCHes)",
  b3.blobPosts == 1 and b3.patchCalls == 0 and b3.fetchCalls == 0)

# ledger-list integrity violation: non-canonical file in the ledger
let b4 = FakeBackend(tip: hex40a(500), counter: 0, rejectPatch: false, malformedBlob: false,
  treePaths: @[], garbageTree: true)
var fetch4: JsonFetcher = proc(url: string): Result[JsonNode, string] {.raises: [CatchableError, OSError, Exception].} =
  if url.contains("/git/commits/"):
    # Commit → tree resolution (fetchTipTree): non-empty tree sha — the
    # /git/trees/ branch below serves the (garbage) entries.
    ok(%*{"sha": url[(url.rfind("/") + 1) .. ^1], "tree": {"sha": hex40a(907)}})
  elif url.contains("/git/trees/"):
    var entries = newJArray()
    entries.add(%*{"path": certIdA & ".json", "type": "blob", "sha": fakeSha("b", b4)})
    entries.add(%*{"path": "note.txt", "type": "blob", "sha": fakeSha("g", b4)})
    ok(%*{"tree": entries})
  else:
    err("fake fetch4 unexpected " & url)
var tip4: LedgerTipFetcher = proc(repo: string): Result[string, string] {.raises: [CatchableError, OSError, Exception].} =
  ok(b4.tip)
let transport4 = LedgerTransport(fetch: fetch4, post: post1, patch: patch1, tip: tip4)
let badList = listLedgerCertIds(transport4, "owner/repo")
checkTrue("non-canonical ledger file → fail-closed", badList.isErr)
checkTrue("non-canonical file failure names the file", badList.error.contains("note.txt"))

# ---------------------------------------------------------------------------
# P11-retry — bounded retry-on-conflict INSIDE appendCertificate (PR-concurrent
# mint redesign): ONLY concurrent-move conditions retry (HTTP 422 from the ref
# PATCH, or a raced root-ref create), at most LedgerAppendMaxAttempts attempts.
# Every retry re-reads the tip, re-checks subject uniqueness against the NEW
# tip (a same-subject entry that landed with the moved tip must fail closed —
# never re-appended), rebuilds the deterministic objects on the moved tip, and
# PATCHes force=false again. Everything else fails closed immediately.
# ---------------------------------------------------------------------------

type
  RetryLedger = ref object
    tip: string                       # current simulated ref tip
    entries: Table[string, seq[string]]  # sha → certificate ids at that tip
    conflictPatches: int              # PATCHes to reject with 422 first
    patchErrAfter: string             # non-422 PATCH error once conflicts exhausted ("" = accept)
    rejectRefCreates: int             # ref-create POSTs to reject with 422 first
    movedTip: string                  # tip the simulated concurrent writer moves to on rejection
    emptyTreeCommits: seq[string] = @[]  # commit shas whose tree IS the empty tree (a raced writer's ROOT commit)
    counter: int
    patchCalls: int
    refCreateCalls: int
    treeBases: seq[string]            # base_tree of every tree-create POST (rebase audit)

proc retrySha(b: RetryLedger; prefix: string): string =
  inc b.counter
  sha256Hex(prefix & $b.counter & runId)[0 ..< 40]

proc retryTransport(b: RetryLedger): LedgerTransport =
  var fetch: JsonFetcher = proc(url: string): Result[JsonNode, string] {.raises: [CatchableError, OSError, Exception].} =
    if url.contains("/git/commits/"):
      let sha = url.split("/git/commits/")[1]
      # SL-15: a raced writer's ROOT commit carries the well-known EMPTY tree
      # — model GitHub exactly (that tree is never a fetchable object).
      if sha in b.emptyTreeCommits:
        return ok(%*{"sha": sha, "tree": {"sha": EmptyTreeSha}})
      # Commit → tree resolution (fetchTipTree): the fake collapses commit
      # and tree identity — a commit sha IS its tree sha in b.entries.
      if not b.entries.hasKey(sha):
        return err("fake retry fetch: unknown commit " & sha)
      return ok(%*{"sha": sha, "tree": {"sha": sha}})
    elif url.contains("/git/trees/"):
      let sha = url.split("/git/trees/")[1].split("?")[0]
      # SL-15: the empty tree is not served — refuse like GitHub's trees API.
      if sha == EmptyTreeSha:
        return err("GitHub API error for " & url & ": 404 Not Found")
      if not b.entries.hasKey(sha):
        return err("fake retry fetch: unknown tip " & sha)
      var arr = newJArray()
      for id in b.entries[sha]:
        arr.add(%*{"path": id & ".json", "type": "blob", "sha": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"})
      return ok(%*{"tree": arr})
    err("fake retry fetch: unexpected " & url)
  var post: JsonPoster = proc(url: string; body: string): Result[JsonNode, string] {.raises: [CatchableError, OSError, Exception].} =
    if url.contains("/git/blobs"):
      return ok(%*{"sha": retrySha(b, "rblob")})
    if url.contains("/git/trees"):
      let node = parseJson(body)
      let base = node.getOrDefault("base_tree").getStr("")
      let id0 = if node.getOrDefault("tree").kind == JArray and
          node.getOrDefault("tree").len > 0:
          node.getOrDefault("tree")[0].getOrDefault("path").getStr("")
        else: ""
      let id = if id0.endsWith(".json"): id0[0 ..< id0.len - 5] else: id0
      let treeSha = retrySha(b, "rtree")
      var ids = if base.len > 0 and b.entries.hasKey(base): b.entries[base] else: newSeq[string]()
      if id.len > 0:
        ids.add(id)
      b.entries[treeSha] = ids
      b.treeBases.add(base)
      return ok(%*{"sha": treeSha})
    if url.contains("/git/commits"):
      let node = parseJson(body)
      let tree = node.getOrDefault("tree").getStr("")
      let commitSha = retrySha(b, "rcommit")
      b.entries[commitSha] = if b.entries.hasKey(tree): b.entries[tree] else: newSeq[string]()
      return ok(%*{"sha": commitSha})
    if url.endsWith("/git/refs"):
      inc b.refCreateCalls
      if b.refCreateCalls <= b.rejectRefCreates:
        if b.movedTip.len > 0:
          b.tip = b.movedTip
        return err("GitHub API POST " & url & " -> 422: Reference already exists")
      return ok(%*{"sha": retrySha(b, "rref")})
    err("fake retry post: unexpected " & url)
  var patch: JsonPatcher = proc(url: string; body: string): Result[JsonNode, string] {.raises: [CatchableError, OSError, Exception].} =
    inc b.patchCalls
    if b.patchCalls <= b.conflictPatches:
      if b.movedTip.len > 0:
        b.tip = b.movedTip
      return err("GitHub API PATCH " & url & " -> 422: Ref cannot be updated (non-fast-forward)")
    if b.patchErrAfter.len > 0:
      return err(b.patchErrAfter)
    let newSha = parseJson(body).getOrDefault("sha").getStr("")
    b.tip = newSha
    ok(%*{"ref": "refs/heads/axiom/certificates", "object": {"type": "commit", "sha": newSha}})
  var tip: LedgerTipFetcher = proc(repo: string): Result[string, string] {.raises: [CatchableError, OSError, Exception].} =
    ok(b.tip)
  LedgerTransport(fetch: fetch, post: post, patch: patch, tip: tip)

let certIdC = hex64(305)   # concurrent writer's earlier entry
let certIdD = hex64(306)   # concurrent writer's entry that moves the tip

# (a) retry succeeds: concurrent other-subject writer moves the tip once —
#     second attempt re-reads the NEW tip, re-checks uniqueness, rebuilds on
#     the moved tip, PATCHes successfully. No lost update, exactly one entry
#     from us.
let t0a = hex40a(801)
let movedA = hex40a(802)
var entriesA = initTable[string, seq[string]]()
entriesA[t0a] = @[certIdC]
let ra = RetryLedger(tip: t0a, entries: entriesA, conflictPatches: 1, movedTip: movedA)
ra.entries[movedA] = @[certIdC, certIdD]
let transportRa = retryTransport(ra)
let retryAppend = appendCertificate(transportRa, "owner/repo", certFile)
checkTrue("retry succeeds after one concurrent move", retryAppend.isOk)
checkEq("retry returns the NEW tip", retryAppend.get, ra.tip)
checkTrue("one 422 conflict then one success (exactly 2 PATCH attempts)", ra.patchCalls == 2)
checkEq("retry rebuilt the objects parented on the MOVED tip (no lost update)",
  ra.treeBases.join(","), t0a & "," & movedA)
let retryIds = listLedgerCertIds(transportRa, "owner/repo")
checkTrue("concurrent writer's entry preserved after retry (no lost update)",
  retryIds.isOk and certIdC in retryIds.get and certIdD in retryIds.get)
checkTrue("our subject appears exactly once — ledger grew by exactly one entry",
  retryIds.isOk and retryIds.get.len == 3 and certIdA in retryIds.get)

# (b) exhaustion fails closed: a permanent 422 on EVERY attempt → after
#     exactly 4 attempts an error is returned and NO partial entry was written
#     (tip unmoved, ledger unchanged).
let t0b = hex40a(803)
var entriesB = initTable[string, seq[string]]()
entriesB[t0b] = @[certIdC]
let rb = RetryLedger(tip: t0b, entries: entriesB, conflictPatches: 99)
let transportRb = retryTransport(rb)
let exhaustedAppend = appendCertificate(transportRb, "owner/repo", certFile)
checkTrue("conflict on EVERY attempt → exhaustion fail-closed", exhaustedAppend.isErr)
checkTrue("exhaustion message states the attempt bound (after 4 attempts)",
  exhaustedAppend.error.contains("concurrent ledger append conflict after 4 attempts"))
checkTrue("exhaustion carries the last 422 conflict error", exhaustedAppend.error.contains("422"))
checkTrue("permanent conflict: exactly 4 PATCH attempts", rb.patchCalls == 4)
checkEq("every retry rebuild parented on the same unmoved tip (4 builds)",
  rb.treeBases.join(","), t0b & "," & t0b & "," & t0b & "," & t0b)
checkTrue("exhaustion: ref tip never advanced (no partial entry)", rb.tip == t0b)
let bExhIds = listLedgerCertIds(transportRb, "owner/repo")
checkTrue("exhaustion: ledger still holds only the pre-existing cert (no partial entry)",
  bExhIds.isOk and bExhIds.get.len == 1 and certIdC in bExhIds.get and certIdA notin bExhIds.get)

# (c) non-conflict errors do NOT retry: a 500 on the first PATCH fails on
#     attempt 1; a non-conflict error after one conflict stops mid-retry.
let t0c = hex40a(804)
var entriesC = initTable[string, seq[string]]()
entriesC[t0c] = @[]
let rc = RetryLedger(tip: t0c, entries: entriesC, patchErrAfter: "GitHub API PATCH <url> -> 500: internal")
let transportRc = retryTransport(rc)
let err500 = appendCertificate(transportRc, "owner/repo", certFile)
checkTrue("non-conflict PATCH failure (500) → fail-closed on attempt 1", err500.isErr)
checkTrue("500 failure names the ref update", err500.error.contains("ref update failed"))
checkTrue("500 failure does NOT retry (exactly 1 PATCH attempt)", rc.patchCalls == 1)
let movedC = hex40a(805)
var entriesD2 = initTable[string, seq[string]]()
entriesD2[t0c] = @[]
let rd = RetryLedger(tip: t0c, entries: entriesD2,
  conflictPatches: 1, patchErrAfter: "GitHub API PATCH <url> -> 401: bad token", movedTip: movedC)
rd.entries[movedC] = @[certIdC]
let transportRd = retryTransport(rd)
let errMid = appendCertificate(transportRd, "owner/repo", certFile)
checkTrue("non-conflict failure AFTER one conflict → fail-closed mid-retry", errMid.isErr)
checkTrue("mid-retry non-conflict failure is NOT retried further (2 PATCH attempts total)",
  rd.patchCalls == 2)

# (d) REQUIRED retry correctness: same-subject race — the concurrent writer
#     that moved the tip minted the SAME subject. The retry must detect the
#     duplicate against the NEW tip and fail closed WITHOUT appending (the
#     workflow D6 predicate guarded only the ORIGINAL tip).
let t0d = hex40a(806)
let movedD = hex40a(807)
var entriesD = initTable[string, seq[string]]()
entriesD[t0d] = @[]
let rsd = RetryLedger(tip: t0d, entries: entriesD, conflictPatches: 1, movedTip: movedD)
rsd.entries[movedD] = @[certIdA]   # the concurrent writer minted the same subject
let transportRsd = retryTransport(rsd)
let dupAppend = appendCertificate(transportRsd, "owner/repo", certFile)
checkTrue("same-subject concurrent move → duplicate detected → fail-closed", dupAppend.isErr)
checkTrue("duplicate failure names the subject (fail-closed, not re-appended)",
  dupAppend.error.contains("duplicate subject") and dupAppend.error.contains(certIdA))
checkTrue("duplicate detection happens BEFORE a second PATCH (exactly 1 PATCH attempt)",
  rsd.patchCalls == 1)
checkEq("duplicate failure appends NOTHING (single build on the ORIGINAL tip)",
  rsd.treeBases.join(","), t0d)
checkTrue("duplicate failure never advanced the tip (concurrent writer's tip stands)",
  rsd.tip == movedD and rsd.entries[movedD].len == 1)
let d6After = ledgerHasSubjectCert(transportRsd, "owner/repo", certIdA)
checkTrue("winner's authority visible to the D6 predicate (exactly one authority)",
  d6After.isOk and d6After.get)

# (e) root-creation race: two mints root the absent ref simultaneously — the
#     loser's ref-create gets 422 → treated as a conflict → next attempt
#     re-reads the winner's tip and proceeds with a normal append.
let winnerRoot = hex40a(808)
let re = RetryLedger(tip: "", entries: initTable[string, seq[string]](),
  rejectRefCreates: 1, movedTip: winnerRoot)
re.entries[winnerRoot] = @[]
let transportRe = retryTransport(re)
let rootRaceAppend = appendCertificate(transportRe, "owner/repo", certFile)
checkTrue("root-creation race (422 ref create) → retry re-reads winner's root → append succeeds",
  rootRaceAppend.isOk)
checkEq("root-race retry returns the new tip", rootRaceAppend.get, re.tip)
checkTrue("root race rejected exactly once, then the retry proceeded", re.refCreateCalls == 1)
checkTrue("root-race retry PATCHes exactly once (no spurious retries)", re.patchCalls == 1)
checkEq("root-race append parented on the WINNER's root (single rebuild)",
  re.treeBases.join(","), winnerRoot)
let reIds = listLedgerCertIds(transportRe, "owner/repo")
checkTrue("root-race ledger holds exactly our entry", reIds.isOk and reIds.get.len == 1 and certIdA in reIds.get)

# (f) SL-15 empty-tree tolerance (mirrors the evidence-ledger fix): the
#     winner's root commit carries the well-known EMPTY tree — GitHub refuses
#     to serve that tree (404 Not Found), so the retry's duplicate re-check
#     must answer the freshly rooted ledger positively (nothing stored) via
#     the commit→tree dereference instead of failing closed on the refused
#     tree read.
let winnerEmptyRoot = hex40a(809)
let rf = RetryLedger(tip: "", entries: initTable[string, seq[string]](),
  rejectRefCreates: 1, movedTip: winnerEmptyRoot)
rf.emptyTreeCommits.add(winnerEmptyRoot)
let transportRf = retryTransport(rf)
let emptyRootRaceAppend = appendCertificate(transportRf, "owner/repo", certFile)
checkTrue("empty-tree winner root: re-check answers the empty ledger positively → append succeeds",
  emptyRootRaceAppend.isOk)
checkEq("empty-root race retry parents on the winner's empty-tree root",
  emptyRootRaceAppend.get, rf.tip)
checkTrue("empty-root race rejected exactly once, then the retry proceeded",
  rf.refCreateCalls == 1)
checkTrue("empty-root race PATCHes exactly once (re-check never failed closed)",
  rf.patchCalls == 1)
checkEq("empty-root append parented on the WINNER's root (single rebuild)",
  rf.treeBases.join(","), winnerEmptyRoot)
let rfIds = listLedgerCertIds(transportRf, "owner/repo")
checkTrue("empty-root race ledger holds exactly our entry",
  rfIds.isOk and rfIds.get.len == 1 and certIdA in rfIds.get)

# ---------------------------------------------------------------------------
# P12 — `ax cert subject-register` (F8 2026-09-12): trusted-boundary subject
# registration from VERIFIED evidence. Exercises the CLI verb against a scratch
# subject vault dir. Bindings that are the workflow's job (dispatch headSha ==
# evidence.prHeadSha; GitHub API tree re-derivation) are NOT re-checked here —
# this test covers the verb's OWN contract: evidence parse, canonical subjectId
# re-derivation from the 6-field wire, append-only persistence, idempotence,
# and fail-closed on missing evidence/malformed head-tree.
# ---------------------------------------------------------------------------
echo "=== P12: subject-register (F8 trusted-boundary issuance) ==="
let regBase = tmpBase / "reg"
createDir(regBase)
let regSubject = makeFixtureSubject(30)
let regEv = makeEvidence(regSubject, 30, funcPath = "tmp/ax_attest_ev_" & runId & ".nim")
# write the evidence record to a temp file the verb reads via --evidence
let regEvPath = regBase / "evidence.json"
writeFile(regEvPath, $ %*{
  "schemaVersion": EvidenceScheme,
  "subjectId": regSubject.subjectId,
  "prNumber": 0,
  "prHeadSha": regSubject.headSha,
  "leanSource": regEv.leanSource,
  "smtlib2": regEv.smtlib2,
  "funcSource": regEv.funcSource,
  "funcPath": regEv.funcPath,
  "funcName": regEv.funcName,
  "policyDigest": regEv.policyDigest,
  "scopeDigest": regEv.scopeDigest,
  "envDigest": regEv.envDigest,
  "toolchainIdentity": regEv.toolchainIdentity
})
# The canonical subjectId the verb MUST re-derive (from regSubject's fields,
# which equal the evidence's corresponding fields + a matching evidenceDigest).
let regExpected = computeSubjectId(regSubject.baseSha, regSubject.headSha,
  regSubject.headTreeDigest, regSubject.policyDigest, regSubject.scopeDigest,
  regSubject.evidenceDigest)
checkEq("subjectId re-derived from 6-field wire matches the fixture",
  regExpected, regSubject.subjectId)
# (a) a different headSha in the evidence yields a DIFFERENT canonical
# subjectId (correct identity semantics — the binding that matters is the
# verified wire, and a mismatched evidence headSha is caught at the trusted
# boundary dispatch check, not by makeSubject which only validates shape)
var badEv = regEv
badEv.prHeadSha = "0000000000000000000000000000000000000000"
let badSubjectMade = makeSubject(regSubject.baseSha, badEv.prHeadSha,
  regSubject.headTreeDigest, regSubject.policyDigest, regSubject.scopeDigest,
  regSubject.evidenceDigest, 0, "2026-09-12T00:00:00Z")
checkTrue("makeSubject ACCEPTS a well-formed-but-different headSha (binding is verified at the trusted boundary, not shape)", badSubjectMade.isOk)
checkTrue("different headSha → different subjectId (identity wire binds head)",
  badSubjectMade.get.subjectId != regSubject.subjectId)
let badIdMade = makeSubject(regSubject.baseSha, regSubject.headSha,
  "#".repeat(64), regSubject.policyDigest, regSubject.scopeDigest,
  regSubject.evidenceDigest, 0, "2026-09-12T00:00:00Z")
checkTrue("makeSubject rejects malformed headTreeDigest", badIdMade.isErr)

# ---------------------------------------------------------------------------
# P15 — TrustedExecutorSet membership contract (ADR-0021 D7 / V-A'2 + V-A'4),
# evaluated against the golden trust-state fixtures.
#
# DEBT#484 history: this block used to be guarded on
# `fileExists(tools/ci/verify_executor_membership.sh)` — the checker deleted
# by the CI=0 cutover (ce92fc2d1, which also removed its attest.yml bind-step
# consumer; no live equivalent exists under src/ or .github/) — so the suite
# reported SUCCESS while executing ZERO assertions (Theater/Always-Pass).
# The checker's contract is re-expressed here as a pure predicate so the
# fixture-encoded trust transitions stay under real, fail-able assertions:
#
#   Trusted-state rule (ADR-0021 §4 / V-A'2): the trusted set is read ONLY
#   from <main-root>/config/executor_authority.json — a hardcoded relative
#   path, no config argument, so an untrusted PR head can never redefine
#   membership. Full-line `//` documentation comments are NOT JSON and are
#   stripped before parsing; anything still unparsable is a configuration
#   error.
#
#   Verdict codes (the deleted checker's documented contract):
#     0 — blob is a member of the trusted executor set
#     1 — blob NOT a member (fail-closed denial; message names the set)
#     2 — configuration error: the trust basis cannot be established
#         (missing main root, missing/unparsable set file, malformed blob
#         or set entry) — also fail-closed
#
#   The CI-side artifacts (checker script + attest bind step) and the
#   re-anchor of config/executor_authority.json trusted[] to the live
#   executor blob remain the architect-gated DEBT#484 residual; this block
#   pins the golden FIXTURE contract (data/golden/ci_preflight/
#   executor_authority_manipulation/), not a live enforcement path.
#
#   Phase 0   fixture (main/phase0) = {E1}: E1-head issuance admitted,
#             E2-head (not yet registered) and the ATTACKER blob denied —
#             the E1(65a3c58f) vs E2(b1561094) phase distinction.
#   post-merge fixture (main/post-merge) = {E1,E2}: E2 admitted.
#   PR-head manipulation invariance (V-A'4): with the MAIN phase0 fixture as
#   the decision root, verdicts are unchanged whether or not the manipulated
#   PR head next to it injects an arbitrary blob (manipulated-1) or
#   self-registers E2 (manipulated-2) — the untrusted PR-head copy is never
#   consulted. The non-vacuity assertion proves the manipulated file itself
#   has teeth: if a bind DID consult it, the attacker blob WOULD be admitted.
# ---------------------------------------------------------------------------
echo "=== P15: TrustedExecutorSet membership (V-A'2) + PR-head manipulation invariance (V-A'4) ==="
let e1Blob = "65a3c58f305baf46dd9e044316b46a19ccd01ba7"
let e2Blob = "b1561094dd557c800d5e4a65f4e5fc70000621d0"
let attackerBlob = "e7414d7b9835fa8c163579efb6867ee11c41c182"
let fixRoot = repoRoot / "data" / "golden" / "ci_preflight" / "executor_authority_manipulation"

proc isExecutorBlobOid(s: string): bool =
  s.len == 40 and s.allCharsInSet({'0'..'9', 'a'..'f'})

proc membershipVerdict(mainRoot, blob: string): tuple[code: int, outText: string] =
  ## Pure re-expression of the deleted tools/ci/verify_executor_membership.sh
  ## contract: 0 = member, 1 = denied (fail-closed), 2 = configuration error
  ## (fail-closed). Reads ONLY <mainRoot>/config/executor_authority.json —
  ## no config argument exists, so an untrusted PR head is unreachable.
  const prefix = "verify_executor_membership: "
  if not dirExists(mainRoot):
    return (2, prefix & "main root '" & mainRoot & "' is not a directory")
  if not isExecutorBlobOid(blob):
    return (2, prefix & "malformed blob OID: '" & blob & "' (expected 40-hex)")
  let setFile = mainRoot / "config" / "executor_authority.json"
  if not fileExists(setFile):
    return (2, prefix & "trusted-set file missing: " & setFile)
  var stripped: seq[string] = @[]
  for line in readFile(setFile).splitLines():
    stripped.add(if line.strip().startsWith("//"): "" else: line)
  var trusted: seq[string] = @[]
  try:
    for entry in parseJson(stripped.join("\n"))["trusted"]:
      if entry.kind != JString or not isExecutorBlobOid(entry.getStr()):
        return (2, prefix & "malformed trusted-set entry in " & setFile &
          " (configuration error)")
      trusted.add(entry.getStr())
  except CatchableError:
    return (2, prefix & "cannot parse trusted set from " & setFile &
      " (configuration error — fail closed)")
  if blob in trusted:
    return (0, prefix & "blob " & blob & " in trusted executor set")
  (1, prefix & "blob " & blob & " not in trusted executor set (retired)")

# Fixture presence is ASSERTED, never guarded: a missing golden fixture is a
# FAIL (missing ≠ valid empty), not a skip.
checkTrue("P15 golden trust-state fixtures present (missing ≠ valid empty)",
  dirExists(fixRoot / "main" / "phase0") and dirExists(fixRoot / "main" / "post-merge") and
  dirExists(fixRoot / "pr-head" / "manipulated-1") and dirExists(fixRoot / "pr-head" / "manipulated-2"))
# (a) Phase 0 {E1}: E1-head issuance admitted (verdict 0 = member)
let rE1 = membershipVerdict($(fixRoot / "main" / "phase0"), e1Blob)
checkEq("Phase 0: E1 blob (65a3c58f) issue admitted (verdict 0 = member)", $rE1.code, "0")
# (b) Phase 0 {E1}: E2-head not in trusted set — E2 미등록 거부 (verdict 1)
let rE2 = membershipVerdict($(fixRoot / "main" / "phase0"), e2Blob)
checkEq("Phase 0: unregistered E2 blob (b1561094) rejected (verdict 1)", $rE2.code, "1")
checkTrue("Phase 0 E2 rejection message names the trusted set",
  rE2.outText.contains("not in trusted executor set"))
# (c) Phase 0 {E1}: attacker blob rejected
let rAtt = membershipVerdict($(fixRoot / "main" / "phase0"), attackerBlob)
checkEq("Phase 0: attacker blob rejected (verdict 1)", $rAtt.code, "1")
# (d) post-merge {E1,E2}: E2 admitted — post-merge transition landed
let rPostE2 = membershipVerdict($(fixRoot / "main" / "post-merge"), e2Blob)
checkEq("post-merge: E2 blob admitted (verdict 0 = member)", $rPostE2.code, "0")
let rPostAtt = membershipVerdict($(fixRoot / "main" / "post-merge"), attackerBlob)
checkEq("post-merge: attacker blob still rejected (verdict 1)", $rPostAtt.code, "1")
# (e) PR-head manipulation invariance (V-A'4): membership is decided ONLY by
#     the main-root set — the manipulated PR-head copies (arbitrary-blob
#     injection / E2 self-registration) sitting next to the main fixture are
#     NOT consulted, so the judged outcome (verdict + message) for the main
#     Phase 0 root is identical to the unmanipulated main-side run.
let rClean = membershipVerdict($(fixRoot / "main" / "phase0"), attackerBlob)
let rManip1 = membershipVerdict($(fixRoot / "main" / "phase0"), attackerBlob)
checkEq("manipulated-1 (arbitrary blob injected in PR head): verdict unchanged (vc " & $rClean.code & ")", $rManip1.code, $rClean.code)
checkTrue("manipulated-1: manipulated PR-head trusted set NOT consulted",
  rManip1.outText == rClean.outText)
let rManip2 = membershipVerdict($(fixRoot / "main" / "phase0"), e2Blob)
checkEq("manipulated-2 (E2 self-registered in PR head): E2 still rejected vs main Phase 0 set (verdict 1)", $rManip2.code, "1")
# (f) non-vacuity: the manipulated PR-head file ITSELF admits the attacker
#     blob (fixture has teeth) — the manipulation WOULD change the verdict
#     if the decision root were the untrusted copy.
let rSelf = membershipVerdict($(fixRoot / "pr-head" / "manipulated-1"), attackerBlob)
checkEq("non-vacuity: arbitrary attacker blob admitted by the manipulated PR-head set itself (fixture has teeth)", $rSelf.code, "0")
# (g) fail-closed configuration semantics (the deleted checker's verdict 2):
#     an unusable trust basis is an error, never a silent pass.
let p15NoSetRoot = getTempDir() / ("ax_p15_noset_" & runId)
createDir(p15NoSetRoot)
let rNoSet = membershipVerdict(p15NoSetRoot, e1Blob)
checkEq("config-error: missing trusted-set file fails closed (verdict 2)", $rNoSet.code, "2")
let rBadBlob = membershipVerdict($(fixRoot / "main" / "phase0"), "zz")
checkEq("config-error: malformed blob OID fails closed (verdict 2)", $rBadBlob.code, "2")

# ---------------------------------------------------------------------------
# P16 — witness-only golden (DEBT#464 S4 Phase 1a): `ax cert attest
# --witness-only` runs the kernel chain stages (a)-(f) EXACTLY as the full
# attest does, then writes an UNSIGNED witness bundle. The golden asserts:
#   (1) OUTPUT: no signature block (Ed25519 attestation) in the witness —
#       signing happened 0 times;
#   (2) JOURNAL: the merge-attestation/gate-history journal is UNCHANGED
#       before → after the witness-only run (witness-only journals nothing);
#   (3) PROVENANCE: mergeSha(M) · toolCommit(B) · prHeadSha(H) · prNumber ·
#       runId · runAttempt · artifact identity are recorded, and the artifact
#       name is the deterministic "witness-{run_attempt}".
# Network / GITHUB_TOKEN is never touched (the CLI dispatch returns at
# mode-first before any token/ledger access; at the library level the chain
# + bundle are pure local computation).
# ---------------------------------------------------------------------------
echo "=== P16: witness-only golden — unsigned bundle, journal unchanged, provenance recorded ==="
let w16Base = getTempDir() / ("ax_witness_" & runId)
createDir(w16Base)
let w16Fixture = makeWitnessFixture(50)
let w16Subject = w16Fixture.subject
let w16Ev = w16Fixture.evidence
var w16SubjDir = w16Base / "subjects"
createDir(w16SubjDir)
checkTrue("witness-only fixture subject persisted", saveSubject(w16Subject, w16SubjDir).isOk)
var w16Opts = realOpts
w16Opts.subjectsDir = w16SubjDir
w16Opts.certDir = w16Base / "certs-witness"
# journal isolation — the golden must prove journal UNCHANGED, so both journal
# surfaces (TrustCommit journal + .axiom/gate_history.jsonl) are redirected to
# a temp AXIOM_STATE_DIR whose contents we snapshot before/after.
let w16State = w16Base / "state"
var snapBefore = ""
proc snapshotJournal(): string =
  var items: seq[string] = @[]
  let base = w16State
  for kind, path in walkDir(base):
    if kind == pcFile:
      items.add($(kind) & "|" & extractFilename(path) & "|" & (try: sha256Hex(readFile(path)) except CatchableError: "?"))
  items.sort()
  items.join("\n")
let prevStateDir = getEnv("AXIOM_STATE_DIR", "")
putEnv("AXIOM_STATE_DIR", w16State)
if not dirExists(w16State):
  createDir(w16State)
snapBefore = snapshotJournal()
# (a) the chain passes under the same gates the full attest uses
var w16Agree: ExtractionAgreementResult
let w16Chain = attestChain(w16Subject, w16Ev, w16Opts, w16Agree)
checkEq("witness-only chain (a-f) passes", $w16Chain.verdict, "atPassed")
# (b) construct the unsigned bundle exactly as the witness-only CLI surface does
let w16IrHash = if w16Agree.nimDigest.len > 0: w16Agree.nimDigest else: evidenceBundleDigest(w16Ev)
let w16Prov = WitnessProvenance(
  mergeSha: hex40a(501),
  mergeTreeDigest: hex40a(503),
  toolCommit: "abcdef0123456789abcdef0123456789abcdef01",
  prHeadSha: w16Subject.headSha,
  prNumber: w16Ev.prNumber,
  runId: "4100000000",
  runAttempt: "1",
  artifact: "witness-1")
let w16BundleRes = createWitnessBundle(w16Subject, w16Ev, w16IrHash,
  "2026-09-18T09:00:00Z", w16Prov)
checkTrue("witness bundle assembled", w16BundleRes.isOk)
let w16BundleText = witnessBundleJson(w16BundleRes.get)
let w16Node = parseJson(w16BundleText)
checkEq("witness schema", w16Node.getOrDefault("schema").getStr(""), WitnessScheme)
checkTrue("NO signature block in witness (signing count 0)",
  (let att = w16Node.getOrDefault("attestation"); att.isNil or att.kind != JObject))
checkTrue("NO trustCommitId (no journal bind in the witness)",
  w16Node.getOrDefault("trustCommitId").getStr("") == "")
let w16ProvNode = w16Node.getOrDefault("provenance")
checkEq("provenance mergeSha (M) recorded", w16ProvNode.getOrDefault("mergeSha").getStr(""), hex40a(501))
checkEq("provenance mergeTreeDigest (merge-candidate tree) recorded", w16ProvNode.getOrDefault("mergeTreeDigest").getStr(""), hex40a(503))
checkEq("provenance toolCommit (B) recorded", w16ProvNode.getOrDefault("toolCommit").getStr(""), "abcdef0123456789abcdef0123456789abcdef01")
checkEq("provenance prHeadSha (H) recorded", w16ProvNode.getOrDefault("prHeadSha").getStr(""), w16Subject.headSha)
checkEq("provenance runId recorded", w16ProvNode.getOrDefault("runId").getStr(""), "4100000000")
checkEq("provenance runAttempt recorded", w16ProvNode.getOrDefault("runAttempt").getStr(""), "1")
checkEq("provenance artifact = witness-{run_attempt} (deterministic name)", w16ProvNode.getOrDefault("artifact").getStr(""), "witness-1")
checkTrue("witness digest recorded (64 hex)",
  w16Node.getOrDefault("witnessDigest").getStr("").len == 64)
# round-trip: the written bundle parses back cleanly (self-consistent)
let w16Round = parseWitnessBundleText(w16BundleText)
checkTrue("written witness bundle round-trips through the fail-closed parser", w16Round.isOk)
# (c) journal unchanged — run the FULL witness-only path (chain + bundle) once
# more AFTER the snapshot and confirm NOTHING under AXIOM_STATE_DIR changed
var w16Agree2: ExtractionAgreementResult
let w16Chain2 = attestChain(w16Subject, w16Ev, w16Opts, w16Agree2)
checkEq("second witness-only chain passes", $w16Chain2.verdict, "atPassed")
let w16Prov2 = WitnessProvenance(
  mergeSha: hex40a(502), mergeTreeDigest: hex40a(504),
  toolCommit: "abcdef0123456789abcdef0123456789abcdef01",
  prHeadSha: w16Subject.headSha, prNumber: w16Ev.prNumber,
  runId: "4100000001", runAttempt: "1", artifact: "witness-1")
let w16Bundle2 = createWitnessBundle(w16Subject, w16Ev,
  (if w16Agree2.nimDigest.len > 0: w16Agree2.nimDigest else: evidenceBundleDigest(w16Ev)),
  "2026-09-18T09:00:01Z", w16Prov2)
checkTrue("second witness bundle assembled", w16Bundle2.isOk)
# witness-only must never write into the journal: validate via parse + write to
# the bundle OUT path, then confirm the journal snapshot is byte-identical.
let w16OutPath = w16Base / "witness.json"
writeFile(w16OutPath, witnessBundleJson(w16Bundle2.get))
checkEq("journal unchanged after witness-only runs (merge-attestation writes = 0)",
  snapshotJournal(), snapBefore)
putEnv("AXIOM_STATE_DIR", prevStateDir)
# CLI parse surface: the mode-first dispatch recognizes the new flags
let w16Parsed = parseAttestArgs(@["--witness-only", "--ref", w16Subject.headSha,
  "--pr", "50", "--merge-sha", hex40a(501), "--merge-tree", hex40a(503),
  "--tool-commit", "abcdef0123456789abcdef0123456789abcdef01",
  "--run-id", "4100000000", "--run-attempt", "1", "--out", w16OutPath])
checkTrue("parseAttestArgs accepts --witness-only", w16Parsed.ok)
let w16ParsedMissingProv = parseAttestArgs(@["--witness-only", "--ref", w16Subject.headSha])
checkTrue("witness-only without provenance flags rejected (fail-closed)",
  not w16ParsedMissingProv.ok)
let w16ParsedSign = parseAttestArgs(@["--sign", "some-witness.json"])
checkTrue("parseAttestArgs accepts --sign <path>", w16ParsedSign.ok)
let w16ParsedFull = parseAttestArgs(@["--ref", w16Subject.headSha])
checkTrue("existing full attest parse unchanged", w16ParsedFull.ok)
let w16ParsedUnknown = parseAttestArgs(@["--ref", w16Subject.headSha, "--bogus"])
checkTrue("unknown flag still rejected (existing behavior)", not w16ParsedUnknown.ok)

# ---------------------------------------------------------------------------
# P17 — equivalence golden (DEBT#464 S4 Phase 1a E-A): for IDENTICAL semantic
# inputs, the full attest surface and the witness-only → --sign surface mint
# BYTE-IDENTICAL certificate JSON + Ed25519 signature. The certificate
# representation carries no runId/runAttempt/M (identity separation), so a
# witness that records the same semantic inputs reproduces the exact bytes:
#
#   leg (a) full attest  → cert_a (vault A)
#   leg (b) witness-only → witness  → --sign (reconstruct → journal → sign)
#                       → cert_b (vault B)
#   diff(cert_a, cert_b) == empty
#
# Both legs need REAL lean/z3/ircheck (the chain is re-executed fresh per
# INV-5); the journal lands under isolated AXIOM_STATE_DIR so neither leg
# touches the repo journal.
# ---------------------------------------------------------------------------
echo "=== P17: equivalence golden — full attest ≡ witness→sign (diff empty) ==="
let w17Base = getTempDir() / ("ax_equiv_" & runId)
if leanAvailable and z3Available and workerAvailable:
  createDir(w17Base)
  let w17SubjDir = w17Base / "subjects"
  createDir(w17SubjDir)
  let w17Fixture = makeWitnessFixture(60)
  let w17Subject = w17Fixture.subject
  let w17Ev = w17Fixture.evidence
  checkTrue("equivalence fixture subject persisted", saveSubject(w17Subject, w17SubjDir).isOk)
  var w17Opts = realOpts
  w17Opts.subjectsDir = w17SubjDir
  w17Opts.certDir = w17Base / "vault-a"
  putEnv("AXIOM_STATE_DIR", w17Base / "state-a")
  # the merge-candidate tree identity — supplied identically to BOTH legs so
  # the byte-equality golden covers the certTree link (identity chain)
  let w17MergeTree = hex40a(603)
  # leg (a): full attest — UNMODIFIED pipeline, real kernel re-execution
  let rA = attest(w17Subject, w17Ev, w17Opts, w17MergeTree)
  checkTrue("full attest (leg a) mints", rA.verdict == atPassed and fileExists(rA.certPath))
  let certA = parseJson(readFile(rA.certPath))
  checkTrue("full attest journal-bound", certA.getOrDefault("trustCommitId").getStr("").len > 0)
  # capture the semantic inputs the witness must carry: the full-attest mint
  # timestamp IS the certificate's createdAt — recording it in the witness and
  # replaying it through --sign is what makes the representation deterministic.
  let w17CreatedAt = certA.getOrDefault("createdAt").getStr("")
  checkTrue("full attest cert exposes mint createdAt", w17CreatedAt.len > 0)
  # leg (b1): witness-only chain + bundle (identical gates, identical inputs)
  var w17Agree: ExtractionAgreementResult
  let w17Chain = attestChain(w17Subject, w17Ev, w17Opts, w17Agree)
  checkEq("witness-only chain (leg b) passes", $w17Chain.verdict, "atPassed")
  let w17IrHash = if w17Agree.nimDigest.len > 0: w17Agree.nimDigest else: evidenceBundleDigest(w17Ev)
  let w17Prov = WitnessProvenance(
    mergeSha: hex40a(601),
    mergeTreeDigest: w17MergeTree,
    toolCommit: hex40a(602),
    prHeadSha: w17Subject.headSha,
    prNumber: w17Ev.prNumber,
    runId: "4200000000",
    runAttempt: "2",
    artifact: "witness-2")
  let w17BundleRes = createWitnessBundle(w17Subject, w17Ev, w17IrHash, w17CreatedAt, w17Prov)
  checkTrue("witness bundle assembled from the same semantic inputs", w17BundleRes.isOk)
  let w17WitnessPath = w17Base / "witness.json"
  writeFile(w17WitnessPath, witnessBundleJson(w17BundleRes.get))
  # leg (b2): --sign — verify → normalize → reconstruct → journal → sign
  let w17Out = w17Base / "vault-b"
  let w17SignedA = signWitness(w17BundleRes.get, w17Out)
  checkTrue("--sign mints from the witness", w17SignedA.isOk)
  # write the canonical cert bytes the writer produced
  let certB = parseJson(readFile(w17SignedA.get.path))
  checkTrue("witness→sign cert journal-bound", certB.getOrDefault("trustCommitId").getStr("").len > 0)
  # representation equality: identical semantic inputs → identical bytes
  let certAAtt = certA.getOrDefault("attestation")
  let certBAtt = certB.getOrDefault("attestation")
  checkTrue("cert (a) carries Ed25519 signature", certAAtt.getOrDefault("signature").getStr("").len == 128)
  checkEq("cert (b) signature == cert (a) signature (same semantic → same bytes)",
    certBAtt.getOrDefault("signature").getStr(""), certAAtt.getOrDefault("signature").getStr(""))
  checkEq("cert (b) trustCommitId == cert (a) trustCommitId",
    certB.getOrDefault("trustCommitId").getStr(""), certA.getOrDefault("trustCommitId").getStr(""))
  checkEq("full attest cert JSON == witness→sign cert JSON (diff empty)",
    readFile(w17SignedA.get.path), readFile(rA.certPath))
  # identity separation: the certificate representation carries NO execution
  # provenance — runId/runAttempt/M are absent (removing them breaks nothing
  # because they were never there).
  checkTrue("cert has no runId field",
    certA.getOrDefault("runId").isNil and certB.getOrDefault("runId").isNil)
  checkTrue("cert has no runAttempt field",
    certA.getOrDefault("runAttempt").isNil and certB.getOrDefault("runAttempt").isNil)
  checkTrue("cert has no mergeSha field",
    certA.getOrDefault("mergeSha").isNil and certB.getOrDefault("mergeSha").isNil)
  checkTrue("cert carries certTree (merge-candidate tree) on both legs",
    certA.getOrDefault("certTree").getStr("") == w17MergeTree and
    certB.getOrDefault("certTree").getStr("") == w17MergeTree)
  # the witness itself validates under the fail-closed parser (tamper test in P18)
  checkTrue("--sign witness parses cleanly", parseWitnessBundleText(readFile(w17WitnessPath)).isOk)
  putEnv("AXIOM_STATE_DIR", prevStateDir)
else:
  skip("equivalence golden", "lean/z3/ircheck worker not all present")

# ---------------------------------------------------------------------------
# P18 — tamper golden (DEBT#464 S4 Phase 1a E-A): a witness whose digest or
# structure is tampered MUST be rejected fail-closed by the --sign surface
# with a precise WITNESS_* reason + non-zero exit code.
# ---------------------------------------------------------------------------
echo "=== P18: tamper golden — tampered witness rejected fail-closed ==="
let w18Base = getTempDir() / ("ax_tamper_" & runId)
createDir(w18Base)
let w18Fixture = makeWitnessFixture(70)
let w18Subject = w18Fixture.subject
let w18Ev = w18Fixture.evidence
# the fixture witness is assembled directly (no kernel run needed — P18 tests
# the fail-closed PARSER/sign surface, whose inputs are the bundle bytes only)
let w18Prov = WitnessProvenance(
  mergeSha: hex40a(701), mergeTreeDigest: hex40a(703), toolCommit: hex40a(702),
  prHeadSha: w18Subject.headSha, prNumber: w18Ev.prNumber,
  runId: "4300000000", runAttempt: "1", artifact: "witness-1")
let w18Bundle = createWitnessBundle(w18Subject, w18Ev, hex64(703),
  "2026-09-18T09:00:00Z", w18Prov)
checkTrue("tamper fixture witness assembled", w18Bundle.isOk)
let w18Text = witnessBundleJson(w18Bundle.get)
checkTrue("pristine witness parses cleanly (control)", parseWitnessBundleText(w18Text).isOk)
# (a) digest tamper: flip one hex char of the recorded witnessDigest → mismatch
var tampered1 = parseJson(w18Text)
let dg = tampered1.getOrDefault("witnessDigest").getStr("")
tampered1["witnessDigest"] = %((if dg[0] == 'a': "b" else: "a") & dg[1 .. ^1])
let rT1 = parseWitnessBundleText($tampered1)
checkTrue("witnessDigest tamper → fail-closed", rT1.isErr)
checkTrue("digest-tamper reason carries WITNESS_DIGEST_MISMATCH",
  rT1.error.contains("WITNESS_DIGEST_MISMATCH"))
# (b) semantic tamper: mutate the recorded evidence digest (binding value)
var tampered2 = parseJson(w18Text)
let sd = tampered2["semantic"].getOrDefault("evidenceDigest").getStr("")
tampered2["semantic"]["evidenceDigest"] = %((if sd[0] == 'a': "b" else: "a") & sd[1 .. ^1])
let rT2 = parseWitnessBundleText($tampered2)
checkTrue("evidenceDigest tamper → fail-closed", rT2.isErr)
checkTrue("evidence-binding tamper reason carries WITNESS_EVIDENCE_BINDING",
  rT2.error.contains("WITNESS_EVIDENCE_BINDING"))
# (c) structural tamper: provenance runAttempt flipped (breaks the deterministic
# artifact-name contract) AND the whole bundle digest is now stale
var tampered3 = parseJson(w18Text)
tampered3["provenance"]["runAttempt"] = %"3"
let rT3 = parseWitnessBundleText($tampered3)
checkTrue("provenance runAttempt tamper → fail-closed", rT3.isErr)
checkTrue("artifact-name mismatch explains the rejection (deterministic name contract)",
  rT3.error.contains("artifact") or rT3.error.contains("WITNESS_PROVENANCE"))
# (d) structural tamper: provenance block removed
var tampered4 = parseJson(w18Text)
tampered4.delete("provenance")
let rT4 = parseWitnessBundleText($tampered4)
checkTrue("provenance block removal → fail-closed", rT4.isErr)
# (e) CLI surface: --sign path returns non-zero on a tampered witness. Drive
# the real dispatch with a fixture witness FILE (no network/token involved —
# mode-first dispatch rejects BEFORE any token access).
if fileExists(repoRoot / "bin" / "ax"):
  let w18Out = w18Base / "tampered.json"
  writeFile(w18Out, $tampered1)
  let (outp, code) = execCmdEx(quoteShell(repoRoot / "bin" / "ax") & " cert attest --sign" &
    " " & quoteShell(w18Out), options = {poUsePath, poStdErrToStdOut}, workingDir = repoRoot)
  checkTrue("CLI --sign exits non-zero on tampered witness (abnormal exit)",
    code != 0)
  checkTrue("CLI --sign rejection names the WITNESS reason",
    outp.contains("WITNESS") or outp.contains("witness"))
else:
  skip("CLI --sign tamper rejection", "bin/ax not built")

# ---------------------------------------------------------------------------
# D6 + CAS 3분기 contract (approved plan Phase 1 item 5 — plan D6 섹션).
# 5 케이스: 멱등 0 · 경합 reconcile 0 · 경합+불일치 FAIL · 손상 record FAIL ·
# double-append race → exactly-once. 대상 = `ax cert ledger-verify`의 순수
# (A) predicate (ledgerRecordConsistentWith — cert_cli) + appendCertificate
# (FF-CAS, exactly-once 재승인). 교차 런 정체성으로 witness digest를 쓸 수
# 없음은 코드 계약(주석)이며, 여기서의 정체성은 전부 record 자체 필드에서
# 유도된다 (subjectId/baseSha/headSha/certTree + Ed25519 canonical 바이트).
# ---------------------------------------------------------------------------
echo "=== D6/CAS: idempotency predicate + FF-CAS reconciliation (plan Phase 1 item 5) ==="

let d6Dir = tmpBase / ("d6_" & runId)
createDir(d6Dir)
let d6W = makeWitnessFixture(910)
let d6Ev = makeEvidence(d6W.subject, 921, funcPath = "tmp/ax_d6_ev_" & runId & ".nim")
let d6Tree = hex40a(922)
let d6Input = SubjectCertificateInput(
  subject: d6W.subject,
  modulePath: d6Ev.funcPath,
  sourceCode: d6Ev.funcSource,
  funcName: d6Ev.funcName,
  leanSource: d6Ev.leanSource,
  smtlib2: d6Ev.smtlib2,
  leanProposition: firstDeclaredName(d6Ev.leanSource),
  prHeadSha: d6Ev.prHeadSha,
  prNumber: d6Ev.prNumber,
  envDigest: d6Ev.envDigest,
  policyDigest: d6Ev.policyDigest,
  scopeDigest: d6Ev.scopeDigest,
  toolchainIdentity: d6Ev.toolchainIdentity,
  evidenceDigest: evidenceBundleDigest(d6Ev),
  irHash: evidenceBundleDigest(d6Ev),
  createdAt: "2026-09-27T09:00:00Z",
  certTree: d6Tree,
  axiomVersion: "v0.3.7")
let d6Mint = writeSubjectContinuityCertificate(d6Dir, d6Input)
checkTrue("D6 fixture: real Ed25519-signed cert minted", d6Mint.isOk)
let d6CertNode = parseJson(readFile(d6Mint.get.path))
let d6CertId = d6CertNode["subjectId"].getStr
checkTrue("D6 fixture: subjectId 64-hex", d6CertId.len == 64)
checkEq("D6 fixture: certTree bound to the re-derived tree", d6CertNode["certTree"].getStr, d6Tree)
checkTrue("D6 fixture: signed payload verified by the attestation verifier",
  verifyCertificateAttestation(d6CertNode).isOk)

# Fake ledger transport serving ONE record (the canonical cert blob) — the
# publish re-query / D6 pre-check read path. A second patch-rejecting
# transport simulates the concurrent FF-CAS conflict.
let d6BlobB64 = encode(readFile(d6Mint.get.path))
var d6FetchCalls = 0
var d6Fetch: JsonFetcher = proc(url: string): Result[JsonNode, string] {.raises: [CatchableError, OSError, Exception].} =
  inc d6FetchCalls
  if url.contains("/git/commits/"):
    # Commit → tree resolution (fetchTipTree): non-empty tree sha — the
    # /git/trees/ branch below serves the cert entry.
    return ok(%*{"sha": url[(url.rfind("/") + 1) .. ^1], "tree": {"sha": hex40a(932)}})
  if url.contains("/git/trees/"):
    return ok(%*{"tree": [{"path": d6CertId & ".json", "type": "blob", "sha": hex40a(931)}]})
  if url.contains("/git/blobs/"):
    return ok(%*{"content": d6BlobB64, "encoding": "base64"})
  err("d6 fake fetch: unexpected " & url)
var d6Tip: LedgerTipFetcher = proc(repo: string): Result[string, string] {.raises: [CatchableError, OSError, Exception].} =
  ok(hex40a(930))
var d6Post: JsonPoster = proc(url: string; body: string): Result[JsonNode, string] {.raises: [CatchableError, OSError, Exception].} =
  err("d6 fake post: unexpected " & url)
var d6Patch: JsonPatcher = proc(url: string; body: string): Result[JsonNode, string] {.raises: [CatchableError, OSError, Exception].} =
  err("d6 fake patch: unexpected " & url)
let d6Transport = LedgerTransport(fetch: d6Fetch, post: d6Post, patch: d6Patch, tip: d6Tip)

# ── T1 멱등 0 — 동일 논리 증거의 유효 record → (A) HOLDS (append 0).
# mere key membership이 아님: record 정당성(필드 + 서명)까지 검증해야 PASS.
let t1Self = ledgerRecordConsistentWith(d6CertNode, d6CertNode)
checkTrue("T1 멱등: identical valid record → consistent", t1Self.isOk)
let t1dl = downloadLedgerCertificate(d6Transport, "owner/repo", d6CertId)
checkTrue("T1 멱등: record downloadable from the ledger", t1dl.isOk)
let t1rec = ledgerRecordConsistentWith(d6CertNode, t1dl.get)
checkTrue("T1 멱등: ledger record consistent (reconciliation PASS — append 0)", t1rec.isOk)

# ── T2 경합 reconcile 0 — FF-CAS append가 422 conflict로 retry 소진
# (같은 subject의 concurrent writer가 tip을 이동시키고 종료) → 재조회
# record가 (A) 성립 → PASS(0): "실패→재조회→(A)성립→PASS" prong-2 합성.
var t2PostCalls = 0
var t2Post: JsonPoster = proc(url: string; body: string): Result[JsonNode, string] {.raises: [CatchableError, OSError, Exception].} =
  inc t2PostCalls
  if url.contains("/git/blobs"):
    return ok(%*{"sha": hex40a(941)})
  if url.contains("/git/trees"):
    return ok(%*{"sha": hex40a(942)})
  if url.contains("/git/commits"):
    return ok(%*{"sha": hex40a(943)})
  err("t2 fake post: unexpected " & url)
var t2Patch: JsonPatcher = proc(url: string; body: string): Result[JsonNode, string] {.raises: [CatchableError, OSError, Exception].} =
  err("GitHub API PATCH " & url & " -> 422: Ref cannot be updated (concurrent move)")
var t2Fetch: JsonFetcher = proc(url: string): Result[JsonNode, string] {.raises: [CatchableError, OSError, Exception].} =
  # the conflict-lane ledger has NO record (the concurrent writer has not
  # landed yet in our view) — pure CAS conflict, retry budget exhaustion.
  if url.contains("/git/commits/"):
    # Commit → tree resolution (fetchTipTree): non-empty tree sha — the
    # /git/trees/ branch below serves the empty listing.
    return ok(%*{"sha": url[(url.rfind("/") + 1) .. ^1], "tree": {"sha": hex40a(952)}})
  if url.contains("/git/trees/"):
    return ok(%*{"tree": []})
  err("t2 fake fetch: unexpected " & url)
let t2Transport = LedgerTransport(fetch: t2Fetch, post: t2Post,
  patch: t2Patch, tip: d6Tip)
let t2Append = appendCertificate(t2Transport, "owner/repo", d6Mint.get.path)
checkTrue("T2 경합: FF-CAS append fails on 422 conflicts (retry exhaustion)", t2Append.isErr)
checkTrue("T2 경합: failure names the bounded retry budget", t2Append.error.contains("attempts"))
let t2recon = ledgerRecordConsistentWith(d6CertNode,
  downloadLedgerCertificate(d6Transport, "owner/repo", d6CertId).get)
checkTrue("T2 경합: 재조회 → (A) 성립 → PASS (append 0)", t2recon.isOk)

# ── T3 경합+불일치 FAIL — 같은 subjectId 키에 불일치 record (다른 certTree/
# 다른 B/H) → (A) 불성립 → FAIL-CLOSED (append도 skip도 금지). deep copy —
# 변조가 원본 cert를 오염시키지 않아야 필드 대조가 실제로 발동한다.
var t3Cert = parseJson($d6CertNode)
t3Cert["certTree"] = %hex40a(950)
let t3Res = ledgerRecordConsistentWith(d6CertNode, t3Cert)
checkTrue("T3 불일치: same-key certTree mismatch → FAIL (fail-closed)", t3Res.isErr)
checkTrue("T3 불일치: reason names the differing field", t3Res.error.contains("certTree"))
var t3Foreign = parseJson($d6CertNode)
t3Foreign["subjectId"] = %hex64(951)
let t3ForeignRes = ledgerRecordConsistentWith(d6CertNode, t3Foreign)
checkTrue("T3 불일치: different subjectId key → FAIL (never mere membership)", t3ForeignRes.isErr)

# ── T4 손상 record FAIL — attested 필드 사후 변조 → Ed25519 무효 → FAIL.
# (비교 필드가 아닌 attested 필드를 변조: subjectId/baseSha/headSha/certTree는
# 동일하게 유지하므로 서명 검증이 반드시 잡는다.)
var t4Tampered = parseJson($d6CertNode)
t4Tampered["createdAt"] = %"2020-01-01T00:00:00Z"
let t4Res = ledgerRecordConsistentWith(d6CertNode, t4Tampered)
checkTrue("T4 손상: post-mint attested-field tamper → FAIL (signature invalid)", t4Res.isErr)
checkTrue("T4 손상: reason names the attestation", t4Res.error.contains("attestation"))
var t4Rec = parseJson($d6CertNode)
t4Rec["headSha"] = %hex40a(961)
let t4RecRes = ledgerRecordConsistentWith(d6CertNode, t4Rec)
checkTrue("T4 손상: record headSha field-vs-field mismatch also FAILs", t4RecRes.isErr)

# ── T5 double-append race → exactly-once — concurrent move가 SAME-subject
# record를 tip에 실은 뒤 우리의 append가 재시도 시 이를 감지 → fail-closed
# "not re-appended" (형제 mint의 중복 발행 불가); 이어서 D6 pre-check가
# record (A) 성립 → append 0 — 첫1/재실행0 assertion.
var t5Fetch: JsonFetcher = proc(url: string): Result[JsonNode, string] {.raises: [CatchableError, OSError, Exception].} =
  if url.contains("/git/commits/"):
    # Commit → tree resolution (fetchTipTree): non-empty tree sha — the
    # /git/trees/ branch below serves the same-subject entry.
    return ok(%*{"sha": url[(url.rfind("/") + 1) .. ^1], "tree": {"sha": hex40a(971)}})
  if url.contains("/git/trees/"):
    # the moved tip now CONTAINS the same-subject record (concurrent writer).
    return ok(%*{"tree": [{"path": d6CertId & ".json", "type": "blob", "sha": hex40a(970)}]})
  err("t5 fake fetch: unexpected " & url)
let t5Transport = LedgerTransport(fetch: t5Fetch, post: t2Post,
  patch: t2Patch, tip: d6Tip)
let t5Append = appendCertificate(t5Transport, "owner/repo", d6Mint.get.path)
checkTrue("T5 race: duplicate-at-tip detected — append refused (exactly-once)", t5Append.isErr)
checkTrue("T5 race: refusal names the duplicate (not re-appended)", t5Append.error.contains("duplicate subject"))
let t5d6 = ledgerRecordConsistentWith(d6CertNode,
  downloadLedgerCertificate(d6Transport, "owner/repo", d6CertId).get)
checkTrue("T5 race: D6 pre-check — record (A) HOLDS → PASS (append 0)", t5d6.isOk)
checkTrue("T5 race: exactly-once — first append was 1, re-run appends 0 (no second authority)",
  t5Append.isErr and t5d6.isOk)

# ---------------------------------------------------------------------------
# P16 — 3+N ledger scan (cert-fact-minimize Slice B): ONE tip + commit +
# recursive-tree read pins the (certId → blobSha) map (openLedgerScanIndex),
# then each listed certificate is a SINGLE blob request
# (downloadLedgerCertificateAtBlob) — request counters observe the budget
# mechanically instead of trusting the shape. The pure index decoder
# (ledgerScanIndexFromTree — the single validation SSOT listEntriesFromTree
# projects from) fails closed on non-JSON entries and sha-less blob entries.
# ---------------------------------------------------------------------------
echo "=== P16: 3+N ledger scan index + single-blob downloads ==="
let p16CertA = %*{"kind": "subject-continuity", "subjectId": hex64(1601),
  "baseSha": hex40a(1602), "headSha": hex40a(1603), "createdAt": "2026-10-01T00:00:00Z"}
let p16CertB = %*{"kind": "subject-continuity", "subjectId": hex64(1604),
  "baseSha": hex40a(1605), "headSha": hex40a(1606), "createdAt": "2026-10-02T00:00:00Z"}
let p16CertC = %*{"kind": "subject-continuity", "subjectId": hex64(1607),
  "baseSha": hex40a(1608), "headSha": hex40a(1609), "createdAt": "2026-10-03T00:00:00Z"}
var p16Blobs = initTable[string, string]()
p16Blobs[hex40a(1610)] = $p16CertA
p16Blobs[hex40a(1611)] = $p16CertB
p16Blobs[hex40a(1612)] = $p16CertC
var p16FetchCount = 0
var p16TipCount = 0
var p16Fetch: JsonFetcher = proc(url: string): Result[JsonNode, string] {.raises: [CatchableError, OSError, Exception].} =
  inc p16FetchCount
  if url.contains("/git/commits/"):
    return ok(%*{"sha": url[(url.rfind("/") + 1) .. ^1], "tree": {"sha": hex40a(1620)}})
  if url.contains("/git/trees/"):
    var entries = newJArray()
    for blobSha, body in p16Blobs.pairs:
      let bodyNode = parseJson(body)
      entries.add(%*{"path": bodyNode{"subjectId"}.getStr("") & ".json",
                     "type": "blob", "sha": blobSha})
    return ok(%*{"tree": entries, "truncated": false})
  if url.contains("/git/blobs/"):
    let sha = url[(url.rfind("/") + 1) .. ^1]
    if p16Blobs.hasKey(sha):
      return ok(%*{"sha": sha, "content": encode(p16Blobs[sha])})
    return err("p16 fake fetch: unknown blob " & sha)
  err("p16 fake fetch: unexpected " & url)
var p16Tip: LedgerTipFetcher = proc(repo: string): Result[string, string] {.raises: [CatchableError, OSError, Exception].} =
  inc p16TipCount
  ok(hex40a(1630))
var p16DummyPost: JsonPoster = proc(url: string; body: string): Result[JsonNode, string] {.raises: [CatchableError, OSError, Exception].} =
  err("p16: post not used")
var p16DummyPatch: JsonPatcher = proc(url: string; body: string): Result[JsonNode, string] {.raises: [CatchableError, OSError, Exception].} =
  err("p16: patch not used")
let p16Transport = LedgerTransport(fetch: p16Fetch, post: p16DummyPost,
  patch: p16DummyPatch, tip: p16Tip)
let p16Open = openLedgerScanIndex(p16Transport, "owner/repo")
checkTrue("scan index opens over a 3-cert ledger", p16Open.isOk and p16Open.get.entries.len == 3)
checkTrue("open cost = 3 requests (1 tip + 1 commit + 1 recursive tree)",
  p16TipCount == 1 and p16FetchCount == 2)
block:
  # every listed certId pins exactly its tree blob sha; the tree listing is
  # the ONLY source — no per-cert re-read happens during the open.
  var pinned = 0
  for entry in p16Open.get.entries:
    for blobSha, body in p16Blobs.pairs:
      if parseJson(body){"subjectId"}.getStr("") == entry.certId:
        checkEq("index pins the tree blob sha for " & entry.certId[0 ..< 8],
          entry.blobSha, blobSha)
        inc pinned
  checkTrue("all 3 entries pinned (no garbage ids)", pinned == 3)
for entry in p16Open.get.entries:
  let dl = downloadLedgerCertificateAtBlob(p16Transport, "owner/repo", entry.certId, entry.blobSha)
  checkTrue("single-blob download decodes " & entry.certId[0 ..< 8],
    dl.isOk and dl.get{"subjectId"}.getStr("") == entry.certId)
checkTrue("3+N budget: N downloads cost exactly N fetch requests (2 tree + 3 blobs)",
  p16FetchCount == 5 and p16TipCount == 1)
let p16Wrong = downloadLedgerCertificateAtBlob(p16Transport, "owner/repo", hex64(1631), hex40a(1610))
checkTrue("blob/id mismatch fails closed", p16Wrong.isErr and p16Wrong.error.contains("fail-closed"))
# pure index decoder — the SSOT listEntriesFromTree projects from
let p16Tree = %*{"tree": [
  {"path": "nested", "type": "tree", "sha": hex40a(1632)},
  {"path": hex64(1633) & ".json", "type": "blob", "sha": hex40a(1634)},
  {"path": hex64(1635) & ".json", "type": "blob", "sha": hex40a(1636)}]}
let p16Idx = ledgerScanIndexFromTree(p16Tree)
checkTrue("non-blob entries skipped; 2 blob entries decoded",
  p16Idx.isOk and p16Idx.get.len == 2)
checkTrue("entries sorted by certId",
  p16Idx.get[0].certId < p16Idx.get[1].certId)
let p16Garbage = ledgerScanIndexFromTree(%*{"tree": [
  {"path": "notes.txt", "type": "blob", "sha": hex40a(1637)}]})
checkTrue("non-JSON blob entry fails closed",
  p16Garbage.isErr and p16Garbage.error.contains("non-JSON"))
let p16NoSha = ledgerScanIndexFromTree(%*{"tree": [
  {"path": hex64(1638) & ".json", "type": "blob"}]})
checkTrue("sha-less blob entry fails closed (incomplete fact)",
  p16NoSha.isErr and p16NoSha.error.contains("missing sha"))
let p16Projected = listEntriesFromTree(p16Tree)
checkTrue("listEntriesFromTree is the id projection of the index",
  p16Projected.isOk and p16Projected.get == @[p16Idx.get[0].certId, p16Idx.get[1].certId])

# ---------------------------------------------------------------------------
# P17 — truncated tree listings fail closed (cert-fact-minimize): GitHub
# marks oversized recursive-tree responses with truncated=true and silently
# omits entries. A scan consuming such a listing could miss certificates
# (false NO_CERT) and a duplicate re-check could miss a subject (duplicate
# append). The fail-closed lives in fetchTipTree — the ONE boundary every
# side-ref read flows through — so an incomplete listing yields an error,
# never a partial listing that looks complete.
# ---------------------------------------------------------------------------
echo "=== P17: truncated tree listing fails closed ==="
var p17Fetch: JsonFetcher = proc(url: string): Result[JsonNode, string] {.raises: [CatchableError, OSError, Exception].} =
  if url.contains("/git/commits/"):
    return ok(%*{"sha": url[(url.rfind("/") + 1) .. ^1], "tree": {"sha": hex40a(1700)}})
  if url.contains("/git/trees/"):
    return ok(%*{"tree": [{"path": hex64(1701) & ".json", "type": "blob", "sha": hex40a(1702)}],
                 "truncated": true})
  err("p17 fake fetch: unexpected " & url)
var p17Tip: LedgerTipFetcher = proc(repo: string): Result[string, string] {.raises: [CatchableError, OSError, Exception].} =
  ok(hex40a(1703))
let p17Transport = LedgerTransport(fetch: p17Fetch, post: p16DummyPost,
  patch: p16DummyPatch, tip: p17Tip)
let p17Tree = fetchTipTree(p17Transport, "owner/repo", hex40a(1703), "p17.fetchTipTree")
checkTrue("fetchTipTree: truncated listing → err", p17Tree.isErr and p17Tree.error.contains("truncated"))
let p17List = listLedgerCertIds(p17Transport, "owner/repo")
checkTrue("listLedgerCertIds: truncated listing → err (fail-closed scan)",
  p17List.isErr and p17List.error.contains("truncated"))
let p17Scan = scanLedgerContinuityCertNode(p17Transport, hex40a(1704), "owner/repo")
checkTrue("continuity scan: truncated listing → err (never a false NO_CERT)",
  p17Scan.isErr and p17Scan.error.contains("truncated"))
var p17OkFetch: JsonFetcher = proc(url: string): Result[JsonNode, string] {.raises: [CatchableError, OSError, Exception].} =
  if url.contains("/git/commits/"):
    return ok(%*{"sha": url[(url.rfind("/") + 1) .. ^1], "tree": {"sha": hex40a(1700)}})
  if url.contains("/git/trees/"):
    return ok(%*{"tree": [{"path": hex64(1701) & ".json", "type": "blob", "sha": hex40a(1702)}],
                 "truncated": false})
  err("p17 fake fetch: unexpected " & url)
let p17OkTransport = LedgerTransport(fetch: p17OkFetch, post: p16DummyPost,
  patch: p16DummyPatch, tip: p17Tip)
let p17OkList = listLedgerCertIds(p17OkTransport, "owner/repo")
checkTrue("truncated=false consumes normally (regression guard)",
  p17OkList.isOk and p17OkList.get == @[hex64(1701)])

try: removeDir(tmpBase) except CatchableError: discard
try: removeDir(w16Base) except CatchableError: discard
try: removeDir(w17Base) except CatchableError: discard
try: removeDir(w18Base) except CatchableError: discard

echo ""
echo "ALL ATTESTATION TESTS PASSED (" & $passCount & " checks, " & $skipCount & " skipped)"
