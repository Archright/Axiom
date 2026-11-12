import std/[json, os, strutils]
import core/crypto/hash_kernel
import core/deterministic_cas_key
import core/results
import verification/canonical_json
import verification/judgment_cas

## Judgment CAS execution-record unit tests — the append-only PASS/FAIL/UNKNOWN
## accounting surface and the reusable-PASS eligibility predicate (B/M/CAS
## execution–reuse separation, go-critical-lane hardening).
##
## Pure: no network, no Lean, no git — every identity member is synthetic hex.
## The tests pin:
##   * the record wire is canonical + content-addressed (id = sha256(wire)),
##   * the shape validator rejects wrong schema/subject/hex,
##   * reusable-PASS eligibility requires schemaVersion, verdict=PASS,
##     basis=EXECUTED, bound executed evidence, and the EXACT current identity
##     set — FAIL/UNKNOWN/old/incomplete records are never reusable,
##   * the append-only store never overwrites and refuses history mutation.

var failures = 0

proc expect(cond: bool; msg: string) =
  if cond:
    echo "  [PASS] " & msg
  else:
    inc failures
    echo "  FAIL: " & msg

proc expectReject(name: string; reason: string; needle: string) =
  ## "" reason = PASS; a rejection must contain `needle`.
  if reason.len > 0 and reason.contains(needle):
    echo "  [PASS] " & name
  else:
    inc failures
    echo "  FAIL: " & name & " — got '" &
      (if reason.len == 0: "<PASS>" else: reason) &
      "', expected rejection containing '" & needle & "'"

proc expectErr(name: string; res: Result[string, string]; needle: string) =
  if res.isErr and res.error.contains(needle):
    echo "  [PASS] " & name
  else:
    inc failures
    echo "  FAIL: " & name & " — got " &
      (if res.isErr: "err(" & res.error & ")" else: "ok(" & res.get & ")") &
      ", expected err containing '" & needle & "'"

proc hex64(seed: string): string =
  sha256Hex("jcas-exec-fixture:" & seed)

proc hex40(seed: string): string =
  sha256Hex("jcas-exec-oid:" & seed)[0 ..< 40]

proc currentIdentity(): JudgmentReuseIdentity =
  JudgmentReuseIdentity(
    schemaVersion: currentExecutionSchemaVersion(),
    executorTreeOid: hex40("B"),
    candidateTreeOid: hex40("M"),
    candidateHeadSha: hex40("Mhead"),
    overlayManifestDigest: hex64("overlay"),
    toolchainBundle: hex64("bundle"),
    contractVersion: EvidenceIdContractVersion)

proc passRecord(ident: JudgmentReuseIdentity): JudgmentExecutionRecord =
  JudgmentExecutionRecord(
    schemaVersion: currentExecutionSchemaVersion(),
    subject: "s1a",
    verdict: jevPass,
    basis: "EXECUTED",
    evidenceKey: hex64("key"),
    evidenceSha256: hex64("evidence"),
    identities: ident,
    observedAtUtc: "2026-10-20T00:00:00Z")

# ---------------------------------------------------------------------------
# Wire + content address
# ---------------------------------------------------------------------------
echo "[1] wire determinism + content address"
block:
  let r = passRecord(currentIdentity())
  let w1 = executionRecordWire(r)
  let w2 = executionRecordWire(r)
  expect w1 == w2, "wire is deterministic"
  expect w1 == canonicalJsonString(parseJson(w1)),
    "wire is canonical JSON (re-serialization is byte-identical)"
  expect executionRecordId(r) == sha256Hex(w1),
    "record id is sha256 of the wire"
  expect w1.contains("\"verdict\":\"PASS\""), "wire carries the PASS verdict"

# ---------------------------------------------------------------------------
# Shape validation
# ---------------------------------------------------------------------------
echo "[2] shape validator (fail-closed)"
block:
  var r = passRecord(currentIdentity())
  expect validateJudgmentExecutionRecord(r) == "", "valid record passes"
  r.schemaVersion = "axiom.judgment.cas.execution.v1"
  expectReject("old schemaVersion rejected",
    validateJudgmentExecutionRecord(r), "schemaVersion")
  r = passRecord(currentIdentity())
  r.subject = "not_a_subject"
  expectReject("unknown subject rejected",
    validateJudgmentExecutionRecord(r), "not a judgment subject")
  r = passRecord(currentIdentity())
  r.evidenceSha256 = "zz"
  expectReject("bad evidenceSha256 hex rejected",
    validateJudgmentExecutionRecord(r), "64 lowercase hex")
  r = passRecord(currentIdentity())
  r.identities.candidateTreeOid = hex64("too-long-for-tree-oid")
  expectReject("bad candidate tree OID length rejected",
    validateJudgmentExecutionRecord(r), "40 lowercase hex")

# ---------------------------------------------------------------------------
# Reusable-PASS eligibility — outcome gates
# ---------------------------------------------------------------------------
echo "[3] reusable-PASS eligibility — outcome gates"
block:
  let ident = currentIdentity()
  expect reusablePassRejection(passRecord(ident), ident) == "",
    "PASS+EXECUTED+evidence+exact identity IS reusable"
  var r = passRecord(ident)
  r.verdict = jevFail
  expectReject("FAIL verdict never reusable",
    reusablePassRejection(r, ident), "only PASS is reusable")
  r = passRecord(ident)
  r.verdict = jevUnknown
  expectReject("UNKNOWN verdict never reusable",
    reusablePassRejection(r, ident), "only PASS is reusable")
  r = passRecord(ident)
  r.basis = "REUSED"
  expectReject("REUSED basis never reusable (an adoption is not an execution)",
    reusablePassRejection(r, ident), "only an EXECUTED")
  r = passRecord(ident)
  r.basis = "OFF"
  expectReject("OFF basis never reusable",
    reusablePassRejection(r, ident), "only an EXECUTED")
  r = passRecord(ident)
  r.evidenceSha256 = ""
  expectReject("missing evidence binding never reusable",
    reusablePassRejection(r, ident), "evidenceSha256")
  r = passRecord(ident)
  r.evidenceKey = ""
  expectReject("missing evidence key never reusable",
    reusablePassRejection(r, ident), "evidenceKey")

# ---------------------------------------------------------------------------
# Reusable-PASS eligibility — the exact identity set
# ---------------------------------------------------------------------------
echo "[4] reusable-PASS eligibility — exact B/M/executor/overlay/toolchain/contract"
block:
  let ident = currentIdentity()

  proc mismatched(mutator: proc (x: var JudgmentExecutionRecord) {.raises: [].},
      label, needle: string) =
    var r = passRecord(ident)
    mutator(r)
    expectReject(label, reusablePassRejection(r, ident), needle)

  var r = passRecord(ident)
  r.schemaVersion = "axiom.judgment.cas.execution.v1"
  expectReject("old-generation record never reusable",
    reusablePassRejection(r, ident), "old-generation record")

  mismatched(proc (x: var JudgmentExecutionRecord) {.raises: [].} =
    x.identities.executorTreeOid = hex40("B2"),
    "executor tree (B) changed", "identity member")
  mismatched(proc (x: var JudgmentExecutionRecord) {.raises: [].} =
    x.identities.candidateTreeOid = hex40("M2"),
    "candidate tree (M) changed", "identity member")
  mismatched(proc (x: var JudgmentExecutionRecord) {.raises: [].} =
    x.identities.candidateHeadSha = hex40("Mhead2"),
    "candidate head changed", "identity member")
  mismatched(proc (x: var JudgmentExecutionRecord) {.raises: [].} =
    x.identities.overlayManifestDigest = hex64("overlay2"),
    "overlay changed", "identity member")
  mismatched(proc (x: var JudgmentExecutionRecord) {.raises: [].} =
    x.identities.toolchainBundle = hex64("bundle2"),
    "toolchain changed", "identity member")
  mismatched(proc (x: var JudgmentExecutionRecord) {.raises: [].} =
    x.identities.contractVersion = "evidence-id-contract.v0",
    "contract version changed", "identity member")

  # Empty identity members are mismatches, never a wildcard.
  var partial = passRecord(JudgmentReuseIdentity(
    schemaVersion: currentExecutionSchemaVersion(),
    executorTreeOid: "",
    candidateTreeOid: hex40("M"),
    candidateHeadSha: hex40("Mhead"),
    overlayManifestDigest: hex64("overlay"),
    toolchainBundle: hex64("bundle"),
    contractVersion: EvidenceIdContractVersion))
  expectReject("incomplete identity never reusable",
    reusablePassRejection(partial, ident), "identity member")

# ---------------------------------------------------------------------------
# Append-only store
# ---------------------------------------------------------------------------
echo "[5] append-only store"
block:
  let tmp = getTempDir() / "jcas-exec-store-" & $getCurrentProcessId()
  createDir(tmp)
  defer:
    removeDir(tmp)
  let r = passRecord(currentIdentity())
  let first = appendExecutionRecord(tmp, r)
  expect first.isOk, "first append succeeds"
  expect first.get.contains(JudgmentExecutionRecordsDir),
    "record lands under the append-only dir"
  expect fileExists(first.get), "record file exists"
  let again = appendExecutionRecord(tmp, r)
  expect again.isOk and again.get == first.get,
    "re-append of the same record is an idempotent no-op"

  # History mutation refusal: tamper with the stored bytes; a re-append of
  # the true record must fail closed (the wire is content-addressed — the
  # same record always has the same bytes, so diverging stored bytes =
  # recorded history mutated).
  var tampered = readFile(first.get)
  tampered = tampered.replace("\"verdict\":\"PASS\"", "\"verdict\":\"FAIL\"")
  writeFile(first.get, tampered)
  expectErr("tampered history append refused",
    appendExecutionRecord(tmp, r), "mutation refused")

  # A FAIL record appends fine (it is recorded history) but is never reusable.
  var failRec = passRecord(currentIdentity())
  failRec.verdict = jevFail
  let failPath = appendExecutionRecord(tmp, failRec)
  expect failPath.isOk, "FAIL record is appendable (append-only accounting)"
  expect failPath.get != first.get, "FAIL record has its own content address"

if failures == 0:
  echo "[OK] test_judgment_execution_records — all groups green"
  quit(0)
else:
  echo "[FAIL] test_judgment_execution_records — " & $failures & " failure(s)"
  quit(1)
