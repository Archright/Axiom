## src/core/debt/debt_audit.nim — Audit input/snapshot + replay runtime.
##
## Phase 7/8: Audit input/snapshot + replay runtime.
## Builds on the committed keystone identity types in `src/core/types/debt_types.nim`.
##
## Deliverables:
##   buildAuditInput  — construct an AuditInputManifest from current evidence
##   recordAuditRun   — append a completed audit run to the journal
##   readAuditRuns    — read all audit runs from a journal
##   replayExact      — verify a stored run is reproducible (byte-level replay)
##   reevaluate       — produce a new manifest with a different rule set hash

import core/trusted/layer_declaration
axiomLayer "domain"

import std/[strutils, json, os, sequtils, options]
import checksums/sha2
import core/axiom_pragmas
import core/types/debt_types
import core/trusted/append_store
import core/debt/debt_observation

# ---------------------------------------------------------------------------
# JSON serialization helpers for AuditRun journal records
#
# Journal record format (JSON per line) includes replay metadata
# (manifest, ordinal, nonce) alongside the AuditRun fields so that
# replayExact can re-derive and verify the run identity without
# external state.
# ---------------------------------------------------------------------------

func auditRunRecordToJson*(run: AuditRun; manifest: AuditInputManifest; ordinal: int; nonce: string): JsonNode {.raises: [].} =
  %*{
    "auditInputId": raw(run.auditInputId),
    "auditRunId": raw(run.auditRunId),
    "resultRoot": raw(run.resultRoot),
    "recordedAt": run.recordedAt,
    "manifest": %*{
      "repositorySnapshot": manifest.repositorySnapshot,
      "evidenceRoot": raw(manifest.evidenceRoot),
      "provenanceRoot": raw(manifest.provenanceRoot),
      "artifactRoot": raw(manifest.artifactRoot),
      "executionRoot": raw(manifest.executionRoot),
      "ruleSetHash": manifest.ruleSetHash,
      "toolchainContext": manifest.toolchainContext
    },
    "ordinal": ordinal,
    "nonce": nonce
  }

func auditRunRecordFromJson*(node: JsonNode): Option[(AuditRun, AuditInputManifest, int, string)] {.raises: [CatchableError], axiomDecision(
  id = "DECISION-0657",
  reason = "Parse a canonical journal JSON record into its AuditRun, manifest, ordinal, and nonce components",
  adr = "docs/adr/0001-fail-closed-result-type.md",
  introduced = "v33"
).} =
  ## Parse a canonical journal JSON record into its components.
  ## Returns none for structurally invalid records.
  if node.isNil or node.kind != JObject:
    return none((AuditRun, AuditInputManifest, int, string))
  if not (node.hasKey("auditInputId") and node.hasKey("auditRunId") and
          node.hasKey("resultRoot") and node.hasKey("recordedAt") and
          node.hasKey("manifest") and node.hasKey("ordinal") and
          node.hasKey("nonce")):
    return none((AuditRun, AuditInputManifest, int, string))

  # AuditInputId has a validated constructor; AuditRunId / ContentDigest are
  # constructed by us via sha256Ref so direct distinct-cast is safe here.
  let inputIdRaw = node["auditInputId"].getStr()
  if not isValidSha256Ref(inputIdRaw):
    return none((AuditRun, AuditInputManifest, int, string))
  let inputId = AuditInputId(inputIdRaw)
  let runId = AuditRunId(node["auditRunId"].getStr())
  let resultRoot = ContentDigest(node["resultRoot"].getStr())

  let mNode = node["manifest"]
  let manifest = AuditInputManifest(
    repositorySnapshot: mNode["repositorySnapshot"].getStr(),
    evidenceRoot: ContentDigest(mNode["evidenceRoot"].getStr()),
    provenanceRoot: ContentDigest(mNode["provenanceRoot"].getStr()),
    artifactRoot: ContentDigest(mNode["artifactRoot"].getStr()),
    executionRoot: ContentDigest(mNode["executionRoot"].getStr()),
    ruleSetHash: mNode["ruleSetHash"].getStr(),
    toolchainContext: mNode["toolchainContext"].getStr()
  )
  let ordinal = node["ordinal"].getInt()
  let nonce = node["nonce"].getStr()

  some((AuditRun(
    auditInputId: inputId,
    auditRunId: runId,
    resultRoot: resultRoot,
    recordedAt: node["recordedAt"].getStr()
  ), manifest, ordinal, nonce))

# ---------------------------------------------------------------------------
# 1. buildAuditInput
# ---------------------------------------------------------------------------

func buildAuditInput*(evRoot: ContentDigest; ruleSetHash, toolchain: string): AuditInputManifest {.raises: [].} =
  ## Build an AuditInputManifest capturing the current evidence roots.
  ##
  ## The evidenceRoot is content-addressed over the provided digest.
  ## To compute a deterministic evidence root from observations, callers
  ## can read observations via `readObservations` and hash the sorted
  ## digests:
  ##   sha256Ref("evidence-root:", sortedDigests.join("\x1e"))
  ## All other roots are initialized to empty digests; callers should
  ## fill them in as the audit captures more context.
  AuditInputManifest(
    repositorySnapshot: "",
    evidenceRoot: evRoot,
    provenanceRoot: ContentDigest(""),
    artifactRoot: ContentDigest(""),
    executionRoot: ContentDigest(""),
    ruleSetHash: ruleSetHash,
    toolchainContext: toolchain
  )

# ---------------------------------------------------------------------------
# 3. readAuditRuns  (defined before recordAuditRun which calls it)
# ---------------------------------------------------------------------------

proc readAuditRuns*(journalPath: string): seq[AuditRun]
    {.raises: [], axiomEffect: IOEffect, axiomDecision(id = "DECISION-0751", reason = "Read audit run records from append-store journal", adr = "docs/adr/0001-fail-closed-result-type.md", introduced = "v34").} =
  let lines = readRecords(journalPath)
  var runs: seq[AuditRun]
  for line in lines:
    let stripped = line.strip(chars = {' ', '\t', '\r'})
    if stripped.len == 0:
      continue
    try:
      let node = parseJson(stripped)
      let recordOpt = auditRunRecordFromJson(node)
      if recordOpt.isSome():
        runs.add(recordOpt.get()[0])
    except CatchableError:
      discard  # fail-open on corrupt record
  runs

# ---------------------------------------------------------------------------
# 2. recordAuditRun  (uses readAuditRuns — defined above)
# ---------------------------------------------------------------------------

proc recordAuditRun*(manifest: AuditInputManifest; resultRoot: ContentDigest; nonce: string; journalPath: string = "data/debt/audits/runs.journal"): AuditRun
    {.raises: [], axiomEffect: IOEffect, axiomDecision(id = "DECISION-0750", reason = "Append audit run record to durable journal with deterministic ordinal", adr = "docs/adr/0001-fail-closed-result-type.md", introduced = "v34").} =
  let inputId = manifestInputId(manifest)
  # Count existing runs for the same auditInputId to derive deterministic ordinal (I10).
  let existingRuns = readAuditRuns(journalPath)
  var ordinal = 0
  for run in existingRuns:
    if run.auditInputId == inputId:
      ordinal += 1
  let runId = newAuditRunId(inputId, ordinal, nonce)
  let run = AuditRun(
    auditInputId: inputId,
    auditRunId: runId,
    resultRoot: resultRoot,
    recordedAt: ""  # metadata — never part of the run id (I10)
  )
  let jsonLine = $auditRunRecordToJson(run, manifest, ordinal, nonce)
  let _ = appendRecord(journalPath, jsonLine)
  run

# ---------------------------------------------------------------------------
# 4. replayExact
# ---------------------------------------------------------------------------

proc replayExact*(runId: AuditRunId; journalPath: string): tuple[ok: bool, reason: string]
    {.raises: [], axiomEffect: IOEffect, axiomDecision(id = "DECISION-0752", reason = "Verify stored audit run is reproducible by re-deriving run identity from manifest+ordinal+nonce", adr = "docs/adr/0001-fail-closed-result-type.md", introduced = "v34").} =
  ## Verify that a stored audit run is reproducible (byte-level replay).
  ## Re-derives auditInputId and auditRunId from the stored manifest +
  ## ordinal + nonce and checks that the derived runId equals the stored one.
  let lines = readRecords(journalPath)
  for line in lines:
    let stripped = line.strip(chars = {' ', '\t', '\r'})
    if stripped.len == 0:
      continue
    try:
      let node = parseJson(stripped)
      if not node.hasKey("auditRunId") or node["auditRunId"].getStr() != raw(runId):
        continue
      # Found the matching run — now re-derive from manifest + ordinal + nonce.
      if not node.hasKey("manifest") or not node.hasKey("ordinal") or not node.hasKey("nonce"):
        return (ok: false, reason: "stored run record missing replay metadata (manifest/ordinal/nonce)")
      let mNode = node["manifest"]
      if mNode.kind != JObject:
        return (ok: false, reason: "manifest field is not a JSON object")
      let manifest = AuditInputManifest(
        repositorySnapshot: mNode["repositorySnapshot"].getStr(),
        evidenceRoot: ContentDigest(mNode["evidenceRoot"].getStr()),
        provenanceRoot: ContentDigest(mNode["provenanceRoot"].getStr()),
        artifactRoot: ContentDigest(mNode["artifactRoot"].getStr()),
        executionRoot: ContentDigest(mNode["executionRoot"].getStr()),
        ruleSetHash: mNode["ruleSetHash"].getStr(),
        toolchainContext: mNode["toolchainContext"].getStr()
      )
      let ordinal = node["ordinal"].getInt()
      let nonce = node["nonce"].getStr()
      let derivedInputId = manifestInputId(manifest)
      let derivedRunId = newAuditRunId(derivedInputId, ordinal, nonce)
      if derivedRunId == runId:
        return (ok: true, reason: "")
      else:
        return (ok: false, reason: "derived auditRunId does not match stored auditRunId")
    except CatchableError:
      continue
  (ok: false, reason: "run not found in journal")

# ---------------------------------------------------------------------------
# 5. reevaluate
# ---------------------------------------------------------------------------

func reevaluate*(manifest: AuditInputManifest; newRuleSetHash: string): AuditInputManifest {.raises: [].} =
  ## Return a new manifest with a different rule set hash, preserving all
  ## other roots so the AuditInputId changes (past evidence preserved).
  ## This supports the RE-EVALUATE replay mode: same past evidence,
  ## new rule set -> new classification.
  AuditInputManifest(
    repositorySnapshot: manifest.repositorySnapshot,
    evidenceRoot: manifest.evidenceRoot,
    provenanceRoot: manifest.provenanceRoot,
    artifactRoot: manifest.artifactRoot,
    executionRoot: manifest.executionRoot,
    ruleSetHash: newRuleSetHash,
    toolchainContext: manifest.toolchainContext
  )
