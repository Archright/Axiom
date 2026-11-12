import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

## Durable evidence ledger (Evidence CAS) — side-ref exactly-once store for
## content-addressed verification evidence.
##
## The durable store for landing-flow evidence is the OUT-OF-TREE side ref
## `EvidenceCasRefName` — NEVER the GHA cache or any other cache tier:
## cache is acceleration, never evidence. Git objects are content-addressed
## and immutable (tamper-evident), so a git side-ref ledger gives the same
## guarantee as the certificate ledger (INV-8: out-of-tree side-ref, FF-only
## append) and the admission side refs (ADR-0022). Each append is one commit
## containing `<evidenceKey>.json`; the ref update is a fast-forward CAS
## (PATCH with force=false), so a concurrent move rejects the update and the
## append RETRIES on conflict (bounded, same budget as ledger_side_ref.nim)
## and FAILS CLOSED on exhaustion — no force, no overwrite, no duplicate
## entry. Exactly-once per key (INV-13 discipline: never duplicate identity):
## appending a key that already exists is an idempotent success returning the
## EXISTING entry, never a second record.
##
## Reads RE-HASH the payload bytes on every call (execution_accounting_contract
## §15.3(d): reads re-hash payload bytes) and verify the full identity chain
## — sha256(payload) == payloadSha256 and record.evidenceKey == requested key.
## Missing / mismatched / corrupt / unreadable → fail-closed error. There is
## no partial-trust path: a ledger read either yields the exact verified
## payload bytes or an error.
##
## Identity: `evidenceKey` ALONE. `payloadSha256` binds the payload bytes to
## the record (re-verified on every read); `verifierArtifactDigests` is
## provenance/informational and `storedAtUtc` is audit-only — neither is part
## of the identity. `evidenceDigest` is the record's evidence-bundle BINDING
## digest, carried — never re-derived here: each producer computes it from its
## OWN single definition at build time (attestation evidence:
## evidenceBundleDigest over the canonical 7-member evidenceBundleWire; a
## self-contained payload: the payload's own content digest), and consumers
## COMPARE it against the witness's recorded digest (ADR-0034). Old records
## without the field fail the strict parse (generation cutover backstop).
## The evidence key derivation itself (normalized evidence →
## key) lives OUTSIDE this module: this module is keyed by opaque bytes plus
## the 64-hex key string, so it composes with any producer (e.g.
## verification/evidence_cas.nim).
##
## Transport is injectable — the same `LedgerTransport` as
## verification/ledger_side_ref.nim (live builder: liveLedgerTransport).
## The schema is canonical RFC 8785 JSON (deterministic blob bytes →
## regeneration on retry is idempotent).

import std/[algorithm, json, os, strutils]
import core/axiom_pragmas
import core/crypto/hash_kernel
import core/results
import verification/canonical_json
import verification/ledger_side_ref
import verification/verification_subject

axiomIoBoundary()

const
  EvidenceCasRefName* = "refs/heads/axiom/evidence-cas"
    ## The out-of-tree durable evidence side ref — main tree never contains
    ## the ledger (INV-8 discipline, certificate-ledger sibling
    ## refs/heads/axiom/certificates). HEAD-form (refs/heads/axiom/*) is the
    ## repo's exclusive side-ref convention so branch-protection / FF rulesets
    ## actually apply to the ledger ref; a non-head namespace would escape
    ## them. FF-only appends; never force-updated.
  DefaultEvidenceCasRepo* = "Archright/Axiom"
    ## The ledger's default target repo — the ONE definition; every consumer
    ## (evidence CLI, attestation orchestrator) resolves through
    ## resolveEvidenceCasRepo so the AXIOM_REPO override cannot fork.
  EvidenceCasSchemaVersion* = "axiom.evidence.cas.v1"
    ## Record schema version — a record carrying any other value is corrupt
    ## (fail-closed on read).
  EvidenceCommitMessagePrefix* = "axiom: evidence-cas ledger append "
    ## Commit messages are provenance only — the git objects are the store.
  EvidenceRootCommitMessage* = "axiom: evidence-cas ledger root"
    ## Root commit message (empty-tree root, same shape as the cert ledger).

const
  EvidenceAppendMaxAttempts = 4
    ## Bounded retry-on-conflict budget for ONE appendEvidence call — the
    ## same bound as ledger_side_ref.LedgerAppendMaxAttempts. ONLY
    ## concurrent-move conditions are retried (HTTP 422 from the ref PATCH,
    ## or a raced root-ref create); every other failure fails closed
    ## immediately; exhaustion returns the last conflict error.

type
  EvidenceCasRecord* = object
    evidenceKey*: string            ## 64-hex sha256 — the primary identity
    payload*: string                ## canonical normalized-evidence bytes (lossless JSON string embedding)
    payloadSha256*: string          ## 64-hex sha256 over the payload bytes
    evidenceDigest*: string         ## 64-hex evidence-bundle binding digest — carried from the
                                    ## producer's single definition (ADR-0034); consumers COMPARE,
                                    ## never re-derive
    verifierArtifactDigests*: JsonNode  ## provenance/informational only — NOT identity
    storedAtUtc*: string            ## ISO8601 Zulu — audit only, NOT identity

  EvidenceAppendOutcome* = object
    tipSha*: string                 ## ledger tip after the (possibly no-op) append
    alreadyPresent*: bool           ## true = the key already existed → idempotent no-op
    record*: EvidenceCasRecord      ## the ledger's record for this key (existing entry on a no-op)

# ---------------------------------------------------------------------------
# Pure record construction / validation / serialization
# ---------------------------------------------------------------------------

func evidenceEntryName*(evidenceKey: string): string {.raises: [].} =
  ## Ledger entry name: `<evidenceKey>.json` — one entry per key.
  evidenceKey & ".json"

func isValidEvidenceKey*(s: string): bool {.raises: [].} =
  ## 64 lowercase hex chars — the sha256 identity form.
  isHexOfLen(s, 64)

proc resolveEvidenceCasRepo*(): string {.raises: [].} =
  ## The ledger repo for this process: AXIOM_REPO override, else
  ## DefaultEvidenceCasRepo (the single default definition).
  let overridden = getEnv("AXIOM_REPO", "")
  if overridden.len > 0: overridden else: DefaultEvidenceCasRepo

func validateVerifierArtifactDigests(node: JsonNode): string {.raises: [].} =
  ## The digests object must be a JSON object with string values (digests are
  ## strings) so the canonical serialization stays deterministic. Anything
  ## else is a malformed record (fail-closed). Empty object is valid.
  if node.isNil:
    return ""
  if node.kind != JObject:
    return "evidence_ledger: verifierArtifactDigests must be an object (fail-closed)"
  for key, value in node.pairs:
    if value.kind != JString:
      return "evidence_ledger: verifierArtifactDigests." & key & " must be a string (fail-closed)"
  ""

func makeEvidenceRecord*(evidenceKey, payload: string; verifierArtifactDigests: JsonNode;
                         storedAtUtc, evidenceDigest: string): Result[EvidenceCasRecord, string] {.
    raises: [].} =
  ## Build an EvidenceCasRecord from its parts. FAIL-CLOSED on every malformed
  ## input: non-64-hex evidenceKey, empty payload, non-object or non-string-
  ## valued digests, non-canonical storedAtUtc, non-64-hex evidenceDigest.
  ## payloadSha256 is derived from the payload bytes — never accepted as an
  ## input. evidenceDigest is accepted as the producer's binding digest (each
  ## producer computes it from its own single definition before calling); it
  ## is validated for form only, never re-derived here.
  if not isValidEvidenceKey(evidenceKey):
    return err("evidence_ledger: evidenceKey must be 64 lowercase hex chars (fail-closed)")
  if payload.len == 0:
    return err("evidence_ledger: payload must be non-empty (fail-closed)")
  let digestsError = validateVerifierArtifactDigests(verifierArtifactDigests)
  if digestsError.len > 0:
    return err(digestsError)
  if not isValidIso8601Zulu(storedAtUtc):
    return err("evidence_ledger: storedAtUtc must be ISO8601 UTC 'yyyy-MM-ddTHH:mm:ssZ' (fail-closed)")
  if not isHexOfLen(evidenceDigest, 64):
    return err("evidence_ledger: evidenceDigest must be 64 lowercase hex chars (fail-closed)")
  let digests = if verifierArtifactDigests.isNil: newJObject() else: verifierArtifactDigests
  ok(EvidenceCasRecord(
    evidenceKey: evidenceKey,
    payload: payload,
    payloadSha256: sha256Hex(payload),
    evidenceDigest: evidenceDigest,
    verifierArtifactDigests: digests,
    storedAtUtc: storedAtUtc))

## Structural self-check: "" = well-formed; otherwise the rejection reason
## (fail-closed — a malformed record is never appended or served).
## Re-derives payloadSha256 from the payload bytes.
func validateEvidenceRecord*(record: EvidenceCasRecord): string {.raises: [].} =
  if not isValidEvidenceKey(record.evidenceKey):
    return "evidence_ledger: evidenceKey must be 64 lowercase hex chars (fail-closed)"
  if record.payload.len == 0:
    return "evidence_ledger: payload must be non-empty (fail-closed)"
  if not isHexOfLen(record.payloadSha256, 64):
    return "evidence_ledger: payloadSha256 must be 64 lowercase hex chars (fail-closed)"
  let derived = sha256Hex(record.payload)
  if derived != record.payloadSha256:
    return "evidence_ledger: payloadSha256 does not match sha256(payload) (fail-closed)"
  if not isHexOfLen(record.evidenceDigest, 64):
    return "evidence_ledger: evidenceDigest must be 64 lowercase hex chars (fail-closed)"
  let digestsError = validateVerifierArtifactDigests(record.verifierArtifactDigests)
  if digestsError.len > 0:
    return digestsError
  if not isValidIso8601Zulu(record.storedAtUtc):
    return "evidence_ledger: storedAtUtc must be ISO8601 UTC 'yyyy-MM-ddTHH:mm:ssZ' (fail-closed)"
  ""

func evidenceRecordToCanonicalJson*(record: EvidenceCasRecord): string {.raises: [].} =
  ## RFC 8785 canonical JSON of the record — the deterministic blob bytes.
  ## Field set is fixed; the canonical serializer emits keys in RFC 8785
  ## order, so identical records serialize to identical bytes.
  canonicalJsonString(%*{
    "schemaVersion": EvidenceCasSchemaVersion,
    "evidenceKey": record.evidenceKey,
    "payload": record.payload,
    "payloadSha256": record.payloadSha256,
    "evidenceDigest": record.evidenceDigest,
    "verifierArtifactDigests": record.verifierArtifactDigests,
    "storedAtUtc": record.storedAtUtc
  })

func evidenceRecordFromJson*(node: JsonNode): Result[EvidenceCasRecord, string] {.raises: [].} =
  ## Parse + fully validate a ledger record. Missing/wrong-typed fields, a
  ## foreign schemaVersion, malformed hex, or a payloadSha256 that does not
  ## match the re-hashed payload bytes → err (fail-closed: a tampered record
  ## is never read as valid). evidenceKey is taken as the identity here; the
  ## caller binds it to the requested key (see fetchEvidenceRecord).
  ## evidenceDigest is REQUIRED: a record without it (a pre-ADR-0034
  ## old-generation record) fails the parse — the generation-cutover backstop
  ## that keeps a binding-less record from ever being served or re-appended.
  if node.isNil or node.kind != JObject:
    return err("evidence_ledger: evidence record must be a JSON object")
  template need(key: string): string =
    block:
      let v = node{key}
      if v.isNil or v.kind != JString or v.getStr().len == 0:
        return err("evidence_ledger: missing or empty field '" & key & "' (fail-closed)")
      v.getStr()
  let schemaVersion = need("schemaVersion")
  if schemaVersion != EvidenceCasSchemaVersion:
    return err("evidence_ledger: unsupported schemaVersion '" &
      schemaVersion[0 ..< min(schemaVersion.len, 32)] & "' (fail-closed)")
  let evidenceKey = need("evidenceKey")
  let payload = need("payload")
  let payloadSha256 = need("payloadSha256")
  let evidenceDigest = need("evidenceDigest")
  let digests = node{"verifierArtifactDigests"}
  let digestsError = validateVerifierArtifactDigests(digests)
  if digestsError.len > 0:
    return err(digestsError)
  let storedAtUtc = need("storedAtUtc")
  let built = makeEvidenceRecord(evidenceKey, payload,
    if digests.isNil: newJObject() else: digests, storedAtUtc, evidenceDigest)
  if built.isErr:
    return err("evidence_ledger: " & built.error)
  let record = built.get
  if record.payloadSha256 != payloadSha256:
    return err("evidence_ledger: payloadSha256 does not match sha256(payload) (fail-closed)")
  ok(record)

# ---------------------------------------------------------------------------
# Pure response decoding — fail-closed on missing fields
# ---------------------------------------------------------------------------

func evidenceKeysFromNames*(names: seq[string]): Result[seq[string], string] {.raises: [].} =
  ## Strict evidence-key projection over side-ref entry names: every entry
  ## must be "<64-hex>.json". Any other name is a ledger integrity violation
  ## (fail-closed — garbage is never silently skipped).
  var keys: seq[string] = @[]
  for path in names:
    if not path.endsWith(".json"):
      return err("evidence_ledger: non-JSON file in evidence ledger (fail-closed): " & path)
    let key = path[0 ..< path.len - ".json".len]
    if not isValidEvidenceKey(key):
      return err("evidence_ledger: non-canonical file in evidence ledger (fail-closed): " & path)
    keys.add(key)
  keys.sort()
  ok(keys)

func blobShaForKey*(node: JsonNode; evidenceKey: string): Result[string, string] {.raises: [].} =
  ## Locate the `<evidenceKey>.json` blob entry in a recursive tree response
  ## and return its sha. Missing entry → err (the ledger never had this key);
  ## a present entry without a sha → err (fail-closed).
  if node.isNil or node.kind != JObject:
    return err("evidence_ledger: tree response is not an object")
  let tree = node{"tree"}
  if tree.isNil or tree.kind != JArray:
    return err("evidence_ledger: tree response missing tree array")
  let want = evidenceEntryName(evidenceKey)
  for entry in tree.getElems():
    if entry.kind != JObject:
      return err("evidence_ledger: malformed tree entry (fail-closed)")
    if entry.getOrDefault("type").getStr("") != "blob":
      continue
    if entry.getOrDefault("path").getStr("") != want:
      continue
    let sha = entry{"sha"}
    if sha.isNil or sha.kind != JString or sha.getStr().len == 0:
      return err("evidence_ledger: blob entry missing sha for " & want & " (fail-closed)")
    return ok(sha.getStr())
  err("evidence_ledger: no evidence record for key " & evidenceKey & " (fail-closed)")

func decodeEvidenceBlob*(blob: JsonNode): Result[string, string] {.raises: [].} =
  ## Blob API response → decoded record text. Missing content or malformed
  ## base64 → err (fail-closed).
  if blob.isNil or blob.kind != JObject:
    return err("evidence_ledger: blob response is not an object")
  let content = blob{"content"}
  if content.isNil or content.kind != JString or content.getStr().len == 0:
    return err("evidence_ledger: blob response missing content (fail-closed)")
  let decoded = decodeBlobContent(content.getStr())
  if decoded.isErr:
    return err("evidence_ledger: " & decoded.error)
  ok(decoded.get)

proc parseEvidenceRecord*(text: string): Result[EvidenceCasRecord, string]
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Parse + validate a record from its decoded blob text. parseJson is
  ## effectful, so this is an I/O-boundary proc (house convention: JSON
  ## parsing happens in annotated procs, see ledger_side_ref). Malformed
  ## JSON or any field violation → err (fail-closed).
  var node: JsonNode
  try:
    node = parseJson(text)
  except CatchableError as e:
    return err("evidence_ledger: malformed evidence record JSON: " & e.msg)
  evidenceRecordFromJson(node)

# ---------------------------------------------------------------------------
# Read side — HIT/MISS membership + verified payload lookup
# ---------------------------------------------------------------------------

proc listEvidenceKeys*(transport: LedgerTransport; repo: string;
                       refName: string = EvidenceCasRefName): Result[seq[string], string]
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## All evidence keys on the side ref, sorted. Absent ledger ref = empty
  ## ledger (ok(@[])) — there is nothing stored yet. Any non-canonical entry
  ## fails closed. Entry enumeration is delegated to the shared side-ref
  ## read surface (listRefEntryNames — one tip-tree reader per repo, the
  ## certificate ledger reuses the same plumbing); this proc adds only the
  ## strict evidence-key projection.
  let names = listRefEntryNames(transport, repo, refName)
  if names.isErr:
    return err("evidence_ledger.listEvidenceKeys: " & names.error)
  evidenceKeysFromNames(names.get)

proc hasEvidence*(transport: LedgerTransport; repo, evidenceKey: string;
                  refName: string = EvidenceCasRefName): Result[bool, string]
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## HIT/MISS predicate: TRUE iff `<evidenceKey>.json` exists under the side
  ## ref tip. Absent ref = ok(false) — a legitimate MISS. The membership test
  ## consumes the strict key listing, so a corrupt/garbled ledger fails
  ## closed (err) instead of reporting a MISS — an unverifiable ledger is
  ## never reported as "not stored".
  if not isValidEvidenceKey(evidenceKey):
    return err("evidence_ledger.hasEvidence: evidenceKey must be 64 lowercase hex chars (fail-closed)")
  let keys = listEvidenceKeys(transport, repo, refName)
  if keys.isErr:
    return err("evidence_ledger.hasEvidence: " & keys.error)
  ok(keys.get.contains(evidenceKey))

proc fetchEvidenceRecord*(transport: LedgerTransport; repo, evidenceKey: string;
                          refName: string = EvidenceCasRefName): Result[EvidenceCasRecord, string]
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Read ONE evidence record: tip → recursive tree → blob sha of
  ## `<evidenceKey>.json` → blob content (base64) → decoded canonical JSON →
  ## full record validation (re-hashes the payload bytes). Fail-closed on
  ## absent ref, malformed key, missing entry, unreadable blob, malformed
  ## base64/JSON, hash mismatch, or an evidenceKey that differs from the
  ## requested key — a ledger read either yields the exact verified record
  ## or an error, never a partial/guessed record.
  if repo.len == 0:
    return err("evidence_ledger.fetchEvidenceRecord: empty repo")
  if not isValidEvidenceKey(evidenceKey):
    return err("evidence_ledger.fetchEvidenceRecord: evidenceKey must be 64 lowercase hex chars (fail-closed)")
  let tip = transport.tip(repo)
  if tip.isErr:
    return err("evidence_ledger.fetchEvidenceRecord: " & tip.error)
  if tip.get.len == 0:
    return err("evidence_ledger.fetchEvidenceRecord: evidence ledger ref absent — no evidence records (fail-closed)")
  let tree = fetchTipTree(transport, repo, tip.get, "evidence_ledger.fetchEvidenceRecord")
  if tree.isErr:
    return err(tree.error)
  let blobSha = blobShaForKey(tree.get, evidenceKey)
  if blobSha.isErr:
    return err("evidence_ledger.fetchEvidenceRecord: " & blobSha.error)
  let blobUrl = GitHubApiBase & "/repos/" & repo & "/git/blobs/" & blobSha.get
  let blobResponse = transport.fetch(blobUrl)
  if blobResponse.isErr:
    return err("evidence_ledger.fetchEvidenceRecord: " & blobResponse.error)
  let decoded = decodeEvidenceBlob(blobResponse.get)
  if decoded.isErr:
    return err("evidence_ledger.fetchEvidenceRecord: " & decoded.error)
  let record = parseEvidenceRecord(decoded.get)
  if record.isErr:
    return err("evidence_ledger.fetchEvidenceRecord: " & record.error)
  if record.get.evidenceKey != evidenceKey:
    return err("evidence_ledger.fetchEvidenceRecord: ledger object key " & record.get.evidenceKey &
      " != requested " & evidenceKey & " (fail-closed)")
  ok(record.get)

proc lookupEvidence*(transport: LedgerTransport; repo, evidenceKey: string;
                     refName: string = EvidenceCasRefName): Result[string, string]
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Reuse read path: verify + return the payload bytes for `evidenceKey`.
  ## The payload is re-hashed and the identity chain re-verified on every
  ## call (execution_accounting_contract §15.3(d)). Missing / mismatched /
  ## corrupt → fail-closed error — never a partial-trust result.
  let record = fetchEvidenceRecord(transport, repo, evidenceKey, refName)
  if record.isErr:
    return err("evidence_ledger.lookupEvidence: " & record.error)
  ok(record.get.payload)

# ---------------------------------------------------------------------------
# Write side — the ONLY mutation: FF-only idempotent append
# ---------------------------------------------------------------------------

proc isRefConflictError(err: string): bool {.raises: [].} =
  ## Conflict predicate for the retry loop (same contract as
  ## ledger_side_ref.isRefConflictError): HTTP 422 from a REST git ref
  ## transport = the ref moved concurrently (non-fast-forward PATCH rejected
  ## / ref-creation raced). Every other failure (validation, auth, 5xx,
  ## malformed response, missing sha) is NOT a conflict and fails closed
  ## at once.
  "-> 422" in err

proc createEvidenceCasRoot*(transport: LedgerTransport; repo: string;
                            refName: string = EvidenceCasRefName): Result[string, string]
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Root the evidence side ref on an empty-tree commit (called only when the
  ## tip read reported the ref absent). Ref-creation failure (422 = raced
  ## root create) fails closed — the append retry loop re-reads the tip.
  if repo.len == 0:
    return err("evidence_ledger.createEvidenceCasRoot: empty repo")
  let commitUrl = GitHubApiBase & "/repos/" & repo & "/git/commits"
  let commitResp = transport.post(commitUrl, $(%*{
    "message": EvidenceRootCommitMessage,
    "tree": EmptyTreeSha,
    "parents": []}))
  if commitResp.isErr:
    return err("evidence_ledger.createEvidenceCasRoot: root commit create failed: " & commitResp.error)
  let rootSha = shaFromNode(commitResp.get)
  if rootSha.isErr:
    return err("evidence_ledger.createEvidenceCasRoot: " & rootSha.error)
  let refUrl = GitHubApiBase & "/repos/" & repo & "/git/refs"
  let refResp = transport.post(refUrl, $(%*{
    "ref": refName,
    "sha": rootSha.get}))
  if refResp.isErr:
    return err("evidence_ledger.createEvidenceCasRoot: ref create failed: " & refResp.error)
  ok(rootSha.get)

proc createEvidenceObjects*(transport: LedgerTransport; repo, blobContent, baseTip,
                            evidenceKey: string): Result[string, string]
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Git Data API object pipeline for ONE append: blob (canonical record
  ## bytes) → tree with base_tree = current tip (entry `<evidenceKey>.json`)
  ## → commit with parent = tip. Returns the commit sha. Fail-closed on every
  ## transport/response failure (a missing sha in any response is a
  ## malformed-response error, never a retry).
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
    "tree": [{"path": evidenceEntryName(evidenceKey), "mode": "100644", "type": "blob", "sha": blobSha.get}]}))
  if treeResponse.isErr:
    return err("tree create failed: " & treeResponse.error)
  let treeSha = shaFromNode(treeResponse.get)
  if treeSha.isErr:
    return err("tree response malformed: " & treeSha.error)
  let commitUrl = GitHubApiBase & "/repos/" & repo & "/git/commits"
  let commitResponse = transport.post(commitUrl, $(%*{
    "message": EvidenceCommitMessagePrefix & evidenceKey,
    "tree": treeSha.get,
    "parents": [baseTip]}))
  if commitResponse.isErr:
    return err("commit create failed: " & commitResponse.error)
  let commitSha = shaFromNode(commitResponse.get)
  if commitSha.isErr:
    return err("commit response malformed: " & commitSha.error)
  ok(commitSha.get)

proc existingEvidenceAtTip*(transport: LedgerTransport; repo, tip, evidenceKey: string;
                            refName: string = EvidenceCasRefName): Result[EvidenceCasRecord, string]
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Exactly-once re-check: fetch + fully validate the record this key already
  ## has at `tip`. Any read/verify failure fails closed — an unverifiable
  ## existing entry is never treated as "already stored" (no partial trust).
  let tree = fetchTipTree(transport, repo, tip, "evidence_ledger.existingEvidenceAtTip")
  if tree.isErr:
    return err(tree.error)
  let blobSha = blobShaForKey(tree.get, evidenceKey)
  if blobSha.isErr:
    return err("evidence_ledger.existingEvidenceAtTip: " & blobSha.error)
  let blobUrl = GitHubApiBase & "/repos/" & repo & "/git/blobs/" & blobSha.get
  let blobResponse = transport.fetch(blobUrl)
  if blobResponse.isErr:
    return err("evidence_ledger.existingEvidenceAtTip: " & blobResponse.error)
  let decoded = decodeEvidenceBlob(blobResponse.get)
  if decoded.isErr:
    return err("evidence_ledger.existingEvidenceAtTip: " & decoded.error)
  let record = parseEvidenceRecord(decoded.get)
  if record.isErr:
    return err("evidence_ledger.existingEvidenceAtTip: " & record.error)
  if record.get.evidenceKey != evidenceKey:
    return err("evidence_ledger.existingEvidenceAtTip: ledger object key " & record.get.evidenceKey &
      " != requested " & evidenceKey & " (fail-closed)")
  ok(record.get)

proc appendEvidence*(transport: LedgerTransport; repo: string; record: EvidenceCasRecord;
                     refName: string = EvidenceCasRefName): Result[EvidenceAppendOutcome, string]
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Append ONE evidence record to the side-ref ledger. Exactly-once per key:
  ##
  ## * The record is validated first (integrity: payloadSha256 re-derived
  ##   from the payload bytes; any anomaly → fail-closed, nothing is written).
  ## * If the key already exists at the tip (checked on every attempt EXCEPT
  ##   the one that just created the ledger root — a freshly rooted ledger
  ##   contains nothing by construction), the
  ##   existing entry is fetched and fully verified; if its payloadSha256
  ##   matches the appended record's, the append is an idempotent success
  ##   returning the EXISTING entry (alreadyPresent=true, tip unchanged —
  ##   no duplicate, no second write). Same key + different payload bytes is
  ##   an identity-derivation anomaly → fail-closed.
  ## * Otherwise: object pipeline on the current tip → FF CAS ref update
  ##   (PATCH force=false). A concurrent move rejects the PATCH (HTTP 422)
  ##   and the append RETRIES, up to EvidenceAppendMaxAttempts attempts
  ##   total: re-read the tip → re-check exactly-once against the NEW tip →
  ##   rebuild the deterministic objects on the moved tip → PATCH again.
  ##   A raced root-ref create (422) is the same conflict. Exhaustion returns
  ##   the last conflict error — fail-closed: no force, no overwrite, no
  ##   duplicate entry. Only concurrent-move conditions retry; malformed
  ##   records, validation, auth and non-conflict transport errors fail
  ##   closed immediately.
  ##
  ## The canonical record serialization is deterministic (RFC 8785), so
  ## regenerating the blob bytes on a retry is idempotent.
  let valid = validateEvidenceRecord(record)
  if valid.len > 0:
    return err("evidence_ledger.appendEvidence: " & valid)
  let blobContent = evidenceRecordToCanonicalJson(record)
  var lastConflict = ""
  for attempt in 1 .. EvidenceAppendMaxAttempts:
    # 1. current tip (or root the ref when it does not exist yet) — re-read
    #    on EVERY attempt so a retry parents on the moved tip.
    let tipRes = transport.tip(repo)
    if tipRes.isErr:
      return err("evidence_ledger.appendEvidence: tip read failed: " & tipRes.error)
    var tip = tipRes.get
    var freshlyRooted = false
    if tip.len == 0:
      let rootRes = createEvidenceCasRoot(transport, repo, refName)
      if rootRes.isErr:
        # raced root creation (two writers rooted simultaneously → the
        # loser's ref-create is rejected 422) = a conflict: next attempt
        # re-reads the tip, which now exists, and proceeds normally.
        if "ref create failed" in rootRes.error and isRefConflictError(rootRes.error):
          lastConflict = rootRes.error
          continue
        return err("evidence_ledger.appendEvidence: evidence ledger root creation failed: " &
          rootRes.error)
      tip = rootRes.get
      freshlyRooted = true
    # 2. exactly-once re-check against the tip we are about to parent on —
    #    EXCEPT on the attempt that just created the ledger root: a freshly
    #    rooted ledger contains nothing by construction (its tree IS the
    #    empty tree), so the re-check there is a tautology (same shape as the
    #    cert ledger's attempt-guarded duplicate re-check). Every other
    #    attempt still re-checks — the first writer wins; a same-key entry
    #    that landed with a moved tip is the existing entry, never a
    #    duplicate. Any read failure fails closed: an unverifiable ledger is
    #    never appended to.
    if not freshlyRooted:
      let existing = existingEvidenceAtTip(transport, repo, tip, record.evidenceKey, refName)
      if existing.isOk:
        let existingRecord = existing.get
        if existingRecord.payloadSha256 != record.payloadSha256:
          return err("evidence_ledger.appendEvidence: evidence key " & record.evidenceKey &
            " already present with DIFFERENT payload bytes (payloadSha256 mismatch — " &
            "identity-derivation anomaly, fail-closed, not re-appended)")
        return ok(EvidenceAppendOutcome(tipSha: tip, alreadyPresent: true, record: existingRecord))
      if not existing.error.contains("no evidence record for key"):
        return err("evidence_ledger.appendEvidence: " & existing.error)
    # 3-5. object pipeline → FF CAS ref update (force=false → concurrent
    #      move = rejected 422)
    let objects = createEvidenceObjects(transport, repo, blobContent, tip, record.evidenceKey)
    if objects.isErr:
      return err("evidence_ledger.appendEvidence: " & objects.error)
    let refUrl = GitHubApiBase & "/repos/" & repo & "/git/refs/" & singleRefApiPath(refName)
    let refResp = transport.patch(refUrl, $(%*{"sha": objects.get, "force": false}))
    if refResp.isErr:
      if isRefConflictError(refResp.error):
        lastConflict = refResp.error
        continue
      return err("evidence_ledger.appendEvidence: ref update failed (non-FF / ref moved?): " &
        refResp.error)
    let updated = shaFromObject(refResp.get)
    if updated.isErr:
      return err("evidence_ledger.appendEvidence: " & updated.error)
    return ok(EvidenceAppendOutcome(tipSha: updated.get, alreadyPresent: false, record: record))
  err("evidence_ledger.appendEvidence: concurrent evidence ledger append conflict after " &
    $EvidenceAppendMaxAttempts & " attempts (last conflict error: " & lastConflict & ")")
