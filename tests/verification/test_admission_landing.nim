import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

## ═══════════════════════════════════════════════════════════════════════
## Admission Artifact — ADR-0022 implementation-② tests
## (Nim-layer pure semantics + injectable-transport ledger behavior).
##
## Coverage (golden-15 categories that are pure/replayable here):
##   G1  mintAdmissionPayload — merge-commit facts → canonical payload
##       (determinism: same facts → same canonical bytes)
##   G2  FF shape (PR #69 reproduction: single parent, headSha == C')
##       mint accepts landingParent1 == "" / explicit parent
##   G3  non-standard shape: landingParent1 missing for a merge-commit
##       candidate → FAIL (fail-closed)
##   G4  mint refuses: empty verdict / non-40-hex headSha / non-positive pr
##   G5  decodeExecutionIdentityClaims — full roundtrip claims; malformed
##       JWT (2 segments / bad base64url) → FAIL
##   G6  admissionPayloadDigest — canonical-bytes stable; object key order
##       cannot change the digest
##   G7  artifactExistsAtTip — same digest at tip tree → true (idempotent
##       no-op basis); different digest → false
##   G8  append semantics via fake transport: CAS append succeeds; duplicate
##       digest → caller-level no-op; concurrent non-FF move → fail-closed
##   G10 readAdmissionArtifact — roundtrip read; absent entry → FAIL
##   G11 root-only ledgers (empty tree): the f022abb1e empty-tree
##       normalization applied to admission reads — tip commit resolved to
##       its tree, EmptyTreeSha a positive EMPTY listing, and other tree
##       failures stay fail-closed (mirror of evidence-ledger Regression E9)
##
##   RETIRED 2026-10-07 (authority_contract.md §5.4 — GitHub required check +
##   merge queue is the authoritative acceptance; ref preserved, writer
##   removed): former G9 acceptLanding/readAcceptanceForLanding/rewind
##   cross-check tests of the canonical-acceptances ledger writer.
## ═══════════════════════════════════════════════════════════════════════

import std/[json, os, strutils, times]
import core/crypto/hash_kernel
import core/results
import verification/admission_artifact
import verification/ledger_side_ref
import verification/canonical_json

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

proc checkErr(name: string; r: Result[JsonNode, string]) =
  if r.isErr:
    echo "  [PASS] ", name, " -> err: ", r.error
    inc passCount
  else:
    echo "  [FAIL] ", name, " (expected err)"
    quit(1)

# ---------------------------------------------------------------------------
# Shared fixtures
# ---------------------------------------------------------------------------

const oidA = "1111111111111111111111111111111111111111"
const oidB = "2222222222222222222222222222222222222222"
const oidC = "3333333333333333333333333333333333333333"

proc baseFacts(): AdmissionMergeFacts =
  ## merge-commit shape: C' is a merge of headSha over evaluatedMainSha.
  AdmissionMergeFacts(
    verdict: AdmissionVerdictGo,
    reasonCode: "",
    prNumber: 69,
    headSha: oidA,
    landingCandidateSha: oidC,
    landingParent1: oidB,
    evaluatedMainSha: oidB,
    ledgerCertId: repeat('a', 64),
    evaluatedAt: "2026-09-13T00:00:00Z",
    runId: "12345678",
    runAttempt: "1")

# ---------------------------------------------------------------------------
# G1 — mint: merge-commit payload + determinism
# ---------------------------------------------------------------------------

let mergeFacts = baseFacts()
let p1 = mintAdmissionPayload(mergeFacts)
checkTrue("G1 mint merge-commit payload ok", p1.isOk)
let payload1 = p1.get
checkEq("G1 schemaVersion", payload1{"schemaVersion"}.getStr(), "axiom.admission.v1")
checkEq("G1 verdict", payload1{"verdict"}.getStr(), "mergeGo")
checkEq("G1 prNumber", $payload1{"prNumber"}.getInt(), "69")
checkEq("G1 headSha", payload1{"headSha"}.getStr(), oidA)
checkEq("G1 landingCandidateSha", payload1{"landingCandidateSha"}.getStr(), oidC)
checkEq("G1 landingParent1", payload1{"landingParent1"}.getStr(), oidB)
checkEq("G1 evaluatedMainSha", payload1{"evaluatedMainSha"}.getStr(), oidB)
checkEq("G1 ledgerCertId len", $payload1{"ledgerCertId"}.getStr().len, "64")
checkEq("G1 runId", payload1{"runId"}.getStr(), "12345678")
checkEq("G1 runAttempt", payload1{"runAttempt"}.getStr(), "1")
let p1again = mintAdmissionPayload(mergeFacts)
checkTrue("G1 mint deterministic", p1again.isOk and
  canonicalJsonString(p1again.get) == canonicalJsonString(payload1))

# ---------------------------------------------------------------------------
# G2 — FF shape (PR #69 reproduction: single parent, headSha == C')
# ---------------------------------------------------------------------------

let ffFacts = AdmissionMergeFacts(
  verdict: AdmissionVerdictGo,
  reasonCode: "",
  prNumber: 69,
  headSha: oidA,
  landingCandidateSha: oidA,   # FF: C' == headSha (head advanced straight in)
  landingParent1: oidB,
  evaluatedMainSha: oidB,
  ledgerCertId: repeat('b', 64),
  evaluatedAt: "2026-09-13T00:00:00Z",
  runId: "12345679",
  runAttempt: "1")
let ffP = mintAdmissionPayload(ffFacts)
checkTrue("G2 FF shape mint ok", ffP.isOk)
checkEq("G2 FF landingCandidateSha == headSha", ffP.get{"landingCandidateSha"}.getStr(), oidA)

# ---------------------------------------------------------------------------
# G3 — non-standard shape: merge-commit candidate without landingParent1
# ---------------------------------------------------------------------------

var badShape = baseFacts()
badShape.landingParent1 = ""
let p3 = mintAdmissionPayload(badShape)
checkTrue("G3 merge-commit without landingParent1 fails closed", p3.isErr)
checkTrue("G3 error names landingParent1", p3.error.contains("landingParent1"))

# ---------------------------------------------------------------------------
# G4 — mint input validation (fail-closed)
# ---------------------------------------------------------------------------

var emptyVerdict = baseFacts()
emptyVerdict.verdict = ""
checkTrue("G4 empty verdict fails", mintAdmissionPayload(emptyVerdict).isErr)
var badHead = baseFacts()
badHead.headSha = "xyz"
checkTrue("G4 non-hex headSha fails", mintAdmissionPayload(badHead).isErr)
var badPr = baseFacts()
badPr.prNumber = 0
checkTrue("G4 non-positive prNumber fails", mintAdmissionPayload(badPr).isErr)
var badRun = baseFacts()
badRun.runId = ""
checkTrue("G4 empty runId fails", mintAdmissionPayload(badRun).isErr)

# ---------------------------------------------------------------------------
# G5 — JWT claims decode
# ---------------------------------------------------------------------------

proc encodeBlob(s: string): string =
  ## base64 (standard, padded) for GitHub blob content.
  const tbl = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  var res = ""
  var i = 0
  while i < s.len:
    let b0 = ord(s[i])
    let b1 = if i + 1 < s.len: ord(s[i + 1]) else: 0
    let b2 = if i + 2 < s.len: ord(s[i + 2]) else: 0
    res.add(tbl[b0 shr 2])
    res.add(tbl[((b0 and 0x03) shl 4) or (b1 shr 4)])
    if i + 1 < s.len:
      res.add(tbl[((b1 and 0x0F) shl 2) or (b2 shr 6)])
    else:
      res.add('=')
    if i + 2 < s.len:
      res.add(tbl[b2 and 0x3F])
    else:
      res.add('=')
    i += 3
  res

proc b64url(s: string): string =
  ## base64url without padding (test helper).
  var res = ""
  var acc = 0
  var bits = 0
  const tbl = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
  for c in s:
    acc = (acc shl 8) or ord(c)
    bits += 8
    while bits >= 6:
      bits -= 6
      res.add(tbl[(acc shr bits) and 0x3F])
  if bits > 0:
    res.add(tbl[(acc shl (6 - bits)) and 0x3F])
  res

let claimsObj = %*{
  "iss": "token.actions.githubusercontent.com",
  "aud": "axiom-admission-v1",
  "repository": "Archright/Axiom",
  "workflow_ref": "Archright/Axiom/.github/workflows/auto_merge.yml@refs/heads/main",
  "workflow_sha": repeat('c', 40),
  "run_id": "12345678",
  "run_attempt": 1,
  "event_name": "workflow_run",
  "iat": 1770000000,
  "nbf": 1770000000,
  "exp": 1770003600,
  "jti": "jti-123"
}
let jwt = "header." & b64url($claimsObj) & ".signature"
let decoded = decodeExecutionIdentityClaims(jwt)
checkTrue("G5 decode ok", decoded.isOk)
checkEq("G5 iss", decoded.get.issuer, "token.actions.githubusercontent.com")
checkEq("G5 aud", decoded.get.audience, "axiom-admission-v1")
checkEq("G5 repository", decoded.get.repository, "Archright/Axiom")
checkEq("G5 workflow_ref", decoded.get.workflowRef,
  "Archright/Axiom/.github/workflows/auto_merge.yml@refs/heads/main")
checkEq("G5 workflow_sha", decoded.get.workflowSha, repeat('c', 40))
checkEq("G5 run_id", decoded.get.runId, "12345678")
checkEq("G5 event_name", decoded.get.eventName, "workflow_run")
checkTrue("G5 iat", decoded.get.iat == 1770000000)
checkTrue("G5 nbf", decoded.get.nbf == 1770000000)
checkEq("G5 jti", decoded.get.jti, "jti-123")
checkTrue("G5 malformed (2 segments) fails", decodeExecutionIdentityClaims("a.b").isErr)
checkTrue("G5 bad base64url fails", decodeExecutionIdentityClaims("a.%%%.c").isErr)

let identity = buildExecutionIdentity(decoded.get)
checkEq("G5 identity issu", identity{"issuer"}.getStr(), "token.actions.githubusercontent.com")
checkEq("G5 identity aud", identity{"aud"}.getStr(), "axiom-admission-v1")
checkEq("G5 identity run_id", identity{"run_id"}.getStr(), "12345678")

# ---------------------------------------------------------------------------
# G6 — payload digest: canonical-bytes stable
# ---------------------------------------------------------------------------

let d1 = admissionPayloadDigest(payload1)
checkTrue("G6 digest ok", d1.isOk)
checkEq("G6 digest len", $d1.get.len, "64")
# same payload from a differently-ordered object → identical canonical bytes
let reordered = %*{
  "runAttempt": "1",
  "runId": "12345678",
  "evaluatedAt": "2026-09-13T00:00:00Z",
  "ledgerCertId": repeat('a', 64),
  "evaluatedMainSha": oidB,
  "landingParent1": oidB,
  "landingCandidateSha": oidC,
  "headSha": oidA,
  "prNumber": 69,
  "reasonCode": "",
  "verdict": "mergeGo",
  "schemaVersion": "axiom.admission.v1"
}
let d2 = admissionPayloadDigest(reordered)
checkTrue("G6 key order independent", d2.isOk and d2.get == d1.get)

# ---------------------------------------------------------------------------
# G7-G9 — injectable transport ledger behavior
# ---------------------------------------------------------------------------

type FakeAdmBackend = ref object
  tip: string
  counter: int
  rejectPatch: bool
  treeEntries: seq[string]  # entry names present at tip tree
  chainEntries: seq[seq[string]]  # per-commit trees along the chain (rewind)
  commitParents: seq[string]  # parent sha per chain position
  blobContent: string  # base64 artifact bytes served by /git/blobs/
  chainCommits: seq[JsonNode]  # explicit commit graph (sha → tree.sha + parents)
  failTreeRead: bool  # force every /git/trees/ read to fail (fail-closed checks)

proc fakeAdmSha(prefix: string; b: FakeAdmBackend): string =
  inc b.counter
  let h = sha256Hex(prefix & $b.counter)
  h[0 ..< 40]

proc fakeAdmTransport(b: FakeAdmBackend): LedgerTransport =
  var fetch: JsonFetcher = proc(url: string): Result[JsonNode, string] {.raises: [CatchableError, OSError, Exception].} =
    if url.contains("/git/commits/"):
      let commitSha = url[(url.rfind("/") + 1) .. ^1]
      if b.chainCommits.len > 0:
        # Explicit commit graph (rewind scenarios): serve the matching node.
        for node in b.chainCommits:
          if node{"sha"}.getStr("") == commitSha:
            return ok(node)
        return err("GitHub API error for " & url & " -> 404: Not Found")
      # zero entries ⇔ empty tree (the ledger ROOT commit's tree — not a
      # fetchable object on GitHub; f022abb1e quirk fidelity).
      let treeSha = if b.treeEntries.len == 0: EmptyTreeSha else: fakeAdmSha("c", b)
      var parents = newJArray()
      for p in b.commitParents:
        parents.add(%*{"sha": p})
      ok(%*{"sha": commitSha, "tree": {"sha": treeSha}, "parents": parents})
    elif url.contains("/git/trees/"):
      if b.failTreeRead:
        return err("GitHub API error for " & url & " -> 500: fake tree read failure")
      var treeSha = url[(url.rfind("/") + 1) .. ^1]
      let q = treeSha.find('?')
      if q >= 0:
        treeSha = treeSha[0 ..< q]
      if treeSha == EmptyTreeSha:
        # quirk fidelity (observed 2026-10-06): the well-known empty tree is
        # NOT a materialized object — GitHub 404s this endpoint for it. A
        # call reaching here means the code under test failed to normalize.
        return err("GitHub API error for " & url & " -> 404: Not Found")
      if b.chainCommits.len > 0:
        # Explicit graph: only graph TREE shas are materialized; asking for a
        # commit sha as a tree 404s (the defect class this suite guards).
        var materialized = false
        for node in b.chainCommits:
          if node{"tree"}{"sha"}.getStr("") == treeSha:
            materialized = true
        if not materialized:
          return err("GitHub API error for " & url & " -> 404: Not Found")
      var entries = newJArray()
      for name in b.treeEntries:
        entries.add(%*{"path": name, "type": "blob", "sha": fakeAdmSha("t", b)})
      ok(%*{"tree": entries})
    elif url.contains("/git/blobs/"):
      # return a base64 artifact envelope so readAdmissionArtifact can decode
      ok(%*{"content": b.blobContent})
    else:
      err("fake fetch: unexpected " & url)
  var post: JsonPoster = proc(url: string; body: string): Result[JsonNode, string] {.raises: [CatchableError, OSError, Exception].} =
    if url.contains("/git/blobs"):
      ok(%*{"sha": fakeAdmSha("blob", b)})
    elif url.contains("/git/trees"):
      ok(%*{"sha": fakeAdmSha("tree", b)})
    elif url.contains("/git/commits"):
      ok(%*{"sha": fakeAdmSha("commit", b)})
    elif url.contains("/git/refs"):
      ok(%*{"sha": fakeAdmSha("ref", b)})
    else:
      err("fake post: unexpected " & url)
  var patch: JsonPatcher = proc(url: string; body: string): Result[JsonNode, string] {.raises: [CatchableError, OSError, Exception].} =
    if b.rejectPatch:
      return err("GitHub API PATCH " & url & " -> 422: Ref cannot be updated (non-fast-forward)")
    let bodyNode = parseJson(body)
    let newSha = bodyNode.getOrDefault("sha").getStr("")
    b.tip = newSha
    ok(%*{"ref": "refs/heads/axiom/admissions", "object": {"type": "commit", "sha": newSha}})
  var tip: LedgerTipFetcher = proc(repo: string): Result[string, string] {.raises: [CatchableError, OSError, Exception].} =
    ok(b.tip)
  LedgerTransport(fetch: fetch, post: post, patch: patch, tip: tip)

proc newFakeAdm(tip: string; rejectPatch: bool; treeEntries: seq[string]): FakeAdmBackend =
  FakeAdmBackend(tip: tip, counter: 0, rejectPatch: rejectPatch,
    treeEntries: treeEntries, chainEntries: @[], commitParents: @[], blobContent: "",
    chainCommits: @[], failTreeRead: false)

let tmpBase = getTempDir() / ("admission_test_" & $getCurrentProcessId())
createDir(tmpBase)

# G7 — artifactExistsAtTip
let bk = newFakeAdm("", false, @[d1.get & ".json"])
# tip must exist for the tree membership test
bk.tip = repeat('a', 40)
let t1 = fakeAdmTransport(bk)
let exists1 = artifactExistsAtTip(t1, "owner/repo", d1.get)
checkTrue("G7 same digest at tip tree → true", exists1.isOk and exists1.get)
let exists2 = artifactExistsAtTip(t1, "owner/repo", repeat('f', 64))
checkTrue("G7 absent digest → false", exists2.isOk and not exists2.get)

# G8 — append: CAS success then idempotent no-op (duplicate digest refused by caller)
let artifactEnvelope = %*{"payload": payload1, "executionIdentity": identity}
let artifactPath = tmpBase / "artifact.json"
writeFile(artifactPath, canonicalJsonString(artifactEnvelope))
let bk2 = newFakeAdm("", false, @[])
let t2 = fakeAdmTransport(bk2)
let app1 = appendAdmissionArtifact(t2, "owner/repo", artifactPath)
checkTrue("G8 append ok", app1.isOk)
checkTrue("G8 tip advanced", bk2.tip.len == 40)
# duplicate digest now at tip tree → exists (the fake backend mirrors the
# append by publishing the entry name, like a real ref tip would)
bk2.treeEntries = @[d1.get & ".json"]
let dupCheck = artifactExistsAtTip(t2, "owner/repo", d1.get)
checkTrue("G8 dup digest now visible at tip", dupCheck.isOk and dupCheck.get)
# concurrent non-FF move → fail-closed
let bk3 = newFakeAdm("", true, @[])
let t3 = fakeAdmTransport(bk3)
let conc = appendAdmissionArtifact(t3, "owner/repo", artifactPath)
checkTrue("G8 non-FF PATCH → fail-closed", conc.isErr)
checkTrue("G8 failure names ref update", conc.error.contains("ref update failed"))

# G10 — readAdmissionArtifact roundtrip
let bk7 = newFakeAdm("", false, @[])
let t7 = fakeAdmTransport(bk7)
let app7 = appendAdmissionArtifact(t7, "owner/repo", artifactPath)
checkTrue("G10 append for roundtrip ok", app7.isOk)
# treeEntries now must include the digest entry for the read; the fake serves
# treeEntries from the backend — append did NOT update it, so re-serve.
bk7.treeEntries = @[d1.get & ".json"]
bk7.tip = repeat('d', 40)
bk7.blobContent = encodeBlob(canonicalJsonString(artifactEnvelope))
let read7 = readAdmissionArtifact(t7, "owner/repo", "12345678", "1")
checkTrue("G10 read roundtrip ok", read7.isOk)
checkEq("G10 read payload runId", read7.get{"payload"}{"runId"}.getStr(), "12345678")
let readMissing = readAdmissionArtifact(t7, "owner/repo", "999", "1")
checkTrue("G10 absent entry fails closed", readMissing.isErr)

# ---------------------------------------------------------------------------
# G11 — root-only ledgers (empty tree): the f022abb1e empty-tree
# normalization applied to every admission tip-tree read
# ---------------------------------------------------------------------------

proc admCommitNode(sha, treeSha: string; parents: seq[string]): JsonNode =
  var parentArr = newJArray()
  for p in parents:
    parentArr.add(%*{"sha": p})
  %*{"sha": sha, "tree": {"sha": treeSha}, "parents": parentArr}

block:
  # Production regression (observed 2026-10-06, mirror of evidence E9): a
  # freshly rooted side ref's tip commit carries EmptyTreeSha, which GitHub
  # never serves as a fetchable tree — every tip-as-tree read 404'd,
  # fail-closing the caller's idempotency pre-check and every consult.
  let rootOnlyTip = repeat('e', 40)  # the ROOT commit — its tree is the empty tree
  let bk9 = newFakeAdm("", false, @[])
  bk9.tip = rootOnlyTip
  bk9.chainCommits = @[admCommitNode(rootOnlyTip, EmptyTreeSha, @[])]
  let t9 = fakeAdmTransport(bk9)
  let exists9 = artifactExistsAtTip(t9, "owner/repo", d1.get)
  checkTrue("G11 root-only artifactExistsAtTip → ok(false) (pre-check unblocked)",
    exists9.isOk and not exists9.get)
  # a consult on a root-only ref is a positive EMPTY listing — the failure
  # mode is "no entries" (fail-closed), never a transport 404
  let read9 = readAdmissionArtifact(t9, "owner/repo", "12345678", "1")
  checkTrue("G11 root-only readAdmissionArtifact fails closed with 'no artifact entries' (not a 404)",
    read9.isErr and read9.error.contains("no artifact entries"))
  # with the pre-check unblocked, the FIRST append on a root-only ref succeeds
  let app9 = appendAdmissionArtifact(t9, "owner/repo", artifactPath)
  checkTrue("G11 FIRST append on a root-only admissions ref succeeds: " &
    (if app9.isErr: app9.error else: "ok"), app9.isOk)
  checkTrue("G11 append tip == backend tip", app9.isOk and app9.get == bk9.tip)

# cleanup
try:
  removeDir(tmpBase)
except CatchableError:
  discard  # axiom:best-effort(test fixture cleanup — leftover tmp dir is harmless)

echo ""
echo "admission_landing: " & $passCount & " checks passed"
if passCount > 0:
  quit(0)
else:
  quit(1)
{.pop.}