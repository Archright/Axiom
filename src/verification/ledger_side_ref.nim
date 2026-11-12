import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

## Side-ref certificate ledger (certification-continuity Phase 4 — §4.3/INV-8).
##
## Append-only ledger on the OUT-OF-TREE side ref `refs/heads/axiom/
## certificates` — never part of the main tree (INV-8). Each append is one
## commit containing `<certId>.json` (the canonical certificate bytes of one
## subject-continuity certificate; certId = subjectId). The ref update is a
## fast-forward CAS: PATCH with force=false against the tip read moments
## earlier — a concurrent move makes the PATCH fail (422) and the append
## RETRIES on conflict (bounded: re-read tip → re-check subject uniqueness →
## rebuild on the moved tip → PATCH again, ≤ LedgerAppendMaxAttempts
## attempts), then FAILS CLOSED on exhaustion — no force, no overwrite, no
## duplicate entry (§8.2 REST git/refs).
##
## Object pipeline (Git Data API): blob (certificate bytes) → tree with the
## current tip as base_tree → commit with parent = tip → FF ref update.
## Transport is injectable (fetch/post/patch + tip reader); the live builders
## Live builders: liveFetcher/livePoster (bottom of this file).
## Journaling the `ledger-append` record is the caller's job (CLI boundary).

import std/[algorithm, json, os, strutils, httpclient, times]
import core/axiom_pragmas
import core/results
import verification/canonical_json
import infrastructure/logging_facade

axiomIoBoundary()

type
  JsonFetcher* = proc(url: string): Result[JsonNode, string] {.raises: [CatchableError, OSError, Exception].}
    ## Injectable GET transport. Live implementation converts every failure
    ## into an err Result; unit tests inject fakes that never raise.
  JsonPoster* = proc(url: string; body: string): Result[JsonNode, string] {.raises: [CatchableError, OSError, Exception].}
    ## Injectable POST transport (same convention as JsonFetcher).
  JsonPatcher* = proc(url: string; body: string): Result[JsonNode, string] {.raises: [CatchableError, OSError, Exception].}
    ## Injectable PATCH transport (same convention as JsonFetcher).
  LedgerTipFetcher* = proc(repo: string): Result[string, string] {.raises: [CatchableError, OSError, Exception].}
    ## Read the current ledger tip commit sha for a repo. ok("") = the side
    ## ref does not exist yet (first append must create it). ok(sha) = tip.

  LedgerTransport* = object
    fetch*: JsonFetcher
    post*: JsonPoster
    patch*: JsonPatcher
    tip*: LedgerTipFetcher

const
  LedgerRefName* = "refs/heads/axiom/certificates"
    ## The out-of-tree side ref (INV-8) — main tree never contains the ledger.
  AdmissionsRefName* = "refs/heads/axiom/admissions"
    ## Admission artifacts side ref (ADR-0022) — out of tree like the cert
    ## ledger; each append is one `<runId>-<runAttempt>.json` canonical
    ## admission payload.
    ## (The `refs/heads/axiom/canonical-acceptances` R(H) ledger constant was
    ## RETIRED 2026-10-07 — authority_contract.md §5.4; the ref itself is
    ## preserved, only the writer surface was removed.)
  GitHubApiBase* = "https://api.github.com"
  EmptyTreeSha* = "4b825dc642cb6eb9a060e54bf8d69288fbee4904"
    ## Well-known empty-tree OID — the ledger ROOT commit's tree.
  LedgerCommitMessagePrefix* = "axiom: certificate ledger append "
    ## Commit messages are provenance only — the git objects are the store.

func singleRefApiPath*(refName: string): string {.raises: [].} =
  ## Single-ref GET/PATCH endpoints take the ref WITHOUT the leading
  ## `refs/` prefix (e.g. `heads/axiom/certificates`), while ref-creation
  ## POST bodies keep the full `refs/heads/...` form. GitHub returns
  ## 404/422 for the doubled prefix (observed 2026-09-15:
  ## /git/ref/refs/heads/... -> 404; /git/ref/heads/... -> 200).
  if refName.startsWith("refs/"):
    refName[5 .. ^1]
  else:
    refName

func ledgerCertId*(node: JsonNode): Result[string, string] {.raises: [].} =
  ## certId = subjectId of a subject-continuity certificate (64 hex). Any
  ## other payload is not a ledger-able certificate (fail-closed).
  if node.isNil or node.kind != JObject:
    return err("ledger_side_ref: certificate is not a JSON object")
  if node.getOrDefault("kind").getStr("") != "subject-continuity":
    return err("ledger_side_ref: not a subject-continuity certificate (fail-closed)")
  let id = node.getOrDefault("subjectId").getStr("")
  if id.len != 64:
    return err("ledger_side_ref: subjectId must be 64 hex chars (fail-closed)")
  for c in id:
    if c notin {'0'..'9', 'a'..'f'}:
      return err("ledger_side_ref: subjectId must be 64 lowercase hex chars (fail-closed)")
  ok(id)

# ---------------------------------------------------------------------------
# Pure response decoders (fail-closed on missing fields)
# ---------------------------------------------------------------------------

func shaFromObject*(node: JsonNode): Result[string, string] {.raises: [].} =
  ## `{"object": {"sha": ...}}` (ref read/update responses).
  if node.isNil or node.kind != JObject:
    return err("ledger_side_ref: response is not an object")
  let sha = node{"object"}{"sha"}
  if sha.isNil or sha.kind != JString or sha.getStr().len == 0:
    return err("ledger_side_ref: response missing object.sha")
  ok(sha.getStr())

func shaFromNode*(node: JsonNode): Result[string, string] {.raises: [].} =
  ## `{"sha": ...}` (blob/tree/commit creation responses).
  if node.isNil or node.kind != JObject:
    return err("ledger_side_ref: response is not an object")
  let sha = node{"sha"}
  if sha.isNil or sha.kind != JString or sha.getStr().len == 0:
    return err("ledger_side_ref: response missing sha")
  ok(sha.getStr())

func ledgerScanIndexFromTree*(node: JsonNode): Result[seq[tuple[certId, blobSha: string]], string] {.raises: [].} =
  ## `{"tree": [{path, type, sha}...]}` → (certId, blobSha) pairs for every
  ## blob under the ledger ref, sorted by certId — the ONE listing decoder
  ## every tree consumer flows through (listEntriesFromTree is its id
  ## projection). Any entry that is not a "<64-hex>.json" blob, or a blob
  ## entry without a sha, is a ledger-integrity violation (fail-closed —
  ## garbage and sha-less entries are never silently skipped). The blob sha
  ## is what makes a 3+N scan possible: one recursive tree read pins the
  ## (path, blob sha) map, so each certificate afterwards is a single blob
  ## request (the append-only FF ledger never rewrites a listed entry).
  if node.isNil or node.kind != JObject:
    return err("ledger_side_ref: tree response is not an object")
  let tree = node{"tree"}
  if tree.isNil or tree.kind != JArray:
    return err("ledger_side_ref: tree response missing tree array")
  var entries: seq[tuple[certId, blobSha: string]] = @[]
  for entry in tree.getElems():
    if entry.kind != JObject:
      return err("ledger_side_ref: malformed tree entry (fail-closed)")
    let etype = entry.getOrDefault("type").getStr("")
    if etype != "blob":
      continue
    let path = entry.getOrDefault("path").getStr("")
    if not path.endsWith(".json"):
      return err("ledger_side_ref: non-JSON file in certificate ledger (fail-closed): " & path)
    let id = path[0 ..< path.len - ".json".len]
    if id.len != 64:
      return err("ledger_side_ref: non-canonical file in certificate ledger (fail-closed): " & path)
    for c in id:
      if c notin {'0'..'9', 'a'..'f'}:
        return err("ledger_side_ref: non-hex file in certificate ledger (fail-closed): " & path)
    let sha = entry.getOrDefault("sha")
    if sha.isNil or sha.kind != JString or sha.getStr().len == 0:
      return err("ledger_side_ref: blob entry missing sha for " & path & " (fail-closed)")
    entries.add((certId: id, blobSha: sha.getStr()))
  entries.sort()
  ok(entries)

func listEntriesFromTree*(node: JsonNode): Result[seq[string], string] {.raises: [].} =
  ## `{"tree": [{path, type, sha}...]}` → all blob paths under the ledger
  ## ref, as the id projection of ledgerScanIndexFromTree (single validation
  ## SSOT — fail-closed identically).
  let index = ledgerScanIndexFromTree(node)
  if index.isErr:
    return err(index.error)
  var ids: seq[string] = @[]
  for entry in index.get:
    ids.add(entry.certId)
  ok(ids)

func decodeBlobContent*(b64: string): Result[string, string] {.raises: [].} =
  ## Minimal base64 decoder for GitHub blob API content fields (same shape as
  ## cli/merge_cli.decodeBase64 — stdlib-free per house convention). Invalid
  ## length or non-alphabet input → err (fail-closed).
  const tbl = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  func val(c: char): int {.raises: [].} =
    let i = tbl.find(c)
    if i >= 0: i else: -1
  var decoded = ""
  var acc = 0
  var bits = 0
  for c in b64:
    if c == '\n' or c == '\r':
      continue
    if c == '=':
      break
    let v = val(c)
    if v < 0:
      return err("ledger_side_ref: invalid base64 character in blob content (fail-closed)")
    acc = (acc shl 6) or v
    bits += 6
    if bits >= 8:
      bits -= 8
      decoded.add(char((acc shr bits) and 0xFF))
  ok(decoded)

func blobEntrySha*(node: JsonNode; certId: string): Result[string, string] {.raises: [].} =
  ## Locate the `<certId>.json` blob entry in a recursive tree response and
  ## return its sha. Missing entry → err (the ledger never had this cert —
  ## caller decides; a missing sha on a present entry → err, fail-closed).
  if node.isNil or node.kind != JObject:
    return err("ledger_side_ref: tree response is not an object")
  let tree = node{"tree"}
  if tree.isNil or tree.kind != JArray:
    return err("ledger_side_ref: tree response missing tree array")
  let want = certId & ".json"
  for entry in tree.getElems():
    if entry.kind != JObject:
      return err("ledger_side_ref: malformed tree entry (fail-closed)")
    if entry.getOrDefault("type").getStr("") != "blob":
      continue
    if entry.getOrDefault("path").getStr("") != want:
      continue
    let sha = entry{"sha"}
    if sha.isNil or sha.kind != JString or sha.getStr().len == 0:
      return err("ledger_side_ref: blob entry missing sha for " & want & " (fail-closed)")
    return ok(sha.getStr())
  err("ledger_side_ref: certificate " & want & " not in ledger (fail-closed)")

# ---------------------------------------------------------------------------
# Read side — `ax cert ledger-list` basis (Phase 5 continuity consumption)
# ---------------------------------------------------------------------------

proc fetchTipTree*(transport: LedgerTransport; repo, tip, context: string): Result[JsonNode, string]
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Shared tip-tree reader for every side-ref read: resolves the tip COMMIT
  ## sha to its tree (GET /git/commits/<tip> → .tree.sha) and then reads that
  ## tree recursively (GET /git/trees/<treeSha>?recursive=1). GitHub's Git
  ## Data API does not serve a commit sha as a tree object, and the
  ## well-known empty tree (EmptyTreeSha — every ledger ROOT commit's tree)
  ## is not a materialized fetchable object at all (observed 2026-10-06:
  ## /git/trees/<root-commit-sha> and /git/trees/<EmptyTreeSha> both → 404,
  ## which fail-closed every FIRST append and every consult on a root-only
  ## ledger). A tip resolving to EmptyTreeSha is therefore normalized to a
  ## synthetic EMPTY listing ({"tree": []} — there are no entries by
  ## definition); a 404 on any other tree still fails closed. `context`
  ## prefixes every error so each caller keeps its own message identity.
  if repo.len == 0:
    return err(context & ": empty repo")
  if tip.len == 0:
    return err(context & ": empty tip (fail-closed)")
  let commitUrl = GitHubApiBase & "/repos/" & repo & "/git/commits/" & tip
  let commitResponse = transport.fetch(commitUrl)
  if commitResponse.isErr:
    return err(context & ": ledger commit read for tip " & tip & ": " & commitResponse.error)
  let treeSha = commitResponse.get{"tree"}{"sha"}
  if treeSha.isNil or treeSha.kind != JString or treeSha.getStr().len == 0:
    return err(context & ": commit response missing tree.sha for tip " & tip & " (fail-closed)")
  if treeSha.getStr() == EmptyTreeSha:
    return ok(%*{"tree": []})
  let treeUrl = GitHubApiBase & "/repos/" & repo & "/git/trees/" & treeSha.getStr() & "?recursive=1"
  let treeResponse = transport.fetch(treeUrl)
  if treeResponse.isErr:
    return err(context & ": ledger tree read for tip " & tip & ": " & treeResponse.error)
  # Truncated listings are never consumed: GitHub marks oversized tree
  # responses with truncated=true and silently omits entries — a side-ref
  # read built on it would be an INCOMPLETE fact (a scan could miss certs →
  # a false NO_CERT; a duplicate re-check could miss a subject → duplicate
  # append). Every side-ref read flows through this one boundary, so the
  # fail-closed lives here: the caller gets an error, never a partial
  # listing that looks complete.
  let truncated = treeResponse.get{"truncated"}
  if not truncated.isNil and truncated.kind == JBool and truncated.getBool():
    return err(context & ": tree listing truncated (fail-closed — an incomplete listing is never consumed as a complete fact)")
  ok(treeResponse.get)

proc listLedgerCertIds*(transport: LedgerTransport; repo: string): Result[seq[string], string]
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## All certificate ids on the side ref, sorted. Absent ledger ref = empty
  ## ledger (ok(@[])) — there is nothing to list yet.
  ## NOTE: certificate entries are strict "<64-hex>.json"; the general
  ## listRefEntryNames reuses the same tip-tree read without that restriction
  ## (admission entries are "<runId>-<runAttempt>.json" / "<H>.json").
  if repo.len == 0:
    return err("ledger_side_ref.listLedgerCertIds: empty repo")
  let tip = transport.tip(repo)
  if tip.isErr:
    return err("ledger_side_ref.listLedgerCertIds: " & tip.error)
  if tip.get.len == 0:
    return ok(newSeq[string]())
  let tree = fetchTipTree(transport, repo, tip.get, "ledger_side_ref.listLedgerCertIds")
  if tree.isErr:
    return err(tree.error)
  listEntriesFromTree(tree.get)

proc listRefEntryNames*(transport: LedgerTransport; repo, refName: string): Result[seq[string], string]
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## All blob entry paths under the given side ref, sorted. Absent ref =
  ## empty (ok(@[])). General admission reading surface (admissions ref);
  ## non-JSON entries fail closed.
  if repo.len == 0:
    return err("ledger_side_ref.listRefEntryNames: empty repo")
  let tip = transport.tip(repo)
  if tip.isErr:
    return err("ledger_side_ref.listRefEntryNames: " & tip.error)
  if tip.get.len == 0:
    return ok(newSeq[string]())
  let tree = fetchTipTree(transport, repo, tip.get, "ledger_side_ref.listRefEntryNames")
  if tree.isErr:
    return err(tree.error)
  var names: seq[string] = @[]
  for entry in tree.get{"tree"}.getElems():
    if entry.kind != JObject:
      return err("ledger_side_ref.listRefEntryNames: malformed tree entry (fail-closed)")
    if entry.getOrDefault("type").getStr("") != "blob":
      continue
    let path = entry.getOrDefault("path").getStr("")
    if not path.endsWith(".json"):
      return err("ledger_side_ref.listRefEntryNames: non-JSON entry in side ref (fail-closed): " & path)
    names.add(path)
  names.sort()
  ok(names)

type LedgerScanIndex* = object
  ## One opened scan over the certificate side ref: the tip it pinned plus
  ## the (certId → blobSha) map from the tip's recursive tree. The
  ## append-only FF ledger never rewrites a listed entry (same bytes ⇒ same
  ## blob sha), so the pinned map stays exact for every certId it lists even
  ## if the tip moves afterwards — new appends only ever ADD entries.
  tip*: string
  entries*: seq[tuple[certId, blobSha: string]]

proc openLedgerScanIndex*(transport: LedgerTransport; repo: string): Result[LedgerScanIndex, string]
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Open ONE scan over the certificate side ref: tip read + tip commit +
  ## recursive tree = 3 requests yield the full (certId → blobSha) map, so a
  ## scan of N certificates afterwards costs N single-blob requests (3+N
  ## total instead of 3+4N — the per-cert tip/commit/tree re-read that
  ## downloadLedgerCertificate performs is exactly the 3N waste). Absent ref
  ## = empty index (ok) — there is nothing to scan yet.
  if repo.len == 0:
    return err("ledger_side_ref.openLedgerScanIndex: empty repo")
  let tip = transport.tip(repo)
  if tip.isErr:
    return err("ledger_side_ref.openLedgerScanIndex: " & tip.error)
  if tip.get.len == 0:
    return ok(LedgerScanIndex(tip: "", entries: @[]))
  let tree = fetchTipTree(transport, repo, tip.get, "ledger_side_ref.openLedgerScanIndex")
  if tree.isErr:
    return err(tree.error)
  let index = ledgerScanIndexFromTree(tree.get)
  if index.isErr:
    return err("ledger_side_ref.openLedgerScanIndex: " & index.error)
  ok(LedgerScanIndex(tip: tip.get, entries: index.get))

proc fetchLedgerCertBlob(transport: LedgerTransport; repo, certId, blobSha, context: string): Result[JsonNode, string]
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## ONE blob request: blob sha → base64 content → decoded canonical JSON,
  ## with the ledgerCertId equality check (the stored object must BE the
  ## requested certificate). Fail-closed on unreadable blob, malformed
  ## base64/JSON, or an id mismatch — a read either yields the exact object
  ## or an error, never a partial/guessed certificate.
  let blobUrl = GitHubApiBase & "/repos/" & repo & "/git/blobs/" & blobSha
  let blobResponse = transport.fetch(blobUrl)
  if blobResponse.isErr:
    return err(context & ": " & blobResponse.error)
  let blob = blobResponse.get
  let content = blob{"content"}
  if content.isNil or content.kind != JString or content.getStr().len == 0:
    return err(context & ": blob response missing content (fail-closed)")
  let decoded = decodeBlobContent(content.getStr())
  if decoded.isErr:
    return err(context & ": " & decoded.error)
  var node: JsonNode
  try:
    node = parseJson(decoded.get)
  except CatchableError as e:
    return err(context & ": malformed certificate JSON: " & e.msg)
  let id = ledgerCertId(node)
  if id.isErr:
    return err(context & ": " & id.error)
  if id.get != certId:
    return err(context & ": ledger object id " & id.get &
      " != requested " & certId & " (fail-closed)")
  ok(node)

proc downloadLedgerCertificateAtBlob*(transport: LedgerTransport; repo, certId, blobSha: string): Result[JsonNode, string]
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Read ONE certificate by the blob sha pinned in a LedgerScanIndex (from
  ## openLedgerScanIndex): a SINGLE blob request — no tip/commit/tree
  ## re-read. Same fail-closed decode + validation as
  ## downloadLedgerCertificate (shared fetchLedgerCertBlob tail).
  if repo.len == 0 or certId.len == 0 or blobSha.len == 0:
    return err("ledger_side_ref.downloadLedgerCertificateAtBlob: empty repo, certId or blobSha")
  fetchLedgerCertBlob(transport, repo, certId, blobSha,
    "ledger_side_ref.downloadLedgerCertificateAtBlob")

proc downloadLedgerCertificate*(transport: LedgerTransport; repo, certId: string): Result[JsonNode, string]
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Read ONE certificate out of the side-ref ledger: tip → recursive tree →
  ## blob sha of <certId>.json → blob content (base64) → decoded canonical
  ## JSON. Fail-closed on absent ref, missing entry, unreadable blob,
  ## malformed base64/JSON — a ledger read either yields the exact object or
  ## an error, never a partial/guessed certificate.
  if repo.len == 0 or certId.len == 0:
    return err("ledger_side_ref.downloadLedgerCertificate: empty repo or certId")
  let tip = transport.tip(repo)
  if tip.isErr:
    return err("ledger_side_ref.downloadLedgerCertificate: " & tip.error)
  if tip.get.len == 0:
    return err("ledger_side_ref.downloadLedgerCertificate: ledger ref absent — no certificates (fail-closed)")
  let tree = fetchTipTree(transport, repo, tip.get, "ledger_side_ref.downloadLedgerCertificate")
  if tree.isErr:
    return err(tree.error)
  let blobSha = blobEntrySha(tree.get, certId)
  if blobSha.isErr:
    return err("ledger_side_ref.downloadLedgerCertificate: " & blobSha.error)
  fetchLedgerCertBlob(transport, repo, certId, blobSha.get,
    "ledger_side_ref.downloadLedgerCertificate")

# ---------------------------------------------------------------------------
# Write side — the ONLY mutation: FF-only append
# ---------------------------------------------------------------------------

proc createLedgerRoot*(transport: LedgerTransport; repo: string;
    refName: string = LedgerRefName): Result[string, string]
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Root the side ref on an empty-tree commit (called only when the tip read
  ## reported the ref absent). Ref-creation failure (422 = raced) fails closed.
  if repo.len == 0:
    return err("ledger_side_ref.createLedgerRoot: empty repo")
  let commitUrl = GitHubApiBase & "/repos/" & repo & "/git/commits"
  let commitResp = transport.post(commitUrl, $(%*{
    "message": "axiom: certificate ledger root",
    "tree": EmptyTreeSha,
    "parents": []}))
  if commitResp.isErr:
    return err("ledger_side_ref.createLedgerRoot: root commit create failed: " & commitResp.error)
  let rootSha = shaFromNode(commitResp.get)
  if rootSha.isErr:
    return err("ledger_side_ref.createLedgerRoot: " & rootSha.error)
  let refUrl = GitHubApiBase & "/repos/" & repo & "/git/refs"
  let refResp = transport.post(refUrl, $(%*{
    "ref": refName,
    "sha": rootSha.get}))
  if refResp.isErr:
    return err("ledger_side_ref.createLedgerRoot: ref create failed: " & refResp.error)
  ok(rootSha.get)

proc createLedgerObjects*(transport: LedgerTransport; repo, blobContent, baseTip, certId: string;
                          commitProvenance: string = ""): Result[string, string]
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Git Data API object pipeline for ONE append: blob → tree with
  ## base_tree = current tip → commit with parent = tip. Returns the commit
  ## sha. Fail-closed on every transport/response failure (a missing sha in
  ## any response is a malformed-response error, never a retry).
  ## commitProvenance (DEBT#464 S4) — optional provenance appended to the
  ## commit message (certificate-side provenance only; the git objects remain
  ## the store). Empty = legacy behaviour.
  let blobUrl = GitHubApiBase & "/repos/" & repo & "/git/blobs"
  let blobResponse = transport.post(blobUrl, $(%*{"content": blobContent}))
  if blobResponse.isErr:
    return err("blob create failed: " & blobResponse.error)
  let blobSha = shaFromNode(blobResponse.get)
  if blobSha.isErr:
    return err("blob response malformed: " & blobSha.error)
  let treeUrl = GitHubApiBase & "/repos/" & repo & "/git/trees"
  let treeResponse = transport.post(treeUrl, $(%*{
    "base_tree": baseTip,
    "tree": [{"path": certId & ".json", "mode": "100644", "type": "blob", "sha": blobSha.get}]}))
  if treeResponse.isErr:
    return err("tree create failed: " & treeResponse.error)
  let treeSha = shaFromNode(treeResponse.get)
  if treeSha.isErr:
    return err("tree response malformed: " & treeSha.error)
  let commitMessage = if commitProvenance.len > 0:
      LedgerCommitMessagePrefix & certId & " (" & commitProvenance & ")"
    else:
      LedgerCommitMessagePrefix & certId
  let commitUrl = GitHubApiBase & "/repos/" & repo & "/git/commits"
  let commitResponse = transport.post(commitUrl, $(%*{
    "message": commitMessage,
    "tree": treeSha.get,
    "parents": [baseTip]}))
  if commitResponse.isErr:
    return err("commit create failed: " & commitResponse.error)
  let commitSha = shaFromNode(commitResponse.get)
  if commitSha.isErr:
    return err("commit response malformed: " & commitSha.error)
  ok(commitSha.get)

const
  LedgerAppendMaxAttempts = 4
    ## Bounded retry-on-conflict budget for ONE appendCertificate call
    ## (PR-concurrent certificate minting): at most this many
    ## tip-read → uniqueness-re-check → object-build → FF-PATCH attempts.
    ## ONLY concurrent-move conditions are retried (HTTP 422 from the ref
    ## PATCH, or a raced root-ref create); every other failure fails closed
    ## immediately; exhaustion returns the last conflict error.

proc isRefConflictError(err: string): bool {.raises: [].} =
  ## Conflict predicate for the retry loop: HTTP 422 from a REST git ref
  ## transport = the ref moved concurrently (non-fast-forward PATCH rejected
  ## / ref-creation raced). The live transports render non-2xx as
  ## "GitHub API PATCH <url> -> 422: ..." — the "-> 422" marker is the
  ## contract. Every other failure (validation, auth, 5xx, malformed
  ## response, missing sha) is NOT a conflict and fails closed at once.
  "-> 422" in err

proc ledgerHasCertAtTip(transport: LedgerTransport; repo, tip, certId: string): Result[bool, string]
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Duplicate-subject re-check for a RETRY: does the ledger tip we are about
  ## to parent on already contain `<certId>.json`? Consumes the same data the
  ## workflow D6 predicate (ledgerHasSubjectCert → listLedgerCertIds) reads —
  ## the recursive tree of the tip. Any read failure fails closed: an
  ## unverifiable ledger is never appended to by a retry.
  let tree = fetchTipTree(transport, repo, tip, "duplicate re-check failed")
  if tree.isErr:
    return err(tree.error)
  let ids = listEntriesFromTree(tree.get)
  if ids.isErr:
    return err("duplicate re-check failed: " & ids.error)
  ok(ids.get.contains(certId))

proc appendCertificate*(transport: LedgerTransport; repo, certPath: string;
    refName: string = LedgerRefName; commitProvenance: string = ""): Result[string, string]
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Append ONE subject certificate to the side-ref ledger and return the NEW
  ## tip sha. Fail-closed at every step: unreadable/malformed/foreign cert,
  ## blob create failure, tree/commit failure, or a non-FF ref update — the
  ## caller journals the outcome; no partial ledger state is ever "ok".
  ##
  ## Bounded retry-on-conflict (PR-concurrent minting): the FF CAS PATCH can
  ## be rejected (HTTP 422) because a CONCURRENT mint moved the tip between
  ## our read and our update. The append then retries, up to
  ## LedgerAppendMaxAttempts attempts total: re-read the tip → re-check
  ## subject uniqueness against the NEW tip (a same-subject entry that landed
  ## with the moved tip is a duplicate — fail-closed, never re-appended) →
  ## rebuild the objects on the moved tip (the blob bytes are deterministic
  ## RFC-8785 canonical, so regeneration is idempotent) → PATCH with
  ## force=false again. Exhaustion returns the last conflict error. ONLY
  ## concurrent-move conditions retry — malformed cert, validation, auth and
  ## non-conflict transport errors fail immediately. The force=false
  ## fast-forward invariant is unchanged on every attempt: no lost update, no
  ## overwrite, no duplicate entry.
  ## commitProvenance (DEBT#464 S4) — optional provenance text (e.g.
  ## "M=<sha> run_id=<n> run_attempt=<n> artifact=<name> witness_sha256=<d>")
  ## appended to the commit message; the default (empty) preserves legacy
  ## behaviour exactly.
  if repo.len == 0 or certPath.len == 0:
    return err("ledger_side_ref.appendCertificate: empty repo or certPath")
  let text =
    try: readFile(certPath)
    except CatchableError as e:
      return err("ledger_side_ref.appendCertificate: certificate unreadable: " & e.msg)
  if text.len == 0:
    return err("ledger_side_ref.appendCertificate: certificate file is empty (fail-closed)")
  var node: JsonNode
  try:
    node = parseJson(text)
  except CatchableError as e:
    return err("ledger_side_ref.appendCertificate: malformed certificate JSON: " & e.msg)
  let certId = ledgerCertId(node)
  if certId.isErr:
    return err("ledger_side_ref.appendCertificate: " & certId.error)
  # Deterministic blob payload: RFC 8785 canonical certificate bytes.
  let blobContent = canonicalJsonString(node)
  var lastConflict = ""
  for attempt in 1 .. LedgerAppendMaxAttempts:
    # 1. current tip (or root the ref when it does not exist yet) — re-read
    #    on EVERY attempt so a retry parents on the moved tip.
    let tipRes = transport.tip(repo)
    if tipRes.isErr:
      return err("ledger_side_ref.appendCertificate: tip read failed: " & tipRes.error)
    var tip = tipRes.get
    if tip.len == 0:
      let rootRes = createLedgerRoot(transport, repo, refName)
      if rootRes.isErr:
        # raced root creation (two mints rooted simultaneously → the loser's
        # ref-create is rejected 422) = a conflict: next attempt re-reads the
        # tip, which now exists, and proceeds with a normal append.
        if "ref create failed" in rootRes.error and isRefConflictError(rootRes.error):
          lastConflict = rootRes.error
          continue
        return err("ledger_side_ref.appendCertificate: ledger root creation failed: " & rootRes.error)
      tip = rootRes.get
    # retry correctness: a retry parents on a tip we have not seen before. If
    # a SAME-subject entry arrived with the moved tip, appending again would
    # duplicate it (the workflow D6 predicate guarded the ORIGINAL tip only).
    # Re-check uniqueness against the tip we are about to parent on; a read
    # failure fails closed — an unverifiable ledger is never appended to.
    if attempt > 1:
      let dupRes = ledgerHasCertAtTip(transport, repo, tip, certId.get)
      if dupRes.isErr:
        return err("ledger_side_ref.appendCertificate: " & dupRes.error)
      if dupRes.get:
        return err("ledger_side_ref.appendCertificate: duplicate subject " & certId.get &
          " already present at ledger tip " & tip &
          " after concurrent move (fail-closed — not re-appended)")
    # 2-4. object pipeline: blob → tree(base=tip) → commit(parent=tip)
    let objects = createLedgerObjects(transport, repo, blobContent, tip, certId.get, commitProvenance)
    if objects.isErr:
      return err("ledger_side_ref.appendCertificate: " & objects.error)
    # 5. FF CAS ref update (force=false → concurrent move = rejected 422)
    let refUrl = GitHubApiBase & "/repos/" & repo & "/git/refs/" & singleRefApiPath(refName)
    let refResp = transport.patch(refUrl, $(%*{"sha": objects.get, "force": false}))
    if refResp.isErr:
      if isRefConflictError(refResp.error):
        lastConflict = refResp.error
        continue
      return err("ledger_side_ref.appendCertificate: ref update failed (non-FF / ref moved?): " &
        refResp.error)
    let updated = shaFromObject(refResp.get)
    if updated.isErr:
      return err("ledger_side_ref.appendCertificate: " & updated.error)
    return ok(updated.get)
  err("ledger_side_ref.appendCertificate: concurrent ledger append conflict after " &
    $LedgerAppendMaxAttempts & " attempts (last conflict error: " & lastConflict & ")")

{.pop.}

# ---------------------------------------------------------------------------
# Live transport builder (outside the pushed raises:[] scope — the closures
# perform real transport and declare the house exception set).
# ---------------------------------------------------------------------------
#
# Connection reuse: the closures of ONE liveLedgerTransport instance share a
# single HttpClient (SharedHttpClient). httpclient.request keeps the
# connection alive, so consecutive requests to the same host reuse the
# TCP+TLS connection instead of re-establishing it per request. The REQUEST
# STREAM is unchanged: same URLs, same headers (re-set per request), same
# serial order, same count. After any transport failure the pooled socket is
# dropped (dropConnection) so the next request re-dials from a clean state —
# the failure semantics of the old per-request-new-client transport.
# HttpClient is NOT thread-safe: closures are consumed serially (one scan
# pass = one connection; no concurrency is introduced).

type
  SharedHttpClient* = ref object
    ## One lazily-created HttpClient shared by every closure of a single
    ## live transport instance. `client` is nil until the first request so
    ## builder construction stays I/O-free (the documented liveXxx
    ## convention). Not thread-safe — serial consumption only.
    client: HttpClient

proc acquireClient(shared: SharedHttpClient): HttpClient
    {.raises: [CatchableError, OSError, Exception].} =
  ## First request creates the underlying client; every later call returns
  ## the same instance so requests reuse the keep-alive connection.
  if shared.client.isNil:
    shared.client = newHttpClient()
  shared.client

proc dropConnection(shared: SharedHttpClient)
    {.raises: [CatchableError, OSError, Exception].} =
  ## Close the pooled connection after a transport failure — the socket may
  ## hold a partially-read response, so the next request must re-dial from a
  ## clean state (no-op when the client was never created).
  if not shared.client.isNil:
    shared.client.close()

proc liveLedgerPatcher*(token: string; pooled: SharedHttpClient = nil): JsonPatcher =
  ## PATCH transport for the ref-update CAS (force=false), mirroring
  ## livePoster conventions: non-2xx → err with endpoint; an empty success
  ## body is malformed for a ref PATCH (fail-closed).
  let shared = if pooled.isNil: SharedHttpClient() else: pooled
  return proc(url: string; body: string): Result[JsonNode, string] {.raises: [CatchableError, OSError, Exception].} =
    let client = acquireClient(shared)
    client.headers = newHttpHeaders([
      ("Authorization", "Bearer " & token),
      ("Accept", "application/vnd.github.v3+json"),
      ("Content-Type", "application/json")])
    try:
      let resp = client.request(url, httpMethod = HttpPatch, body = body)
      if resp.code.int div 100 != 2:
        return err("GitHub API PATCH " & url & " -> " & $resp.code & ": " &
                   resp.body[0 .. min(199, resp.body.len - 1)])
      if resp.body.len == 0:
        return err("GitHub API PATCH " & url & " -> empty body (fail-closed)")
      try:
        ok(parseJson(resp.body))
      except CatchableError as e:
        return err("GitHub API response parse error for " & url & ": " & e.msg)
    except CatchableError as e:
      dropConnection(shared)
      return err("GitHub API PATCH error for " & url & ": " & e.msg)

proc liveLedgerTipReader*(token: string; refName: string = LedgerRefName;
    pooled: SharedHttpClient = nil): LedgerTipFetcher =
  ## Tip reader for the side ref: 404 = ref absent (first append must root
  ## it, ok("")); any other non-2xx or malformed response → err (fail-closed).
  let shared = if pooled.isNil: SharedHttpClient() else: pooled
  return proc(repo: string): Result[string, string] {.raises: [CatchableError, OSError, Exception].} =
    if repo.len == 0:
      return err("empty repo")
    let client = acquireClient(shared)
    client.headers = newHttpHeaders([
      ("Authorization", "Bearer " & token),
      ("Accept", "application/vnd.github.v3+json")])
    let url = GitHubApiBase & "/repos/" & repo & "/git/ref/" & singleRefApiPath(refName)
    let requestT0 = epochTime()
    try:
      let resp = client.request(url, httpMethod = HttpGet)
      logInfo("ledger_side_ref", "phase=ledger-request url=" & url &
        " elapsed_ms=" & $int((epochTime() - requestT0) * 1000.0) & " status=" & $resp.code)
      if resp.code == Http404:
        return ok("")
      if resp.code.int div 100 != 2:
        return err("GitHub API GET " & url & " -> " & $resp.code & ": " &
                   resp.body[0 .. min(199, resp.body.len - 1)])
      var node: JsonNode
      try:
        node = parseJson(resp.body)
      except CatchableError as e:
        return err("GitHub API response parse error for " & url & ": " & e.msg)
      let sha = shaFromObject(node)
      if sha.isErr:
        return err(sha.error)
      ok(sha.get)
    except CatchableError as e:
      dropConnection(shared)
      return err("GitHub API GET error for " & url & ": " & e.msg)

# ---------------------------------------------------------------------------
# Live GET/POST transport builders (outside the pushed raises:[] scope — the
# returned closures perform real transport and declare the house exception
# set). Previously lived in candidate_materializer/candidate_adapter (the
# removed speculative-queue provider layer); the ledger is their only
# remaining consumer.
# ---------------------------------------------------------------------------

proc liveFetcher*(token: string; pooled: SharedHttpClient = nil): JsonFetcher =
  ## Build a GET closure backed by the GitHub REST API (URL included in
  ## errors). Construction is I/O-free; all transport happens in the closure.
  ## Per-request wall-clock attribution goes to stderr logs ONLY (logging
  ## facade SSOT) — never into any attested artifact or wire payload.
  let shared = if pooled.isNil: SharedHttpClient() else: pooled
  return proc(url: string): Result[JsonNode, string] {.raises: [CatchableError, OSError, Exception].} =
    let client = acquireClient(shared)
    client.headers = newHttpHeaders([
      ("Authorization", "Bearer " & token),
      ("Accept", "application/vnd.github.v3+json")])
    var body = ""
    let requestT0 = epochTime()
    try:
      # request() reads the response body to completion in every outcome
      # (2xx and non-2xx alike), leaving the pooled connection usable;
      # getContent would raise on non-2xx BEFORE draining the body and
      # corrupt the next keep-alive request. Error text is unchanged from
      # the old getContent path (HttpRequestError carried resp.status).
      let resp = client.request(url, HttpGet)
      if resp.code.int div 100 != 2:
        logInfo("ledger_side_ref", "phase=ledger-request url=" & url &
          " elapsed_ms=" & $int((epochTime() - requestT0) * 1000.0) & " outcome=err")
        return err("GitHub API error for " & url & ": " & $resp.status)
      body = resp.body
    except CatchableError as e:
      dropConnection(shared)
      logInfo("ledger_side_ref", "phase=ledger-request url=" & url &
        " elapsed_ms=" & $int((epochTime() - requestT0) * 1000.0) & " outcome=err")
      return err("GitHub API error for " & url & ": " & e.msg)
    logInfo("ledger_side_ref", "phase=ledger-request url=" & url &
      " elapsed_ms=" & $int((epochTime() - requestT0) * 1000.0) & " outcome=ok")
    try:
      ok(parseJson(body))
    except CatchableError as e:
      return err("GitHub API response parse error for " & url & ": " & e.msg)

proc livePoster*(token: string; pooled: SharedHttpClient = nil): JsonPoster =
  ## Build a POST closure backed by the GitHub REST API. Non-2xx → err with
  ## the endpoint; an empty success body (204) becomes ok(JNull).
  ## Construction is I/O-free; all transport happens in the closure.
  let shared = if pooled.isNil: SharedHttpClient() else: pooled
  return proc(url: string; body: string): Result[JsonNode, string] {.raises: [CatchableError, OSError, Exception].} =
    let client = acquireClient(shared)
    client.headers = newHttpHeaders([
      ("Authorization", "Bearer " & token),
      ("Accept", "application/vnd.github.v3+json"),
      ("Content-Type", "application/json")])
    try:
      let resp = client.request(url, httpMethod = HttpPost, body = body)
      if resp.code.int div 100 != 2:
        return err("GitHub API POST " & url & " -> " & $resp.code & ": " &
                   resp.body[0 .. min(199, resp.body.len - 1)])
      if resp.body.len == 0:
        return ok(newJNull())
      try:
        ok(parseJson(resp.body))
      except CatchableError as e:
        return err("GitHub API response parse error for " & url & ": " & e.msg)
    except CatchableError as e:
      dropConnection(shared)
      return err("GitHub API POST error for " & url & ": " & e.msg)

proc liveLedgerTransport*(token: string; refName: string = LedgerRefName): LedgerTransport =
  ## Live GitHub REST transport for the side-ref ledger, mirroring
  ## livePoster/liveFetcher conventions. Construction is I/O-free.
  ## `refName` selects the side ref the tip reader resolves (certificate
  ## ledger by default; admission CLIs pass their own ref name —
  ## a single live transport must never read the wrong ref's tip).
  ## All four closures share ONE HttpClient (SharedHttpClient): every request
  ## of a scan/append pass reuses the keep-alive connection instead of
  ## re-establishing TLS per request. URLs, headers, serial order and the
  ## request count are unchanged; after a transport failure the pooled
  ## connection is dropped so the next request re-dials clean (old
  ## per-request-new-client failure semantics preserved).
  let shared = SharedHttpClient()
  LedgerTransport(fetch: liveFetcher(token, shared), post: livePoster(token, shared),
    patch: liveLedgerPatcher(token, shared), tip: liveLedgerTipReader(token, refName, shared))
