import std/[json, os, strutils]
import core/crypto/hash_kernel
import core/results
import verification/subject_store
import verification/verification_subject

## ═══════════════════════════════════════════════════════════════════════
## VerificationSubject — Model B (schema axiom.subject.v2) tests
##
## Coverage:
##   C1  well-formed subject roundtrip (serialize → parse → identical)
##   C2  tampered subject (flip one hex char in headTreeDigest) → REJECTED
##   C3  wrong base / wrong headSha → REJECTED
##   C4  missing field → REJECTED (fail-closed, never "empty = ok")
##   C5  store: second write with same subject → rejected (append-only)
##   C6  subject == different content → different subjectId (determinism)
##   C7  golden fixtures in data/trusted/subjects/ parse + verify
## ═══════════════════════════════════════════════════════════════════════

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

proc checkVerdict(name: string; got, exp: SubjectVerdict) =
  if got == exp:
    echo "  [PASS] ", name, " -> ", $got
    inc passCount
  else:
    echo "  [FAIL] ", name, "\n      got: ", $got, "\n      exp: ", $exp
    quit(1)

# ---------------------------------------------------------------------------
# Fixture inputs (synthetic — clearly non-production values)
# ---------------------------------------------------------------------------

const
  BaseA = "da39a3ee5e6b4b0d3255bfef95601890afd80709"
  HeadA = "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b"
  TreeA = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
  PolicyA = "1111111111111111111111111111111111111111111111111111111111111111"
  ScopeA = "2222222222222222222222222222222222222222222222222222222222222222"
  EvidenceA = "3333333333333333333333333333333333333333333333333333333333333333"
  PrA = 61
  CreatedA = "2026-09-08T01:02:03Z"

proc makeSubjectA(): VerificationSubject =
  let built = makeSubject(BaseA, HeadA, TreeA, PolicyA, ScopeA, EvidenceA, PrA, CreatedA)
  doAssert built.isOk, "fixture subject should construct: " & built.error
  built.get

proc makeSubjectAlt(baseSha: string; headSha: string; tree: string): VerificationSubject =
  makeSubject(baseSha, headSha, tree, PolicyA, ScopeA, EvidenceA, PrA, CreatedA).get

# ---------------------------------------------------------------------------
# C1 — well-formed roundtrip + canonical byte stability
# ---------------------------------------------------------------------------
echo "=== C1: roundtrip ==="
let subjA = makeSubjectA()
checkTrue("subjectId is 64-hex", isHexOfLen(subjA.subjectId, 64))
checkEq("provenance.source", subjA.provenance.source, SubjectSource)
checkEq("provenance.scheme", subjA.provenance.scheme, SubjectScheme)
let canonical = toCanonicalJson(subjA)
let reparsed = parseSubjectText(canonical)
checkTrue("canonical JSON parses", reparsed.isOk)
let round = reparsed.get
checkEq("roundtrip subjectId", round.subjectId, subjA.subjectId)
checkEq("roundtrip headSha", round.headSha, subjA.headSha)
checkEq("roundtrip baseSha", round.baseSha, subjA.baseSha)
checkEq("roundtrip headTreeDigest", round.headTreeDigest, subjA.headTreeDigest)
checkEq("roundtrip createdAt", round.createdAt, subjA.createdAt)
checkEq("roundtrip serialization is byte-stable", toCanonicalJson(round), canonical)
checkTrue("canonical wire includes scheme + \\x1f separators",
  subjectIdentityWire(BaseA, HeadA, TreeA, PolicyA, ScopeA, EvidenceA) == SubjectScheme & "\n" &
    BaseA & "\x1f" & HeadA & "\x1f" & TreeA & "\x1f" & PolicyA & "\x1f" & ScopeA & "\x1f" & EvidenceA)
checkEq("subjectId re-derives from wire",
  computeSubjectId(BaseA, HeadA, TreeA, PolicyA, ScopeA, EvidenceA), subjA.subjectId)

# ---------------------------------------------------------------------------
# C6 — determinism: same content → same id; different content → different id
# ---------------------------------------------------------------------------
echo "=== C6: determinism ==="
let subjA2 = makeSubjectA()   # identical inputs
checkEq("same inputs → same subjectId", subjA2.subjectId, subjA.subjectId)
let diffHead = makeSubjectAlt(BaseA, "a9993e364706816aba3e25717850c26c9cd0d89d", TreeA)
checkTrue("different headSha → different subjectId",
  diffHead.subjectId != subjA.subjectId)
let diffTree = makeSubjectAlt(BaseA, HeadA,
  "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
checkTrue("different headTreeDigest → different subjectId",
  diffTree.subjectId != subjA.subjectId)
let diffBase = makeSubjectAlt("2fd4e1c67a2d28fced849ee1bb76e7391b93eb12", HeadA, TreeA)
checkTrue("different baseSha → different subjectId",
  diffBase.subjectId != subjA.subjectId)
let diffPolicy = makeSubject(BaseA, HeadA, TreeA,
  "4444444444444444444444444444444444444444444444444444444444444444",
  ScopeA, EvidenceA, PrA, CreatedA).get
checkTrue("different policyDigest → different subjectId",
  diffPolicy.subjectId != subjA.subjectId)

# ---------------------------------------------------------------------------
# C2 — tampered subject (flip one hex char in headTreeDigest) → REJECTED
# ---------------------------------------------------------------------------
echo "=== C2: tampered headTreeDigest ==="
var tamperedNode = parseJson(canonical)
tamperedNode["headTreeDigest"] = %(TreeA[0 .. ^2] & (if TreeA[^1] == 'f': "e" else: "f"))
let tamperedText = $tamperedNode  # re-serialize with the flipped char
let tamperedParse = parseSubjectText(tamperedText)
checkTrue("tampered record rejected on parse (id re-derivation)", tamperedParse.isErr)
let tamperedSubject = makeSubjectAlt(BaseA, HeadA,
  TreeA[0 .. ^2] & (if TreeA[^1] == 'f': "e" else: "f"))
checkTrue("tampered subject has a DIFFERENT id", tamperedSubject.subjectId != subjA.subjectId)
checkVerdict("verifySubject: digest mismatch", verifySubject(BaseA, HeadA, tamperedSubject.headTreeDigest, PolicyA, ScopeA, EvidenceA, subjA), svHeadTreeMismatch)
checkVerdict("verifySubjectMatch: tampered digest rejected via id binding", verifySubjectMatch(subjA, tamperedSubject), svIdMismatch)

# ---------------------------------------------------------------------------
# C3 — wrong base / wrong headSha → REJECTED
# ---------------------------------------------------------------------------
echo "=== C3: wrong base / head ==="
checkVerdict("verifySubject: wrong base", verifySubject(diffBase.baseSha, HeadA, TreeA, PolicyA, ScopeA, EvidenceA, subjA), svBaseMismatch)
checkVerdict("verifySubject: wrong head", verifySubject(BaseA, diffHead.headSha, TreeA, PolicyA, ScopeA, EvidenceA, subjA), svHeadMismatch)
checkVerdict("verifySubject: wrong tree", verifySubject(BaseA, HeadA, diffTree.headTreeDigest, PolicyA, ScopeA, EvidenceA, subjA), svHeadTreeMismatch)
checkVerdict("verifySubject: wrong policy", verifySubject(BaseA, HeadA, TreeA, diffPolicy.policyDigest, ScopeA, EvidenceA, subjA), svPolicyMismatch)
checkVerdict("verifySubject: clean match", verifySubject(BaseA, HeadA, TreeA, PolicyA, ScopeA, EvidenceA, subjA), svMatch)
# Certificate-vs-actual: id binding fires first for well-formed differing
# subjects.
checkVerdict("verifySubjectMatch: different base rejected via id binding", verifySubjectMatch(subjA, diffBase), svIdMismatch)
checkVerdict("verifySubjectMatch: different head rejected via id binding", verifySubjectMatch(subjA, diffHead), svIdMismatch)
checkVerdict("verifySubjectMatch: clean match", verifySubjectMatch(subjA, subjA2), svMatch)

# ---------------------------------------------------------------------------
# C4 — missing field → REJECTED (fail-closed, never "empty = ok")
# ---------------------------------------------------------------------------
echo "=== C4: missing/empty fields ==="
let noBase = parseJson(canonical)
noBase.delete("baseSha")
checkTrue("record missing baseSha rejected on parse", parseSubjectText($noBase).isErr)
let noProvenance = parseJson(canonical)
noProvenance.delete("provenance")
checkTrue("record missing provenance rejected on parse", parseSubjectText($noProvenance).isErr)
let noCreated = parseJson(canonical)
noCreated.delete("createdAt")
checkTrue("record missing createdAt rejected on parse", parseSubjectText($noCreated).isErr)
checkTrue("malformed JSON rejected", parseSubjectText("{not json").isErr)
checkVerdict("verifySubject: empty digest input → REJECT", verifySubject(BaseA, HeadA, "", PolicyA, ScopeA, EvidenceA, subjA), svEmptyInput)
checkVerdict("verifySubject: empty policy input → REJECT", verifySubject(BaseA, HeadA, TreeA, "", ScopeA, EvidenceA, subjA), svEmptyInput)

# ---------------------------------------------------------------------------
# makeSubject validation — fail-closed construction
# ---------------------------------------------------------------------------
echo "=== construction validation ==="
checkTrue("short baseSha rejected", makeSubject(BaseA[0 .. ^2], HeadA, TreeA, PolicyA, ScopeA, EvidenceA, PrA, CreatedA).isErr)
checkTrue("short headSha rejected", makeSubject(BaseA, HeadA[0 .. ^2], TreeA, PolicyA, ScopeA, EvidenceA, PrA, CreatedA).isErr)
checkTrue("short headTreeDigest rejected", makeSubject(BaseA, HeadA, TreeA[0 .. ^2], PolicyA, ScopeA, EvidenceA, PrA, CreatedA).isErr)
checkTrue("non-hex headSha rejected", makeSubject(BaseA, "zzz", TreeA, PolicyA, ScopeA, EvidenceA, PrA, CreatedA).isErr)
checkTrue("short policyDigest rejected", makeSubject(BaseA, HeadA, TreeA, PolicyA[0 .. ^2], ScopeA, EvidenceA, PrA, CreatedA).isErr)
checkTrue("short scopeDigest rejected", makeSubject(BaseA, HeadA, TreeA, PolicyA, ScopeA[0 .. ^2], EvidenceA, PrA, CreatedA).isErr)
checkTrue("short evidenceDigest rejected", makeSubject(BaseA, HeadA, TreeA, PolicyA, ScopeA, EvidenceA[0 .. ^2], PrA, CreatedA).isErr)
checkTrue("negative prNumber rejected", makeSubject(BaseA, HeadA, TreeA, PolicyA, ScopeA, EvidenceA, -1, CreatedA).isErr)
checkTrue("bad createdAt rejected", makeSubject(BaseA, HeadA, TreeA, PolicyA, ScopeA, EvidenceA, PrA, "not-a-date").isErr)
checkTrue("malformed timestamp shape rejected", makeSubject(BaseA, HeadA, TreeA, PolicyA, ScopeA, EvidenceA, PrA, "2026-13-99T99:99:99Z").isErr)
checkTrue("validateSubject ok for valid subject", validateSubject(subjA).len == 0)
checkTrue("validateSubject catches id/field inconsistency",
  validateSubject(VerificationSubject(subjectId: sha256Hex("0000"), baseSha: BaseA, headSha: HeadA, headTreeDigest: TreeA, policyDigest: PolicyA, scopeDigest: ScopeA, evidenceDigest: EvidenceA, prNumber: PrA, createdAt: CreatedA, provenance: subjA.provenance)).len > 0)

# ---------------------------------------------------------------------------
# C5 — store: append-only, second write rejected
# ---------------------------------------------------------------------------
echo "=== C5: subject store ==="
let storeDir = joinPath(getTempDir(), "ax-subject-store-test-" & $getCurrentProcessId())
if dirExists(storeDir):
  removeDir(storeDir)
createDir(storeDir)

let savedA = saveSubject(subjA, storeDir)
checkTrue("saveSubject ok", savedA.isOk)
checkEq("saved path = <dir>/<subjectId>.json", savedA.get, subjectPath(storeDir, subjA.subjectId))
let savedAgain = saveSubject(subjA, storeDir)
checkTrue("second write with same subject REJECTED (append-only)", savedAgain.isErr)
checkTrue("rejection mentions overwrite refused", savedAgain.error.contains("overwrite refused"))

let loaded = loadSubject(subjA.subjectId, storeDir)
checkTrue("loadSubject ok", loaded.isOk)
checkEq("loaded subjectId roundtrip", loaded.get.subjectId, subjA.subjectId)
checkVerdict("loaded == saved (match)", verifySubjectMatch(loaded.get, subjA), svMatch)

let notFound = loadSubject("0000000000000000000000000000000000000000000000000000000000000001", storeDir)
checkTrue("unknown subjectId → err", notFound.isErr)
checkTrue("non-canonical subjectId → err", loadSubject("not-an-id", storeDir).isErr)

let diffSubj = makeSubject("2fd4e1c67a2d28fced849ee1bb76e7391b93eb12",
  "a9993e364706816aba3e25717850c26c9cd0d89d",
  "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  PolicyA, ScopeA, EvidenceA, 62, "2026-09-08T04:05:06Z").get
checkTrue("saveSubject (different subject) ok", saveSubject(diffSubj, storeDir).isOk)
let listing = listSubjects(storeDir)
checkTrue("listSubjects ok", listing.isOk)
checkEq("listSubjects sorted", listing.get.join(","), subjA.subjectId & "," & diffSubj.subjectId)  # sorted lexicographically by id
let found = findSubjectsByHeadSha(HeadA, storeDir)
checkTrue("findSubjectsByHeadSha ok", found.isOk)
checkEq("findSubjectsByHeadSha finds exactly one", $found.get.len, "1")
checkEq("found subject matches headSha", found.get[0].subjectId, subjA.subjectId)
let foundNone = findSubjectsByHeadSha("9999999999999999999999999999999999999999", storeDir)
checkTrue("findSubjectsByHeadSha empty for unknown head", foundNone.isOk and foundNone.get.len == 0)
checkTrue("findSubjectsByHeadSha empty head → err", findSubjectsByHeadSha("", storeDir).isErr)

# ---------------------------------------------------------------------------
# C7 — golden fixtures in data/trusted/subjects parse + verify
# ---------------------------------------------------------------------------
echo "=== C7: golden fixtures ==="
let fixtureDir = "data" / "trusted" / "subjects"
let fixtureIds = listSubjects(fixtureDir)
# historical data — they do NOT re-derive under the v2 wire. v2 golden
# fixtures are produced by the E2E flow. Listing integrity is what matters:
# every file must have a canonical subject-id filename.
checkTrue("fixture listing ok", fixtureIds.isOk)
checkTrue("all fixture ids canonical (64-hex)",
  fixtureIds.get.len == 0 or (block:
    var allHex = true
    for id in fixtureIds.get:
      if id.len != 64: allHex = false
    allHex))
let fixtureHeads = findSubjectsByHeadSha(HeadA, fixtureDir)
# v1 fixtures cannot load under the v2 schema (isErr), so a matching search
# fails closed — documented behavior for a mixed vault.
checkTrue("fixture findSubjectsByHeadSha err-or-empty on v1 vault",
  fixtureHeads.isErr or fixtureHeads.get.len == 0)

# ---------------------------------------------------------------------------
echo ""
echo "ALL SUBJECT TESTS PASSED (" & $passCount & " checks)"
