import core/trusted/layer_declaration
axiomLayer "trusted"
{.push raises: [].}

import std/json
import std/os
import std/options
import std/algorithm
import std/strutils
import core/crypto/hash_kernel
import core/results
import core/axiom_pragmas
import core/utils/io_utils
import core/utils/repo_root
import core/json/json_utils
import infrastructure/cas_index
import core/trusted/append_store
import core/trusted/scope_identity

## Trust Commit — the single authoritative state-transition record (I2/I3).
##
## A TrustCommit is NOT metadata describing multiple persistence artifacts; it is
## the canonicalized record of a full verification outcome, durably persisted as
## exactly one immutable journal file `data/trusted/journal/<commitId>.json` (I3).
##
##   file == one TrustCommit
##
## Durability (I6): write(`<commitId>.tmp`) -> fsync -> rename(`<commitId>.json`)
## -> fsync(parentDir). The atomic rename IS the commit marker; a crash before it
## leaves only an ignored `.tmp`, after it the record is durable. See append_store.
##
## Identity:
##   evidenceId = H(claim || solverInvocation || certificateDigest)   # content identity
##   commitId   = H(kind || evidenceId || scopeDigest || configDigest || parentCommit)  # state-transition identity
##
## Invariant I5 (fail-closed): validateCommit rejects a commit whose structural
## invariants are violated (missing required fields, identity mismatch, parent
## not referenced), so replay cannot build a corrupt trust state silently.
##
## Only commitVerification() is the production trust-mutation API (I2). The
## verification pipeline must never write durable trust state directly (I7).

type
  TrustCommitKind* = enum
    tcVerifiedProof   ## a single authoritative verification outcome
    tcQuarantine      ## a demotion/quarantine transition of an admitted certificate

  TrustCommit* = object
    ## Immutable state-transition record. One instance == one journal file.
    ## kind discriminates the transition semantics. For tcQuarantine only
    ## quarantineReason/originalStatus are meaningful; the verification fields
    ## stay populated with the (post-transition) certificate content so the
    ## evidenceId binding check in validateCommit holds uniformly. Serialization
    ## is deterministic regardless of kind.
    kind*: TrustCommitKind
    evidenceId*: string            ## content identity: H(claim||solver||cert)
    claim*: string                 ## canonical JSON of the VerifiedClaim (self-contained)
    solverInvocation*: string      ## canonical JSON of the SolverInvocation (self-contained)
    attestation*: string           ## attestation / proof-carrying payload (self-contained)
    certificateDigest*: string     ## digest of the promoted certificate artifact
    scopeDigest*: string           ## canonical verification-scope identity
    configDigest*: string          ## canonical config identity
    parentCommit*: Option[string]  ## optional previous commitId (chain)
    projection*: string            ## optional certificate/Z3/V2 projection JSON captured with this commit
    quarantineReason*: string      ## tcQuarantine: why the certificate was demoted
    originalStatus*: string        ## tcQuarantine: certificate status before demotion
  CommitId* = string

  TrustedState* = object
    ## Reconstructed authoritative trust state from journal replay (I4).
    ## commitIds is parent-chain ordered (chronological); stateDigest binds the
    ## whole admitted set so ax verify can trust replay results, not raw certs.
    commitIds*: seq[CommitId]
    scopeDigest*: string
    configDigest*: string
    stateDigest*: string

## Journal file layout.
func journalDir*(baseDir: string): string =
  baseDir / "data" / "trusted" / "journal"

func commitPath*(baseDir: string; commitId: CommitId): string =
  journalDir(baseDir) / (commitId & ".json")

# ---------------------------------------------------------------------------
# Identity
# ---------------------------------------------------------------------------

func computeEvidenceId*(
  claim: string; solverInvocation: string; certificateDigest: string
): string {.raises: [].} =
  ## Content identity of the evidence captured by this commit. Order-sensitive
  ## and domain-separated via combineHashes.
  combineHashes([claim, solverInvocation, certificateDigest])

func computeCommitId*(
  kind: TrustCommitKind; evidenceId, scopeDigest, configDigest: string;
  parentCommit: Option[string]
): string {.raises: [].} =
  ## State-transition identity — a changed scope/config/parent yields a distinct
  ## commit id, so replay can detect stale or divergent chains.
  let parentPart = if parentCommit.isSome: parentCommit.get else: ""
  combineHashes([$kind, evidenceId, scopeDigest, configDigest, parentPart])

proc repoRootForPath*(path: string): string {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect], sideEffect.} =
  ## Root discovery delegates to the SSOT (core/utils/repo_root). This surface
  ## keeps the ""-on-miss contract: the SSOT's legacy parentDir fallback is
  ## masked by re-verifying the anchor, so callers' empty-string branches
  ## (legacy baseDir / currentDir fallbacks) stay exact.
  let resolved = findRepoRoot(path)
  if fileExists(resolved / axiomRoot):
    return resolved
  ""

template activeJournalRoot*(fallback: string = ""): string =
  ## DECISION-0673: the ONE root whose `data/trusted/journal` subtree is the
  ## TrustCommit journal — state relocation (AXIOM_STATE_DIR) > repo anchor >
  ## explicit fallback > CWD. Verification commits, promotion commits, closure
  ## reads and VKD admission must all resolve this same root; a producer
  ## writing under one root while a consumer reads another makes valid evidence
  ## invisible. A template (not a proc) keeps the core proc-to-func invariant.
  block:
    let sr = getEnv("AXIOM_STATE_DIR", "").strip()
    if sr.len > 0:
      sr
    else:
      let root = repoRootForPath(if fallback.len > 0: fallback else: getCurrentDir())
      if root.len > 0:
        root
      elif fallback.len > 0:
        fallback
      else:
        getCurrentDir()

func certificateScopeDigestForPair*(modulePath, functionName: string): string {.raises: [].} =
  canonicalScopeDigest(CanonicalScopeInput(
    kernelSymbols: @[modulePath & "::" & functionName],
    kernelExemptSymbols: @[],
    kernelTotal: 1,
    vksTotal: 0,
    profileIdentity: "wave5-cert-writer",
    protocolVersion: "axiom-wave5-cert-writer-v1"))

func certificateConfigDigestForPair*(
  modulePath, functionName, solverStatus, irHash, leanProposition, semanticProfileId: string
): string {.raises: [].} =
  let profileIdentity = if semanticProfileId.len > 0: semanticProfileId else: "SPV1"
  let scopeLockHash = sha256Hex([
    modulePath,
    functionName,
    solverStatus,
    irHash,
    leanProposition,
    profileIdentity
  ].join("|"))
  configIdentityDigest(profileIdentity, scopeLockHash)

func claimForCertificate(certJson: JsonNode): string {.raises: [CatchableError].} =
  renderJsonMultiline(certJson)

func trustCommitFromJson*(
  claimJson: JsonNode; solverInvocation, attestation, modulePath, functionName,
  solverStatus, irHash, leanProposition, semanticProfileId: string
): TrustCommit {.raises: [CatchableError].} =
  let claim = claimForCertificate(claimJson)
  let projection = claim
  let certificateDigest = sha256Hex(claim)
  TrustCommit(
    kind: tcVerifiedProof,
    evidenceId: computeEvidenceId(claim, solverInvocation, certificateDigest),
    claim: claim,
    solverInvocation: solverInvocation,
    attestation: attestation,
    certificateDigest: certificateDigest,
    scopeDigest: certificateScopeDigestForPair(modulePath, functionName),
    configDigest: certificateConfigDigestForPair(
      modulePath, functionName, solverStatus, irHash, leanProposition, semanticProfileId),
    parentCommit: none(string),
    projection: projection
  )

func certificateTrustCommit*(
  certJson: JsonNode; modulePath, functionName, solverStatus, irHash,
  leanProposition, semanticProfileId: string
): TrustCommit {.raises: [CatchableError].} =
  trustCommitFromJson(
    certJson, "batch-uap-loop",
    "UAP loop certificate projection captured in TrustCommit journal",
    modulePath, functionName, solverStatus, irHash, leanProposition, semanticProfileId)

func quarantineTrustCommit*(
  certJson: JsonNode; reason, originalStatus: string
): TrustCommit {.raises: [CatchableError], axiomDecision(id = "DECISION-0644", reason = "Build a tcQuarantine TrustCommit recording a certificate demotion transition; binds the post-transition certificate content via evidenceId so the record is replay-valid and the quarantine is an authoritative trust-state transition", adr = "docs/adr/0001-fail-closed-result-type.md", introduced = "v33").} =
  ## Build a tcQuarantine commit recording a certificate demotion transition.
  ## `certJson` is the post-demotion certificate content (status=certPending).
  ## The evidenceId binds this record to the actual demoted content, so replay
  ## of the journal faithfully reconstructs the quarantine transition (I4).
  let claim = claimForCertificate(certJson)
  let certificateDigest = sha256Hex(claim)
  TrustCommit(
    kind: tcQuarantine,
    evidenceId: computeEvidenceId(claim, "quarantine-transition", certificateDigest),
    claim: claim,
    solverInvocation: "quarantine-transition",
    attestation: "quarantine transition record",
    certificateDigest: certificateDigest,
    scopeDigest: certificateScopeDigestForPair("certificate-manager", "quarantineCertificate"),
    configDigest: certificateConfigDigestForPair("certificate-manager", "quarantineCertificate", "quarantined", "", "", ""),
    parentCommit: none(string),
    projection: claim,
    quarantineReason: reason,
    originalStatus: originalStatus
  )

proc commitVerification*(
  baseDir: string; c: TrustCommit
): Result[CommitId, string] {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].}

proc commitJsonVerification*(
  baseDir: string; claimJson: JsonNode; solverInvocation, attestation,
  modulePath, functionName, solverStatus, irHash, leanProposition, semanticProfileId: string
): Result[CommitId, string] {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  commitVerification(
    baseDir,
    trustCommitFromJson(
      claimJson, solverInvocation, attestation, modulePath, functionName,
      solverStatus, irHash, leanProposition, semanticProfileId))

proc commitCertificateVerification*(
  baseDir: string; certJson: JsonNode; modulePath, functionName, solverStatus, irHash,
  leanProposition, semanticProfileId: string
): Result[CommitId, string] {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  # Route the journal through the single authority every producer and consumer
  # resolves. The caller's `baseDir` is a write vault, NOT a journal identity:
  # without this, a temp vault dir becomes a second journal root and the
  # report's closure cannot see the commit it just wrote.
  commitVerification(activeJournalRoot(), certificateTrustCommit(certJson, modulePath, functionName, solverStatus, irHash, leanProposition, semanticProfileId))

# ---------------------------------------------------------------------------
# Structural validation (I5, fail-closed)
# ---------------------------------------------------------------------------

func validateCommit*(c: TrustCommit): Result[void, string] {.axiomDecision(id = "DECISION-0640", reason = "Structural fail-closed validation gate for TrustCommit; rejects tampered/empty records before admission to trust state", adr = "docs/adr/0012-ax-vkd-sync.md", introduced = "v33").} =
  ## Reject a commit whose structural invariants are violated. Fail-closed: a
  ## corrupt commit must not be admitted to the trust state.
  if c.kind != tcVerifiedProof and c.kind != tcQuarantine:
    return err("trust_commit: unsupported kind")
  if c.evidenceId.len == 0:
    return err("trust_commit: empty evidenceId")
  if c.claim.len == 0:
    return err("trust_commit: empty claim")
  if c.solverInvocation.len == 0:
    return err("trust_commit: empty solverInvocation")
  if c.kind == tcQuarantine:
    if c.quarantineReason.len == 0:
      return err("trust_commit: quarantine commit missing reason")
    if c.originalStatus.len == 0:
      return err("trust_commit: quarantine commit missing originalStatus")
  if c.scopeDigest.len == 0:
    return err("trust_commit: empty scopeDigest")
  if c.configDigest.len == 0:
    return err("trust_commit: empty configDigest")
  # Recompute content identity from embedded payloads; a mismatch means the
  # evidenceId does not bind to the actual content (tamper / serialization drift).
  let expectEvidence = computeEvidenceId(c.claim, c.solverInvocation, c.certificateDigest)
  if expectEvidence != c.evidenceId:
    return err("trust_commit: evidenceId does not match embedded content")
  Result[void, string](ok: true)

# ---------------------------------------------------------------------------
# Serialization
# ---------------------------------------------------------------------------

func projectionToJson(c: TrustCommit): JsonNode {.raises: [].} =
  if c.projection.len == 0:
    newJNull()
  else:
    %c.projection

proc commitToJson*(c: TrustCommit): string {.raises: [].} =
  ## Canonical JSON serialization of a TrustCommit (self-contained).
  ## Projection payloads are preserved as a JSON string/null field for
  ## deterministic, side-effect-free serialization.
  let o = %*{
    "kind": $c.kind,
    "evidenceId": c.evidenceId,
    "claim": c.claim,
    "solverInvocation": c.solverInvocation,
    "attestation": c.attestation,
    "certificateDigest": c.certificateDigest,
    "scopeDigest": c.scopeDigest,
    "configDigest": c.configDigest,
    "parentCommit": if c.parentCommit.isSome: newJString(c.parentCommit.get) else: newJNull(),
    "projection": projectionToJson(c),
    "quarantineReason": c.quarantineReason,
    "originalStatus": c.originalStatus
  }
  renderJsonMultiline(o)

proc commitFromJson*(text: string): Result[TrustCommit, string] {.raises: [], axiomDecision(id = "DECISION-0636", reason = "Strict TrustCommit JSON deserialization; malformed required fields fail closed", adr = "docs/adr/0001-fail-closed-result-type.md", introduced = "v33").} =
  ## Parse a TrustCommit from its canonical JSON. Strict: any malformed required
  ## field fails closed.
  let parsedOpt = parseJsonOpt(text)
  if parsedOpt.isNone:
    return err("trust_commit: malformed JSON")
  let parsed = parsedOpt.get()
  if parsed.kind != JObject:
    return err("trust_commit: malformed JSON: expected object")
  let kindStr = parsed{"kind"}.getStr("")
  var kind: TrustCommitKind
  case kindStr
  of "tcVerifiedProof": kind = tcVerifiedProof
  of "tcQuarantine": kind = tcQuarantine
  else: return err("trust_commit: unknown kind '" & kindStr & "'")
  var c = TrustCommit(kind: kind)
  c.evidenceId = parsed{"evidenceId"}.getStr("")
  c.claim = parsed{"claim"}.getStr("")
  c.solverInvocation = parsed{"solverInvocation"}.getStr("")
  c.attestation = parsed{"attestation"}.getStr("")
  c.certificateDigest = parsed{"certificateDigest"}.getStr("")
  c.scopeDigest = parsed{"scopeDigest"}.getStr("")
  c.configDigest = parsed{"configDigest"}.getStr("")
  c.quarantineReason = parsed{"quarantineReason"}.getStr("")
  c.originalStatus = parsed{"originalStatus"}.getStr("")
  if parsed{"projection"}.kind == JObject:
    c.projection = renderJsonMultiline(parsed{"projection"})
  else:
    c.projection = parsed{"projection"}.getStr("")
  if parsed{"parentCommit"}.kind == JString:
    c.parentCommit = some(parsed{"parentCommit"}.getStr(""))
  else:
    c.parentCommit = none(string)
  ok(c)

# ---------------------------------------------------------------------------
# Durable persistence
# ---------------------------------------------------------------------------

proc commitVerification*(
  baseDir: string; c: TrustCommit
): Result[CommitId, string] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## I2 — the ONLY production trust-mutation API. Canonicalize + validate, then
  ## durably persist exactly one immutable journal file. Returns the commitId.
  let valid = validateCommit(c)
  if not valid.ok:
    return err("trust_commit: validation failed: " & valid.error)
  let cid = computeCommitId(c.kind, c.evidenceId, c.scopeDigest, c.configDigest, c.parentCommit)
  let dir = journalDir(baseDir)
  if not dirExists(dir):
    try:
      createDir(dir)
    except CatchableError as e:
      return err("trust_commit: cannot create journal dir: " & e.msg)
  if not writeRecord(commitPath(baseDir, cid), commitToJson(c)):
    return err("trust_commit: durable write failed for " & cid)
  ok(cid)

proc readCommit*(baseDir: string; commitId: CommitId): Result[TrustCommit, string] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect], raises: [CatchableError], axiomDecision(id = "DECISION-0637", reason = "Read a single immutable TrustCommit journal record; absent/corrupt fails closed so replay cannot build corrupt state", adr = "docs/adr/0001-fail-closed-result-type.md", introduced = "v33").} =
  ## Read a single immutable commit by id. Fail-closed on absence / corruption:
  ## the parsed record must pass validateCommit AND its recomputed state-transition
  ## identity (computeCommitId over the record's content) must equal the requested
  ## commitId. A journal file whose content was tampered after admission (or moved
  ## onto a foreign id) therefore never reads back as trusted state — the filename
  ## alone is not identity; content addresses it.
  let p = commitPath(baseDir, commitId)
  if not fileExists(p):
    return err("trust_commit: no commit '" & commitId & "'")
  let res = readFileOpt(p)
  if not res.ok:
    return err("trust_commit: read failed: " & res.error)
  let parsed = commitFromJson(res.value)
  if not parsed.ok:
    return err(parsed.error)
  let valid = validateCommit(parsed.value)
  if not valid.ok:
    return err("trust_commit: validation failed for '" & commitId & "': " & valid.error)
  let recomputedId = computeCommitId(parsed.value.kind, parsed.value.evidenceId,
                                     parsed.value.scopeDigest, parsed.value.configDigest,
                                     parsed.value.parentCommit)
  if recomputedId != commitId:
    return err("trust_commit: content-addressing mismatch for '" & commitId &
               "' (record content hashes to '" & recomputedId & "')")
  parsed

# ---------------------------------------------------------------------------
# Journal replay (I4) — reconstruct authoritative trust state from commits.
# ---------------------------------------------------------------------------

proc listCommitIds*(baseDir: string): Result[seq[CommitId], string] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect], axiomDecision(id = "DECISION-0638", reason = "Enumerate immutable commit journal files; skips non-.json (.tmp orphans) so a crash mid-commit is invisible to replay", adr = "docs/adr/0001-fail-closed-result-state.md", introduced = "v33").} =
  ## Enumerate every durable commit id in the journal. `.tmp` orphans (a crash
  ## before atomic rename) are ignored — only rename-committed files are trusted.
  let dir = journalDir(baseDir)
  if not dirExists(dir):
    return ok(newSeq[CommitId]())
  var ids: seq[CommitId] = @[]
  let listing = walkDirOpt(dir)
  if not listing.ok:
    return err("trust_commit: cannot list journal: " & listing.error)
  for p in listing.value:
    let n = extractFilename(p)
    if n.endsWith(".json"):
      ids.add(n[0 ..< n.len - ".json".len])
  ids.sort()
  ok(ids)

func computeStateDigest*(commitIds: openArray[CommitId]): string {.raises: [].} =
  ## Deterministic digest over the ordered, validated commit set. Any divergence
  ## in chain order/content changes the digest (I5 completes-against-stale).
  combineHashes(commitIds)

func placedContains*(placed: seq[string]; id: string): bool {.inline, raises: [].} =
  for p in placed:
    if p == id:
      return true
  false

proc replayJournal*(baseDir: string): Result[TrustedState, string] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect], raises: [CatchableError], axiomDecision(id = "DECISION-0639", reason = "Rebuild authoritative trust state from journal; validates every commit, orders by parent chain, recomputes final state digest — fail-closed on corruption/order breach", adr = "docs/adr/0001-fail-closed-result-state.md", introduced = "v33").} =
  ## Reconstruct trust state by replaying the journal (I4). Each commit is
  ## validated (structural + evidenceId binding); if ANY is corrupt the whole
  ## replay fails closed — no partial trust state is emitted.
  let ids = listCommitIds(baseDir)
  if not ids.ok:
    return err("trust_commit.replayJournal: " & ids.error)
  if ids.value.len == 0:
    return ok(TrustedState(commitIds: @[], scopeDigest: "", configDigest: "", stateDigest: computeStateDigest(@[])))

  # Load a commit's canonical JSON via the validated content-addressed read
  # (readCommit): absence/corruption/content-tamper is a hard replay error.
  proc parseAt(id: CommitId): Result[TrustCommit, string] {.raises: [], axiomDecision(id = "DECISION-0660", reason = "Load a single TrustCommit from its journal file by commitId for replay ordering", adr = "docs/adr/0001-fail-closed-result-type.md", introduced = "v33").} =
    try:
      readCommit(baseDir, id)
    except CatchableError as e:
      return err("trust_commit.replayJournal: read failed " & id & ": " & e.msg)

  # Order by parent-chain: a commit whose parent is absent is a root; a commit
  # whose parent references a non-existent / unknown commit id is an orphan and
  # fails closed.
  var chain: seq[CommitId] = @[]
  var placed: seq[string] = @[]
  var guard = 0
  while chain.len < ids.value.len and guard < ids.value.len * 2 + 8:
    inc guard
    var progressed = false
    for id in ids.value:
      if placed.contains(id):
        continue
      let c = parseAt(id)
      if not c.ok:
        return err("trust_commit.replayJournal: corrupt commit " & id & ": " & c.error)
      let parent = c.value.parentCommit
      if parent.isSome and not ids.value.contains(parent.get):
        return err("trust_commit.replayJournal: orphan parent '" & parent.get & "' referenced by commit " & id)
      if parent.isNone or placedContains(placed, parent.get):
        chain.add(id)
        placed.add(id)
        progressed = true
    if not progressed and chain.len < ids.value.len:
      return err("trust_commit.replayJournal: cycle or unplaceable commit set")

  # Validate every admitted commit (structural + tamper binding).
  var stateScope = ""
  var stateCfg = ""
  var i = 0
  for id in chain:
    let pc = parseAt(id)
    if not pc.ok:
      return err("trust_commit.replayJournal: invalid commit " & id & ": " & pc.error)
    let cv = validateCommit(pc.value)
    if not cv.ok:
      return err("trust_commit.replayJournal: invalid commit " & id & ": " & cv.error)
    if i == chain.len - 1:
      stateScope = pc.value.scopeDigest
      stateCfg = pc.value.configDigest
    inc i

  ok(TrustedState(commitIds: chain, scopeDigest: stateScope, configDigest: stateCfg,
                  stateDigest: computeStateDigest(chain)))

{.pop.}
