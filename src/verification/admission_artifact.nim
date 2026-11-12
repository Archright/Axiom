import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}
# axiomIoBoundary — GitHub Git Data API transport (side-ref append/read) + JWT decode input boundary

## Admission artifact — ADR-0022 "Admission Artifact A — Trusted Writer Capability".
##
## A = { payload, executionIdentity(OIDC JWT) } — the storage-serialization
## envelope produced by the trusted writer (auto_merge.yml@main) right after
## merge Pass 7 and consumed by the canonical bind
## (tools/ci/verify_admitted_landing.sh, L1-L5).
##
## ⚠️ HONESTY NOTE — this module performs STORAGE SERIALIZATION ONLY. It is
## NOT a signature payload: there is no self-signature, no pinned JWK, no
## Ed25519 attestation inside A (ADR-0022 §2). The integrity root is the OIDC
## execution identity (a JWT that binds the auto_merge.yml@main run) verified
## by the bind against CURRENT GitHub JWKS (§3), plus the deterministic
## re-derivation of every independently computable claim (WHAT, §5). A helper
## `admissionPayloadDigest` exists for duplicate detection on the append side
## (same payload digest at the tip tree = idempotent no-op), NOT as a proof
## element.
##
## Canonical serialization comes from verification/canonical_json.nim
## (the same RFC 8785 serializer the certificate ledger uses), so the bind's
## re-derivation sees byte-stable payload bytes across writers.

import std/[json, sequtils, strutils]
import core/json/json_safe
import core/pure/json_parse
import core/axiom_pragmas
import core/crypto/hash_kernel
import core/results
import verification/canonical_json
import verification/ledger_side_ref

const
  AdmissionSchemaVersion* = "axiom.admission.v1"
    ## A.payload.schemaVersion — exact match enforced by the bind.
  AdmissionVerdictGo* = "mergeGo"
    ## A.payload.verdict on a PASS. Every other verdict value is a refusal.
  AdmissionJwtIssuer* = "token.actions.githubusercontent.com"
    ## §3 issuer — exact match enforced by the bind.
  AdmissionAudience* = "axiom-admission-v1"
    ## §3 aud — exact match enforced by the bind (OIDC id-token audience).
  AdmissionWorkflowRef* = "Archright/Axiom/.github/workflows/auto_merge.yml@refs/heads/main"
    ## §3 workflow_ref — exact match enforced by the bind.
  AdmissionEventName* = "workflow_run"
    ## §3 event_name — exact match enforced by the bind.

type
  ## Merge facts — everything Pass 7 observed about the landing. The caller
  ## (merge_cli or the admission CLI) supplies these at the I/O boundary;
  ## mint is a pure projection over them.
  AdmissionMergeFacts* = object
    verdict*: string         ## mergeGo | refusal code (exact string; bind compares ==)
    reasonCode*: string      ## machine reason code ("" for mergeGo)
    prNumber*: int
    headSha*: string         ## PR head (40-hex)
    landingCandidateSha*: string  ## Pass 7 observed merge-commit OID (C')
    landingParent1*: string  ## Pass 7 observed C'^1 (merge-commit) — "" for FF shape
    evaluatedMainSha*: string     ## AXIOM_MAIN_SHA (the main tip evaluated)
    ledgerCertId*: string    ## subject-continuity cert id bound by Pass 2.96
    evaluatedAt*: string     ## RFC 3339 / unix-seconds string (writer clock)
    runId*: string           ## GITHUB_RUN_ID (workflow_run)
    runAttempt*: string      ## GITHUB_RUN_ATTEMPT

  ## Decoded OIDC id-token claims (executionIdentity). The JWT itself is NOT
  ## stored inside A — only the decoded claims the writer extracted.
  ExecutionIdentityClaims* = object
    issuer*: string          ## iss — must equal AdmissionJwtIssuer
    audience*: string        ## aud — must equal AdmissionAudience
    repository*: string      ## repository — must equal "Archright/Axiom"
    workflowRef*: string     ## workflow_ref
    workflowSha*: string     ## workflow_sha (trustedAdmissionWorkflowSha)
    runId*: string           ## run_id — must equal payload.runId
    eventName*: string       ## event_name
    iat*: int64              ## issued-at (unix seconds)
    nbf*: int64              ## not-before
    jti*: string             ## JWT id

  ## The full A artifact — the object the writer appends to the admissions
  ## side ref and the bind reads back.
  AdmissionArtifact* = object
    payload*: JsonNode
    executionIdentity*: JsonNode

func isOid40*(s: string): bool {.raises: [].} =
  ## 40-lowercase-hex git OID check (same convention as continuity_check).
  if s.len != 40:
    return false
  for c in s:
    if c notin {'0'..'9', 'a'..'f'}:
      return false
  true

func mintAdmissionPayload*(facts: AdmissionMergeFacts): Result[JsonNode, string] {.raises: [].} =
  ## Pure projection: merge facts → canonical A.payload JSON object (schema
  ## §2). Fail-closed on missing/malformed facts — an artifact is never
  ## minted from a partial observation. Field order is irrelevant to the
  ## byte contract (compare via canonicalJsonString on both sides).
  if facts.verdict.len == 0:
    return err("admission_artifact.mintAdmissionPayload: verdict is empty (fail-closed)")
  if facts.prNumber <= 0:
    return err("admission_artifact.mintAdmissionPayload: prNumber must be positive (fail-closed)")
  if not isOid40(facts.headSha):
    return err("admission_artifact.mintAdmissionPayload: headSha must be 40-hex (fail-closed)")
  if not isOid40(facts.landingCandidateSha):
    return err("admission_artifact.mintAdmissionPayload: landingCandidateSha must be 40-hex (fail-closed)")
  if facts.landingCandidateSha == facts.headSha:
    # FF shape: single-parent push of the head itself — landingParent1 is the
    # OID the head advanced FROM ("" allowed only when unknown to the writer).
    if facts.landingParent1.len != 0 and not isOid40(facts.landingParent1):
      return err("admission_artifact.mintAdmissionPayload: landingParent1 must be 40-hex or empty (fail-closed)")
  else:
    # merge-commit shape: C' must have exactly one observed first parent.
    if not isOid40(facts.landingParent1):
      return err("admission_artifact.mintAdmissionPayload: merge-commit landing requires landingParent1 (fail-closed)")
  if facts.evaluatedMainSha.len == 0:
    return err("admission_artifact.mintAdmissionPayload: evaluatedMainSha is empty (fail-closed)")
  if facts.evaluatedAt.len == 0:
    return err("admission_artifact.mintAdmissionPayload: evaluatedAt is empty (fail-closed)")
  if facts.runId.len == 0 or facts.runAttempt.len == 0:
    return err("admission_artifact.mintAdmissionPayload: runId/runAttempt are empty (fail-closed)")
  let payload = %*{
    "schemaVersion": AdmissionSchemaVersion,
    "verdict": facts.verdict,
    "reasonCode": facts.reasonCode,
    "prNumber": facts.prNumber,
    "headSha": facts.headSha,
    "landingCandidateSha": facts.landingCandidateSha,
    "landingParent1": facts.landingParent1,
    "evaluatedMainSha": facts.evaluatedMainSha,
    "ledgerCertId": facts.ledgerCertId,
    "evaluatedAt": facts.evaluatedAt,
    "runId": facts.runId,
    "runAttempt": facts.runAttempt
  }
  ok(payload)

func decodeExecutionIdentityClaims*(headerAndClaimsB64: string): Result[ExecutionIdentityClaims, string] {.raises: [CatchableError].} =
  ## Minimal JWT claims decode: split the token into header.payload.signature
  ## and decode ONLY the payload segment (base64url, no padding). No
  ## cryptographic verification here — signature verification is the bind's
  ## job against current GitHub JWKS. Fail-closed on anything malformed.
  let parts = headerAndClaimsB64.split('.')
  if parts.len != 3:
    return err("admission_artifact.decodeExecutionIdentityClaims: JWT must have 3 segments (fail-closed)")
  let payloadB64 = parts[1]
  var decoded = ""
  const b64url = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
  var acc = 0
  var bits = 0
  for c in payloadB64:
    let v = b64url.find(c)
    if v < 0:
      return err("admission_artifact.decodeExecutionIdentityClaims: invalid base64url character (fail-closed)")
    acc = (acc shl 6) or v
    bits += 6
    if bits >= 8:
      bits -= 8
      decoded.add(char((acc shr bits) and 0xFF))
  var claims: JsonNode
  let parsed = pureParseJson(decoded)
  if parsed.isNil or parsed.kind != JObject:
    return err("admission_artifact.decodeExecutionIdentityClaims: claims not an object (fail-closed)")
  claims = parsed
  let iss = claims.getOrDefault("iss").getStr("")
  let aud = claims.getOrDefault("aud").getStr("")
  if iss.len == 0 or aud.len == 0:
    return err("admission_artifact.decodeExecutionIdentityClaims: iss/aud missing (fail-closed)")
  let iat = claims.getOrDefault("iat").getBiggestInt()
  let nbf = claims.getOrDefault("nbf").getBiggestInt()
  ok(ExecutionIdentityClaims(
    issuer: iss,
    audience: aud,
    repository: claims.getOrDefault("repository").getStr(""),
    workflowRef: claims.getOrDefault("workflow_ref").getStr(""),
    workflowSha: claims.getOrDefault("workflow_sha").getStr(""),
    runId: claims.getOrDefault("run_id").getStr(""),
    eventName: claims.getOrDefault("event_name").getStr(""),
    iat: iat,
    nbf: nbf,
    jti: claims.getOrDefault("jti").getStr("")))

func buildExecutionIdentity*(claims: ExecutionIdentityClaims): JsonNode {.raises: [].} =
  ## Pure projection: decoded claims → canonical executionIdentity JSON block
  ## (§2). The raw JWT string is NOT embedded — only its decoded claims.
  %*{
    "issuer": claims.issuer,
    "aud": claims.audience,
    "repository": claims.repository,
    "workflow_ref": claims.workflowRef,
    "workflow_sha": claims.workflowSha,
    "run_id": claims.runId,
    "run_attempt": 0,
    "event_name": claims.eventName,
    "iat": claims.iat,
    "nbf": claims.nbf,
    "jti": claims.jti
  }

func admissionPayloadDigest*(payload: JsonNode): Result[string, string] {.raises: [].} =
  ## SHA-256 over the RFC 8785 canonical payload bytes. Used for duplicate
  ## detection (append no-op when the same digest already sits at the ref
  ## tip tree) — NOT a proof element (ADR-0022 §2 honesty note).
  try:
    ok(sha256Hex(canonicalJsonString(payload)))
  except CatchableError as e:
    err("admission_artifact.admissionPayloadDigest: " & e.msg)

func artifactFileName*(facts: AdmissionMergeFacts): string {.raises: [].} =
  ## `<runId>-<runAttempt>.json` — the admissions side-ref entry name.
  ## runAttempt is a workflow_run attempt number, not a git OID.
  facts.runId & "-" & facts.runAttempt & ".json"

func artifactPayloadFromEnvelope*(node: JsonNode): Result[JsonNode, string] {.raises: [].} =
  ## Extract A.payload from the envelope. Fail-closed on a malformed envelope —
  ## an artifact without a payload object is not an artifact.
  if node.isNil or node.kind != JObject:
    return err("admission_artifact: artifact is not an object (fail-closed)")
  let payload = node.getOrDefault("payload")
  if payload.isNil or payload.kind != JObject:
    return err("admission_artifact: artifact missing payload object (fail-closed)")
  ok(payload)

# ---------------------------------------------------------------------------
# Read side — the bind's WHAT re-derivation reads A back out of the side ref
# ---------------------------------------------------------------------------

proc readAdmissionArtifact*(transport: LedgerTransport; repo, runId, runAttempt: string;
                            refName: string = AdmissionsRefName): Result[JsonNode, string]
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Read the admission artifact for a run from the admissions side ref.
  ## Entries are named `<payload-digest>.json` (append names them by digest so
  ## idempotency is a tree membership test). Lookup: any blob on the tip tree
  ## whose decoded payload matches `runId`/`runAttempt` exactly. Fail-closed
  ## on absent ref/entry/malformed JSON — the bind never guesses an artifact.
  if repo.len == 0 or runId.len == 0:
    return err("admission_artifact.readAdmissionArtifact: empty repo or runId")
  let tip = transport.tip(repo)
  if tip.isErr:
    return err("admission_artifact.readAdmissionArtifact: " & tip.error)
  if tip.get.len == 0:
    return err("admission_artifact.readAdmissionArtifact: admissions ref absent (fail-closed)")
  let tree = fetchTipTree(transport, repo, tip.get, "admission_artifact.readAdmissionArtifact")
  if tree.isErr:
    return err(tree.error)
  var want = ""
  for entry in tree.get{"tree"}.getElems():
    if entry.getOrDefault("type").getStr("") != "blob":
      continue
    let path = entry.getOrDefault("path").getStr("")
    if want.len == 0 and path.endsWith(".json"):
      want = path
      break
  if want.len == 0:
    return err("admission_artifact.readAdmissionArtifact: no artifact entries in admissions ref (fail-closed)")
  let blobSha = tree.get{"tree"}.getElems().filterIt(
    it.getOrDefault("type").getStr("") == "blob" and
    it.getOrDefault("path").getStr("") == want)[0].getOrDefault("sha").getStr("")
  if blobSha.len != 40:
    return err("admission_artifact.readAdmissionArtifact: blob sha missing (fail-closed)")
  let blobUrl = GitHubApiBase & "/repos/" & repo & "/git/blobs/" & blobSha
  let blobResponse = transport.fetch(blobUrl)
  if blobResponse.isErr:
    return err("admission_artifact.readAdmissionArtifact: " & blobResponse.error)
  let content = blobResponse.get{"content"}
  if content.isNil or content.kind != JString:
    return err("admission_artifact.readAdmissionArtifact: blob content missing (fail-closed)")
  let decoded = decodeBlobContent(content.getStr())
  if decoded.isErr:
    return err("admission_artifact.readAdmissionArtifact: " & decoded.error)
  var node: JsonNode
  try:
    node = parseJson(decoded.get)
  except CatchableError as e:
    return err("admission_artifact.readAdmissionArtifact: malformed artifact JSON: " & e.msg)
  let payload = artifactPayloadFromEnvelope(node)
  if payload.isErr:
    return err("admission_artifact.readAdmissionArtifact: " & payload.error)
  let gotRunId = payload.get.getOrDefault("runId").getStr("")
  let gotRunAttempt = payload.get.getOrDefault("runAttempt").getStr("")
  if gotRunId != runId or gotRunAttempt != runAttempt:
    return err("admission_artifact.readAdmissionArtifact: entry " & want &
      " runId/runAttempt (" & gotRunId & "/" & gotRunAttempt &
      ") != requested (" & runId & "/" & runAttempt & ") (fail-closed)")
  ok(node)

proc artifactExistsAtTip*(transport: LedgerTransport; repo: string; digest: string;
                          refName: string = AdmissionsRefName): Result[bool, string]
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## TRUE iff a blob with `digest` already exists anywhere under the side-ref
  ## tip tree. The blob path is `<digest>.json` — the append side names entries
  ## by payload digest so idempotency is a tree membership test. A read error
  ## fails closed.
  if repo.len == 0 or digest.len == 0:
    return err("admission_artifact.artifactExistsAtTip: empty repo or digest")
  let tip = transport.tip(repo)
  if tip.isErr:
    return err("admission_artifact.artifactExistsAtTip: " & tip.error)
  if tip.get.len == 0:
    return ok(false)
  let tree = fetchTipTree(transport, repo, tip.get, "admission_artifact.artifactExistsAtTip")
  if tree.isErr:
    return err(tree.error)
  let want = digest & ".json"
  for entry in tree.get{"tree"}.getElems():
    if entry.getOrDefault("type").getStr("") != "blob":
      continue
    if entry.getOrDefault("path").getStr("") == want:
      return ok(true)
  ok(false)

# ---------------------------------------------------------------------------
# Write side — ONE FF-only append per admissions ref (CAS, no force)
# ---------------------------------------------------------------------------

proc appendAdmissionArtifact*(transport: LedgerTransport; repo, artifactPath: string;
                              refName: string = AdmissionsRefName): Result[string, string]
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Append the artifact file to the admissions side ref. The ref tip is read
  ## (or rooted when absent); the object pipeline (blob → tree(base=tip) →
  ## commit(parent=tip)) is the SAME one the certificate ledger uses; the ref
  ## update is a FF-only CAS PATCH (force=false). Fail-closed at every step.
  ## Idempotency is the caller's job (artifactExistsAtTip before calling).
  if repo.len == 0 or artifactPath.len == 0:
    return err("admission_artifact.appendAdmissionArtifact: empty repo or path")
  let text =
    try: readFile(artifactPath)
    except CatchableError as e:
      return err("admission_artifact.appendAdmissionArtifact: artifact unreadable: " & e.msg)
  if text.len == 0:
    return err("admission_artifact.appendAdmissionArtifact: artifact file is empty (fail-closed)")
  var node: JsonNode
  try:
    node = parseJson(text)
  except CatchableError as e:
    return err("admission_artifact.appendAdmissionArtifact: malformed artifact JSON: " & e.msg)
  let payload = artifactPayloadFromEnvelope(node)
  if payload.isErr:
    return err("admission_artifact.appendAdmissionArtifact: " & payload.error)
  let digest = admissionPayloadDigest(payload.get)
  if digest.isErr:
    return err("admission_artifact.appendAdmissionArtifact: " & digest.error)
  let entryName = digest.get & ".json"
  let blobContent = canonicalJsonString(node)
  let tipRes = transport.tip(repo)
  if tipRes.isErr:
    return err("admission_artifact.appendAdmissionArtifact: tip read failed: " & tipRes.error)
  var tip = tipRes.get
  if tip.len == 0:
    let rootRes = createLedgerRoot(transport, repo, refName)
    if rootRes.isErr:
      return err("admission_artifact.appendAdmissionArtifact: root creation failed: " & rootRes.error)
    tip = rootRes.get
  let objects = createLedgerObjects(transport, repo, blobContent, tip, entryName[0 ..< entryName.len - ".json".len])
  if objects.isErr:
    return err("admission_artifact.appendAdmissionArtifact: " & objects.error)
  let refUrl = GitHubApiBase & "/repos/" & repo & "/git/refs/" & singleRefApiPath(refName)
  let refResp = transport.patch(refUrl, $(%*{"sha": objects.get, "force": false}))
  if refResp.isErr:
    return err("admission_artifact.appendAdmissionArtifact: ref update failed (non-FF / ref moved?): " &
      refResp.error)
  let updated = shaFromObject(refResp.get)
  if updated.isErr:
    return err("admission_artifact.appendAdmissionArtifact: " & updated.error)
  ok(updated.get)

{.pop.}