## src/core/debt/debt_observation.nim — Observation append-only journal store.
##
## Provides deterministic serialization, content-addressing, and durable
## append-only storage for DebtObservation records. The journal is the
## single source of truth (SSOT); no per-file JSON-LD or separate index
## is maintained.

import core/trusted/layer_declaration
axiomLayer "domain"

import std/[strutils, tables, options]
import std/json
import checksums/sha2
import core/axiom_pragmas
import core/types/debt_types
import core/trusted/append_store
import core/utils/io_utils
import core/results

const observationsJournalPath* = "data/debt/observations.journal"

# ---------------------------------------------------------------------------
# Identity canonicalization (excludes snapshotId, observedAt)
# ---------------------------------------------------------------------------

func canonicalizeObservation*(obs: DebtObservation): string {.raises: [].} =
  ## Deterministic serialization for content-addressing.
  ## Fixed field order, newline-separated. Excludes snapshotId and observedAt
  ## from identity (they are stored in the record but not in the identity).
  ##
  ## For okMetricEvaluation kind, identity includes subject + observedValue +
  ## direction (ESKey-based dedup). All other kinds retain the original 6-field
  ## identity to preserve backward-compatible journal digests.
  case obs.kind
  of okMetricEvaluation:
    result = obs.subject & "\n" &
             $obs.observedValue & "\n" &
             obs.direction
  else:
    result = $obs.kind.int & "\n" &
             obs.subject & "\n" &
             obs.semanticIdentity & "\n" &
             obs.source & "\n" &
             obs.payload & "\n" &
             obs.toolchainContext

# ---------------------------------------------------------------------------
# Journal record canonicalization (includes observedAt, snapshotId)
# ---------------------------------------------------------------------------

func canonicalizeObservationRecord*(obs: DebtObservation): string {.raises: [].} =
  ## Deterministic serialization for journal storage.
  ## Includes observedAt and snapshotId as stored fields.
  result = $obs.kind.int & "\n" &
           obs.subject & "\n" &
           obs.semanticIdentity & "\n" &
           obs.snapshotId & "\n" &
           obs.source & "\n" &
           obs.payload & "\n" &
           obs.observedAt & "\n" &
           obs.toolchainContext

# ---------------------------------------------------------------------------
# Content-addressing
# ---------------------------------------------------------------------------

func observationDigest*(obs: DebtObservation): string {.raises: [].} =
  ## Content-address: sha256("obs:" & canonicalIdentity(obs)).
  ## snapshotId and observedAt are excluded from identity.
  "sha256:" & $Sha_256.secureHash("obs:" & canonicalizeObservation(obs))

# ---------------------------------------------------------------------------
# Journal record framing
#
# Canonical persistence format is JSONL: exactly one DebtObservation per line,
# serialized as a single JSON object. JSON escapes `|`, quotes and embedded
# newlines, so records whose subject/payload/observedAt/toolchainContext
# contain `|` (observed in the wild, e.g. "severity=high | status=closed")
# are unambiguous — no delimiter collision. Legacy `|`-delimited records are
# still parsed on read for backward compatibility with the pre-migration
# observation journal (735 lines committed before the framing fix).
# ---------------------------------------------------------------------------

func observationToJson*(obs: DebtObservation): JsonNode {.raises: [].} =
  var base = %*{
    "kind": $obs.kind,
    "subject": obs.subject,
    "semanticIdentity": obs.semanticIdentity,
    "snapshotId": obs.snapshotId,
    "source": obs.source,
    "payload": obs.payload,
    "observedAt": obs.observedAt,
    "toolchainContext": obs.toolchainContext
  }
  case obs.kind
  of okMetricEvaluation:
    base["observedValue"] = %obs.observedValue
    base["direction"] = %obs.direction
    base["status"] = %obs.status
  else:
    discard
  result = base

proc observationFromJson*(node: JsonNode): Option[DebtObservation] {.raises: [CatchableError], axiomDecision(
  id = "DECISION-0655",
  reason = "Parse a canonical JSON observation object into a DebtObservation; nil on structural mismatch",
  adr = "docs/adr/0001-fail-closed-result-type.md",
  introduced = "v33"
).} =
  ## Parse a canonical JSON observation object. Cheap shape validation; nil on
  ## any structural mismatch.
  if node.isNil or node.kind != JObject:
    return none(DebtObservation)
  if not (node.hasKey("kind") and node.hasKey("subject") and
          node.hasKey("semanticIdentity") and node.hasKey("snapshotId") and
          node.hasKey("source") and node.hasKey("payload") and
          node.hasKey("observedAt") and node.hasKey("toolchainContext")):
    return none(DebtObservation)
  let kindStr = node["kind"].getStr()
  # Canonical `$DebtObservation.kind` names. Avoids parseEnum's first-char
  # capitalization and its default-arg overload ambiguities.
  let kind: ObservationKind =
    case kindStr
    of "okSourceMarker": okSourceMarker
    of "okAstPattern": okAstPattern
    of "okCfgPattern": okCfgPattern
    of "okGateDeclaration": okGateDeclaration
    of "okGateExecution": okGateExecution
    of "okCertificate": okCertificate
    of "okProofArtifact": okProofArtifact
    of "okPromotion": okPromotion
    of "okMetric": okMetric
    of "okMetricEvaluation": okMetricEvaluation
    of "okDocumentClaim": okDocumentClaim
    of "okExternalClaim": okExternalClaim
    else: okSourceMarker
  # Phase 1 okMetricEvaluation fields (optional, present only for that kind)
  let observedValue = if node.hasKey("observedValue"): node["observedValue"].getInt(0) else: 0'i64
  let direction = if node.hasKey("direction"): node["direction"].getStr("") else: ""
  let status = if node.hasKey("status"): node["status"].getStr("") else: ""
  some(DebtObservation(
    kind: kind,
    subject: node["subject"].getStr(),
    semanticIdentity: node["semanticIdentity"].getStr(),
    snapshotId: node["snapshotId"].getStr(),
    source: node["source"].getStr(),
    payload: node["payload"].getStr(),
    observedAt: node["observedAt"].getStr(),
    toolchainContext: node["toolchainContext"].getStr(),
    observedValue: observedValue,
    direction: direction,
    status: status
  ))

func observationRecord*(obs: DebtObservation): string {.raises: [].} =
  ## Canonical journal line: one JSON object per line. No field delimiter is
  ## used, so embedded `|` in any field cannot corrupt the record.
  $observationToJson(obs)

func observationRecordLegacy*(obs: DebtObservation): string {.raises: [].} =
  ## Legacy `|`-delimited form, retained for reading pre-migration records.
  result = $obs.kind.int & "|" &
           obs.subject & "|" &
           obs.semanticIdentity & "|" &
           obs.snapshotId & "|" &
           obs.source & "|" &
           obs.payload & "|" &
           obs.observedAt & "|" &
           obs.toolchainContext

proc parseObservationLine*(line: string): Option[DebtObservation] {.axiomDecision(
  id = "DECISION-0656",
  reason = "Parse a journal line as either canonical JSON or legacy pipe-delimited form into a DebtObservation",
  adr = "docs/adr/0001-fail-closed-result-type.md",
  introduced = "v33"
).} =
  ## Parse a journal line: try canonical JSON first, then legacy `|` form.
  ## Returns none for unparseable lines. Fail-open on a single bad line so a
  ## corrupt record never silently drops the whole journal (bounded shell).
  let stripped = line.strip(chars = {' ', '\t', '\r'})
  if stripped.len == 0:
    return none(DebtObservation)
  if stripped[0] == '{':
    try:
      let n = parseJson(stripped)
      return observationFromJson(n)
    except CatchableError:
      discard  # fall through to legacy parse
    # fall through to legacy
  let fields = stripped.split("|")
  if fields.len < 8:
    return none(DebtObservation)
  var kind: ObservationKind
  try:
    kind = ObservationKind(fields[0].parseInt)
  except ValueError:
    return none(DebtObservation)
  some(DebtObservation(
    kind: kind,
    subject: fields[1],
    semanticIdentity: fields[2],
    snapshotId: fields[3],
    source: fields[4],
    payload: fields[5],
    observedAt: fields[6],
    toolchainContext: fields[7]
  ))

# ---------------------------------------------------------------------------
# Append / Read
# ---------------------------------------------------------------------------

proc appendObservation*(obs: DebtObservation; journalPath: string = observationsJournalPath): bool
    {.raises: [], axiomEffect: IOEffect, axiomDecision(id = "DECISION-0701", reason = "Append observation to durable journal with content-addressable ID; idempotent — rejects duplicate identity", adr = "docs/adr/0001-fail-closed-result-type.md", introduced = "v33").} =
  var obs = obs
  obs.observationId = observationDigest(obs)
  # Idempotent append: reject if same identity already present in journal.
  let existingRecords = readRecords(journalPath)
  for record in existingRecords:
    let existingOpt = parseObservationLine(record)
    if existingOpt.isSome:
      let existing = existingOpt.get()
      if canonicalizeObservation(existing) == canonicalizeObservation(obs):
        return false  # duplicate identity — no-op
  let _ = appendRecord(journalPath, observationRecord(obs))
  true

proc readObservations*(journalPath: string = observationsJournalPath): seq[string]
    {.raises: [], axiomEffect: IOEffect, axiomDecision(id = "DECISION-0702", reason = "Read observation records from append-store journal", adr = "docs/adr/0001-fail-closed-result-type.md", introduced = "v33").} =
  readRecords(journalPath)

# ---------------------------------------------------------------------------
# Minimal index utility (optional, redundant — journal is the SSOT)
# ---------------------------------------------------------------------------

proc rebuildIndex*(journalPath: string = observationsJournalPath): Table[string, string]
    {.raises: [], axiomEffect: IOEffect, axiomDecision(id = "DECISION-0703", reason = "Rebuild observation digest-to-record index from journal", adr = "docs/adr/0001-fail-closed-result-type.md", introduced = "v33").} =
  result = initTable[string, string]()
  let records = readRecords(journalPath)
  for record in records:
    let obsOpt = parseObservationLine(record)
    if obsOpt.isNone:
      continue
    let obs = obsOpt.get()
    let digest = observationDigest(obs)
    result[digest] = record

# ---------------------------------------------------------------------------
# Migration — rewrite a legacy `|`-delimited journal as canonical JSONL.
# ---------------------------------------------------------------------------

proc migrateJournalToJsonl*(journalPath: string = observationsJournalPath): int
    {.raises: [IOError, OSError], axiomEffect: IOEffect, axiomDecision(id = "DECISION-0704", reason = "Migrate legacy pipe-delimited observation journal to canonical JSONL framing", adr = "docs/adr/0001-fail-closed-result-type.md", introduced = "v34").} =
  ## Rewrite every legacy record in the journal as canonical JSONL in place.
  ## Returns the number of records written. Fail-open: records that parse
  ## neither as JSON nor legacy are dropped (counted via diff by caller).
  let records = readRecords(journalPath)
  var lines: seq[string]
  for record in records:
    let obsOpt = parseObservationLine(record)
    if obsOpt.isNone:
      continue
    lines.add(observationRecord(obsOpt.get()))
  if lines.len > 0:
    let writeRes = io_utils.writeFileAtomic(journalPath, lines.join("\n") & "\n")
    if writeRes.isErr():
      raise newException(OSError, writeRes.error)
  lines.len
