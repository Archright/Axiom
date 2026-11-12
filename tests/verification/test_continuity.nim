## ═══════════════════════════════════════════════════════════════════════
## Continuity check — certification continuity Phase 5b tests
## (Cheap post-merge continuity: exact object-level `main tip == certified M
## OID` + certificate validity — contract §4.4 I-2, NOT full L2).
##
## Model B (Verdict B 2026-09-10): the pure predicate consumes a caller-
## resolved MainShape (mainSha/parent1/parent2/headTreeOid) and the cert's
## baseSha/headSha/headTreeDigest fields — no candidateCommit field exists
## anymore. A non-merge main (parent2 == "") is ccMismatch, never an error.
##
## The continuity verdict is SELF-CONTAINED (approved journal-free
## continuity predicate): inputs = main object + side-ref ledger certificate
## + CURRENT tracked policy/scope files ONLY. The trust journal
## (data/trusted/journal/) is an audit/forensic record only — it is NEVER
## consulted by the verdict, so a structurally valid, signed cert with
## matching OID + policy + scope yields ccPassed EVEN IF the journal
## directory is empty/missing.
##
## Coverage:
##   C1  pure verifyContinuity verdict table: no cert → ccNoCert (fail-closed
##       missing ≠ valid empty); valid signed cert + matching main → ccPassed;
##       main not a merge (parent2 == "") → ccMismatch; parents swapped →
##       ccMismatch; wrong tree → ccMismatch; tampered cert (signature
##       broken) → ccError; missing/wrong baseSha/headSha fields → ccError;
##       malformed kind/fields/OIDs → ccError
##   C2  I/O boundary verifyContinuityCert (journal-free): missing file →
##       ccNoCert; malformed JSON → ccError; valid JSON non-object → ccError;
##       **journal-free PASS** — a structurally valid, correctly signed cert
##       (fingerprint + identityDigest + attestation + current policy/scope
##       digests all matching) → ccPassed with the journal ABSENT
##   C3  journal-free fail-closed matrix: kind wrong → ccError; omitted
##       baseSha/headSha → ccError; tampered cert (post-sign field change) →
##       ccError; policyDigest mismatch (internally consistent cert) → ccError
##       (policyOk=false); scopeDigest mismatch → ccError (scopeOk=false)
##   C4  reason codes: CC_PASSED / CC_MISMATCH / CC_NO_CERT / CC_ERROR
## ═══════════════════════════════════════════════════════════════════════

import std/[json, os, strutils]
import core/crypto/hash_kernel
import core/results
import infrastructure/certificate_attestation
import verification/certificate_identity
import verification/continuity_check
import verification/subject_continuity_writer
import verification/verification_subject

var passCount = 0

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

proc checkVerdict(name: string; got, exp: ContinuityVerdict) =
  if got == exp:
    echo "  [PASS] ", name, " -> ", $got
    inc passCount
  else:
    echo "  [FAIL] ", name, "\n      got: ", $got, "\n      exp: ", $exp
    quit(1)

proc checkDetail(name: string; got: ContinuityCheckDetail; exp: ContinuityVerdict;
                 expMergeShape, expAncestry, expTree, expPolicy, expScope: bool) =
  if got.verdict == exp and got.mergeShapeOk == expMergeShape and
     got.ancestryOk == expAncestry and got.treeOk == expTree and
     got.policyOk == expPolicy and got.scopeOk == expScope:
    echo "  [PASS] ", name, " -> ", $got.verdict,
      " (mergeShapeOk=", $got.mergeShapeOk, " ancestryOk=", $got.ancestryOk,
      " treeOk=", $got.treeOk, " policyOk=", $got.policyOk,
      " scopeOk=", $got.scopeOk, ")"
    inc passCount
  else:
    echo "  [FAIL] ", name, "\n      got: ", $got.verdict,
      " mergeShapeOk=", $got.mergeShapeOk, " ancestryOk=", $got.ancestryOk,
      " treeOk=", $got.treeOk, " policyOk=", $got.policyOk,
      " scopeOk=", $got.scopeOk,
      "\n      exp: ", $exp, " mergeShapeOk=", $expMergeShape,
      " ancestryOk=", $expAncestry, " treeOk=", $expTree,
      " policyOk=", $expPolicy, " scopeOk=", $expScope
    quit(1)

# ── fixtures ─────────────────────────────────────────────────────────────

func hex40(n: uint64): string =
  ## Deterministic 40-lowercase-hex git-OID-shaped fixture (leading zeros
  ## included) — never used as a real OID, only as an identity token.
  result = newString(40)
  var v = n
  for i in countdown(39, 0):
    let d = v and 0xF'u64
    result[i] = "0123456789abcdef"[int(d)]
    v = v shr 4

proc signedContinuityCert(): JsonNode {.raises: [CatchableError].} =
  ## Minimal VALID subject-continuity certificate shape: kind + a real
  ## Ed25519 attestation block over the canonical payload (the same
  ## deterministic signing the attestation writer uses). No baseSha/headSha/
  ## headTreeDigest binding fields — the predicate must fail it (ccError).
  let node = %*{
    "kind": "subject-continuity",
    "schemaVersion": "axiom.certificate.v3",
    "status": "certGreen",
    "subjectId": hex40(9001) & hex40(9002)[0 .. 23]
  }
  let sig = signCertificatePayload(node)
  if sig.isErr:
    quit("fixture signature failed: " & sig.error)
  node["attestation"] = %*{
    "algorithm": AxiomAttestationAlgorithm,
    "publicKeyId": sig.get.publicKeyId,
    "signature": sig.get.signature
  }
  node

func baseShape(): MainShape =
  ## The observed main shape that matches the cert minted in this test:
  ## parent1/2 = baseSha/headSha fixtures, tree = sha256Hex(headTreeOid
  ## fixture) as the cert's headTreeDigest — the predicate compares
  ## sha256Hex(observed.headTreeOid) against cert.headTreeDigest.
  MainShape(mainSha: hex40(0xA11CE),
    parent1: hex40(0xBA5E),
    parent2: hex40(0xC0FFE),
    headTreeOid: hex40(0xD00D) & hex40(0xD00D)[0 .. 23])

func headTreeDigestShape(): string =
  ## The cert's headTreeDigest is sha256Hex(tree fixture) — the predicate
  ## hashes observed.headTreeOid, so this MUST be used as cert headTreeDigest.
  sha256Hex(hex40(0xD00D) & hex40(0xD00D)[0 .. 23])

proc policyDigestNow(): string =
  ## sha256 of the CURRENT tracked policy file (the same convention the
  ## journal-free predicate checks against). PROCs only — fileSha256Hex is
  ## an I/O side-effect.
  let p = fileSha256Hex("config/policy/merge_admission.json")
  if p.len == 0:
    quit("fixture: cannot read config/policy/merge_admission.json")
  p

proc scopeDigestNow(): string =
  let s = fileSha256Hex("data/verification_scope.lock")
  if s.len == 0:
    quit("fixture: cannot read data/verification_scope.lock")
  s

func evidenceDigestNow(): string =
  ## A stable 64-hex evidence digest for fixtures (identity wire field only).
  sha256Hex("continuity-test-evidence")

proc journalFreeSubjectCert(): JsonNode
    {.raises: [CatchableError].} =
  ## A structurally complete subject-continuity certificate WITHOUT any
  ## journal binding: fingerprint, identityDigest, policyDigest, scopeDigest,
  ## envDigest, treeDigest, baseSha and the Ed25519 attestation are all
  ## computed through the SAME canonical functions the writer uses
  ## (subject_continuity_writer subjectCertDigestSet/subjectCertCoreFields/
  ## subjectCertBindingFields/subjectCertIdentity + signCertificatePayload).
  ## The journal bind (trustCommitId + provenance + journalRef) is
  ## intentionally absent — the journal-free predicate must pass this cert
  ## with the journal directory EMPTY/MISSING.
  let shape = baseShape()
  let shapeHeadTree = headTreeDigestShape()
  let treeDigest = shapeHeadTree
  let baseSha = shape.parent1
  let headSha = shape.parent2
  let subjectMade = makeSubject(baseSha, headSha, treeDigest, policyDigestNow(),
    scopeDigestNow(), evidenceDigestNow(), 1, "2026-09-09T09:00:00Z")
  if subjectMade.isErr:
    quit("fixture subject failed: " & subjectMade.error)
  let input = SubjectCertificateInput(
    subject: subjectMade.get,
    modulePath: "src/verification/continuity_probe.nim",
    sourceCode: "func continuityProbe(a: int): int = a",
    funcName: "continuityProbe",
    leanSource: "theorem axiom_continuity_probe_sanity (x : Int) (r : Int)\n" &
      "  (h1 : r = if x * 2 > 100 then 0 else x * 2)\n" &
      "  (h2 : x * 2 > 100) : r = 0 := by\n  simp [h1, h2]\n",
    smtlib2: "(declare-const x Int)\n(declare-const r Int)\n(check-sat)\n",
    leanProposition: "axiom_continuity_probe_sanity",
    prHeadSha: headSha,
    prNumber: 1,
    envDigest: "a449b9d9bf193cfcba36771320e14da417b5fbbbcded95e088eb45db6b52fd49",
    policyDigest: policyDigestNow(),
    scopeDigest: scopeDigestNow(),
    toolchainIdentity: "nim-2.2.10|lean-4.33.0|z3-4.13.3",
    evidenceDigest: evidenceDigestNow(),
    irHash: "00f88a21f9211258ffa0b90003fb337c80a8cca0b7964b44b8c017920698e563",
    createdAt: "2026-09-09T23:15:15Z",
    axiomVersion: "test")
  let digests = subjectCertDigestSet(input)
  var node = subjectCertCoreFields(input, digests)
  let binding = subjectCertBindingFields(input)
  for key, value in binding.pairs:
    node[key] = value
  let attSig = signCertificatePayload(node)
  if attSig.isErr:
    quit("fixture signature failed: " & attSig.error)
  node["attestation"] = %*{
    "authority": "axiom",
    "policyVersion": "axiom.certificate.v3",
    "claimDigest": "sha256:" & sha256Hex(digests.claimJson),
    "algorithm": AxiomAttestationAlgorithm,
    "publicKeyId": attSig.get.publicKeyId,
    "signature": attSig.get.signature
  }
  node

func flipFirstHex(s: string): string =
  ## Deterministic single-hex-digit flip — keeps the value 64-char lowercase
  ## hex while guaranteeing a different digest.
  result = s
  result[0] = if result[0] == 'a': 'b' else: 'a'

func reSign(node: JsonNode): bool {.raises: [CatchableError].} =
  ## Re-sign a cert whose binding fields were legitimately changed (the
  ## policy/scope flip fixtures model an internally-consistent certificate
  ## minted with a different recorded digest — only the CURRENT-file
  ## comparison must fail, never the signature stage). Returns true on
  ## successful re-attestation.
  let attSig = signCertificatePayload(node)
  if attSig.isErr:
    return false
  node["attestation"] = %*{
    "authority": "axiom",
    "policyVersion": "axiom.certificate.v3",
    "claimDigest": node{"attestation"}{"claimDigest"}.getStr(""),
    "algorithm": AxiomAttestationAlgorithm,
    "publicKeyId": attSig.get.publicKeyId,
    "signature": attSig.get.signature
  }
  true

# ── C1: pure verdict table ────────────────────────────────────────────────

echo "=== C1: verifyContinuity verdict table (pure) ==="
let shape = baseShape()
let cert = signedContinuityCert()

checkVerdict("no certificate -> ccNoCert (fail-closed)",
  verifyContinuity(shape, nil), ccNoCert)
checkVerdict("present-but-empty cert object -> ccError (missing != valid empty)",
  verifyContinuity(shape, newJObject()), ccError)

# tamper: change ANY bound field AFTER signing → attestation must reject
let tampered = signedContinuityCert()
tampered["subjectId"] = %hex40(0xBAD)
checkVerdict("tampered cert (post-sign field change) -> ccError",
  verifyContinuity(shape, tampered), ccError)
let tamperedSig = signedContinuityCert()
tamperedSig["attestation"]["signature"] = %("00".repeat(64))
checkVerdict("tampered signature -> ccError",
  verifyContinuity(shape, tamperedSig), ccError)

# wrong kind / malformed identity
let foreign = %*{"kind": "verification", "status": "certGreen"}
checkVerdict("non-subject-continuity kind -> ccError",
  verifyContinuity(shape, foreign), ccError)

# cert missing the binding fields (baseSha/headSha/headTreeDigest) → ccError
checkVerdict("cert without baseSha/headSha binding fields -> ccError",
  verifyContinuity(shape, cert), ccError)

# malformed inputs
checkVerdict("uppercase main OID -> ccError",
  verifyContinuity(MainShape(mainSha: shape.mainSha.toUpperAscii, parent1: shape.parent1,
    parent2: shape.parent2, headTreeOid: shape.headTreeOid), cert), ccError)
checkVerdict("short main OID -> ccError",
  verifyContinuity(MainShape(mainSha: shape.mainSha[0 ..< 10], parent1: shape.parent1,
    parent2: shape.parent2, headTreeOid: shape.headTreeOid), cert), ccError)

# ── C1b: shape/ancestry/tree verdicts against the full cert ───────────────

echo "=== C1b: shape/ancestry/tree verdicts (full cert) ==="
let fullCert = journalFreeSubjectCert()

checkVerdict("exact merge shape match -> ccPassed",
  verifyContinuity(shape, fullCert), ccPassed)

let oidB = hex40(0xB0B0)           # a DIFFERENT (moved) main tip

# main not a merge commit: parent2 unresolvable → "" → ccMismatch
checkVerdict("non-merge main (parent2 == \"\") -> ccMismatch",
  verifyContinuity(MainShape(mainSha: shape.mainSha, parent1: shape.parent1,
    parent2: "", headTreeOid: ""), fullCert), ccMismatch)

# parents disagree with the cert (swapped / moved) → ccMismatch
checkVerdict("parent1 moved -> ccMismatch",
  verifyContinuity(MainShape(mainSha: shape.mainSha, parent1: oidB,
    parent2: shape.parent2, headTreeOid: shape.headTreeOid), fullCert), ccMismatch)
checkVerdict("parent2 moved -> ccMismatch",
  verifyContinuity(MainShape(mainSha: shape.mainSha, parent1: shape.parent1,
    parent2: oidB, headTreeOid: shape.headTreeOid), fullCert), ccMismatch)

# tree content binding violated → ccMismatch
checkVerdict("head tree mismatched -> ccMismatch",
  verifyContinuity(MainShape(mainSha: shape.mainSha, parent1: shape.parent1,
    parent2: shape.parent2, headTreeOid: oidB & oidB[0 .. 23]), fullCert), ccMismatch)

# ── C2: I/O boundary (journal-free — verdict needs NO journal) ────────────

echo "=== C2: verifyContinuityCert journal-free boundary ==="
let tmpDir = "tmp/continuity_test_" & $getCurrentProcessId()
if not dirExists(tmpDir):
  createDir(tmpDir)

checkVerdict("missing cert file -> ccNoCert (fail-closed)",
  verifyContinuityCert(shape, tmpDir / "nope.json"), ccNoCert)

let garbageFile = tmpDir / "garbage.json"
writeFile(garbageFile, "{not json")
checkVerdict("malformed JSON file -> ccError",
  verifyContinuityCert(shape, garbageFile), ccError)
let nonObjectFile = tmpDir / "non_object.json"
writeFile(nonObjectFile, "[]")
checkVerdict("valid JSON non-object file -> ccError",
  verifyContinuityCert(shape, nonObjectFile), ccError)

# A synthetically signed cert that carries NO identity fields (no
# baseSha/headSha/headTreeDigest) cannot pass the journal-free chain → ccError
# (missing identity != valid identity, fail-closed).
let certFile = tmpDir / "subject_continuity.json"
writeFile(certFile, $signedContinuityCert())
checkVerdict("identity-field-less signed cert -> ccError",
  verifyContinuityCert(shape, certFile), ccError)

# THE journal-free PASS: a structurally complete, correctly signed cert with
# matching OID + policy + scope yields ccPassed EVEN IF the journal
# directory is missing/empty — the verdict never consults the journal.
let fullCertFile = tmpDir / "subject_continuity_full.json"
writeFile(fullCertFile, $fullCert)

let journalPath = "data/trusted/journal"
let journalMoved = dirExists(journalPath)
if journalMoved:
  moveDir(journalPath, tmpDir / "journal_backup")
checkTrue("journal ABSENT → structurally valid cert still ccPassed",
  verifyContinuityCert(shape, fullCertFile) == ccPassed)
if journalMoved:
  moveDir(tmpDir / "journal_backup", journalPath)

# ── C3: journal-free fail-closed matrix (detailed verdicts) ───────────────

echo "=== C3: journal-free fail-closed matrix (detailed) ==="

# complete real cert passes with all per-stage booleans true
let fullDetail = verifyContinuityCertDetailed(shape, fullCertFile)
checkDetail("full journal-free chain -> ccPassed (all Ok)",
  fullDetail, ccPassed, true, true, true, true, true)

# Model B: mainSha is grammar-checked but binds NOTHING — the merge commit
# OID cannot be known at cert-mint time, so the tip moving while the
# ancestry (parent1/baseSha, parent2/headSha) and tree binding all still
# match the cert remains ccPassed (the certified INPUT state is intact).
let movedShape = MainShape(mainSha: oidB, parent1: shape.parent1,
  parent2: shape.parent2, headTreeOid: shape.headTreeOid)
let movedDetail = verifyContinuityCertDetailed(movedShape, fullCertFile)
checkDetail("tip moved but ancestry+tree intact -> ccPassed (Model B)",
  movedDetail, ccPassed, true, true, true, true, true)

# non-merge main (parent2 == "") → ccMismatch with mergeShapeOk=false
let nonMergeShape = MainShape(mainSha: shape.mainSha, parent1: shape.parent1,
  parent2: "", headTreeOid: "")
let nonMergeDetail = verifyContinuityCertDetailed(nonMergeShape, fullCertFile)
checkDetail("non-merge main -> ccMismatch (mergeShapeOk=false)",
  nonMergeDetail, ccMismatch, false, false, false, false, false)

# kind wrong → ccError
let wrongKindFile = tmpDir / "wrong_kind.json"
var wrongKind = parseJson($fullCert)     # fresh copy — JsonNode is a ref type
wrongKind["kind"] = %"verification"
writeFile(wrongKindFile, $wrongKind)
checkVerdict("wrong kind -> ccError (journal-free)",
  verifyContinuityCert(shape, wrongKindFile), ccError)

# baseSha omitted → ccError
let noBaseFile = tmpDir / "no_base.json"
var noBase = parseJson($fullCert)
delete(noBase, "baseSha")
writeFile(noBaseFile, $noBase)
checkVerdict("omitted baseSha -> ccError (journal-free)",
  verifyContinuityCert(shape, noBaseFile), ccError)

# headTreeDigest malformed → ccError
let badTreeFile = tmpDir / "bad_tree.json"
var badTree = parseJson($fullCert)
badTree["headTreeDigest"] = %"deadbeef"
writeFile(badTreeFile, $badTree)
checkVerdict("malformed headTreeDigest -> ccError (journal-free)",
  verifyContinuityCert(shape, badTreeFile), ccError)

# tampered cert (post-sign field change) → ccError — the Ed25519 stage
# rejects it BEFORE the policy/scope comparison, so the per-stage booleans
# stay false (nothing is trusted after a signature failure).
let tamperedFile = tmpDir / "tampered.json"
var tamperedCert = parseJson($fullCert)
tamperedCert["baseSha"] = %oidB
writeFile(tamperedFile, $tamperedCert)
let tamperedDetail = verifyContinuityCertDetailed(shape, tamperedFile)
checkDetail("tampered cert (post-sign field change) -> ccError",
  tamperedDetail, ccError, false, false, false, false, false)

# policyDigest mismatch → ccError with policyOk=false (machine-distinguishable).
# The cert is minted with a DIFFERENT recorded policyDigest but is internally
# consistent (valid signature): only the CURRENT-file comparison fails.
let policyFlipFile = tmpDir / "policy_flip.json"
let fullCertFlipPolicy = journalFreeSubjectCert()
fullCertFlipPolicy["policyDigest"] = %flipFirstHex(policyDigestNow())
doAssert reSign(fullCertFlipPolicy), "policy-flip fixture re-sign failed"
writeFile(policyFlipFile, $fullCertFlipPolicy)
let policyFlipDetail = verifyContinuityCertDetailed(shape, policyFlipFile)
checkDetail("policyDigest mismatch -> ccError (policyOk=false)",
  policyFlipDetail, ccError, true, true, true, false, true)

# scopeDigest mismatch → ccError with scopeOk=false
let scopeFlipFile = tmpDir / "scope_flip.json"
let fullCertFlipScope = journalFreeSubjectCert()
fullCertFlipScope["scopeDigest"] = %flipFirstHex(scopeDigestNow())
doAssert reSign(fullCertFlipScope), "scope-flip fixture re-sign failed"
writeFile(scopeFlipFile, $fullCertFlipScope)
let scopeFlipDetail = verifyContinuityCertDetailed(shape, scopeFlipFile)
checkDetail("scopeDigest mismatch -> ccError (scopeOk=false)",
  scopeFlipDetail, ccError, true, true, true, true, false)

# ── C4: reason codes ─────────────────────────────────────────────────────

echo "=== C4: continuity verdict reason codes ==="
checkEq("ccPassed -> CC_PASSED", continuityVerdictCode(ccPassed), "CC_PASSED")
checkEq("ccMismatch -> CC_MISMATCH", continuityVerdictCode(ccMismatch), "CC_MISMATCH")
checkEq("ccNoCert -> CC_NO_CERT", continuityVerdictCode(ccNoCert), "CC_NO_CERT")
checkEq("ccError -> CC_ERROR", continuityVerdictCode(ccError), "CC_ERROR")

# cleanup
for f in [certFile, garbageFile, nonObjectFile, fullCertFile, wrongKindFile,
          noBaseFile, badTreeFile, tamperedFile, policyFlipFile, scopeFlipFile]:
  try: removeFile(f) except CatchableError: discard
try: removeDir(tmpDir) except CatchableError: discard

echo ""
echo "continuity: ", passCount, " checks passed"
if passCount < 28:
  quit("expected >= 28 checks, got " & $passCount)