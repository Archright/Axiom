## src/infrastructure/debt_audit/audit_correlate.nim — Correlation, disposition & candidate freeze.
##
## Reads canonical findings (RuleResult JSON) and the debt registry to produce
## correlated results with classified dispositions, and freezes NEW findings as
## debt candidates.  Deterministic ordering by (ruleId, path).  ~300 lines.

import core/trusted/layer_declaration
axiomLayer "infrastructure"

import std/[algorithm, json, os, strutils, tables]
import core/axiom_pragmas
import infrastructure/debt_audit/audit_observations
import infrastructure/debt_audit/audit_rules

{.push raises: [].}

# ---------------------------------------------------------------------------
# Public types
# ---------------------------------------------------------------------------

## Disposition of a finding after correlation against the debt registry.
type Disposition* = enum
  ndNew             ## not in registry — brand-new debt candidate
  ndKnownOpen       ## registry entry exists and status is "open"
  ndKnownClosed     ## registry entry exists and status is "closed"
  ndKnownWontfix    ## registry entry exists and status is "accepted"
  ndDuplicate       ## registry entry exists and status is "duplicate"
  ndNonDebt         ## registry entry exists and status is "nonDebt"
  ndExempt          ## registry entry exists and status is "exempt"
  ndObservationOnly ## registry entry exists and status is "closed" (lifecycle note attached)

## Result of correlating a single finding against the debt registry.
type CorrelResult* = object
  finding*: string        ## finding key (ruleId:path)
  overlapsReg*: bool      ## true when path matched a registry entry
  regId*: string          ## registry entry id when overlapsReg is true; empty otherwise
  disposition*: Disposition
  lifecycleNote*: string  ## non-empty for ndObservationOnly ("KNOWN_CLOSED")

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

func normalizePath*(path: string): string {.raises: [].} =
  ## Strip leading "./" from a path for canonical comparison.
  result = path.strip()
  while result.startsWith("./"):
    result = result[2 .. ^1]

func findRegistryMatch*(findingPath: string; registry: JsonNode): tuple[matched: bool; entry: JsonNode] =
  ## Search registry top-level "entries" array for an entry whose "files" array
  ## contains `findingPath`.  Directory entries (entries whose "files" contains
  ## a path ending with "/" or whose id starts with "DIR#") are excluded.
  ## Returns (false, nil) when no match is found.
  result = (false, nil)
  if registry.isNil or registry.kind != JObject:
    return
  let entries = registry.getOrDefault("entries")
  if entries.isNil or entries.kind != JArray:
    return
  for entry in entries:
    if entry.isNil or entry.kind != JObject:
      continue
    let id = entry.getOrDefault("id").getStr("")
    # Skip directory entries.
    if id.startsWith("DIR#"):
      continue
    let files = entry.getOrDefault("files")
    if files.isNil or files.kind != JArray:
      continue
    for f in files:
      let fStr = f.getStr("")
      if fStr.endsWith("/"):
        continue  # directory entry — exclude per spec
      if normalizePath(fStr) == findingPath:
        result = (true, entry)
        return
  result = (false, nil)

func extractString*(node: JsonNode; key: string; default: string = ""): string {.raises: [].} =
  ## Safe string extraction from a JsonNode; returns `default` when missing or
  ## non-string.
  if node.isNil or node.kind != JObject:
    return default
  let v = node.getOrDefault(key)
  if v.isNil or v.kind != JString:
    default
  else:
    v.getStr(default)

func extractStrings*(node: JsonNode; key: string): seq[string] {.raises: [].} =
  ## Safe string-array extraction from a JsonNode; returns @[] when missing or
  ## non-array.
  result = @[]
  if node.isNil or node.kind != JObject:
    return
  let v = node.getOrDefault(key)
  if v.isNil or v.kind != JArray:
    return
  for item in v:
    if item.kind == JString:
      result.add(item.getStr(""))

# ---------------------------------------------------------------------------
# Disposition classification
# ---------------------------------------------------------------------------

proc classifyDisposition*(regEntry: JsonNode): tuple[disposition: Disposition; lifecycleNote: string] =
  ## Deterministic disposition lookup from a matched registry entry.
  ## Maps the entry's "status" string to the corresponding Disposition enum.
  ## Returns ndNew with empty note when `regEntry` is nil.
  if regEntry.isNil or regEntry.kind != JObject:
    return (ndNew, "")
  let status = regEntry.getOrDefault("status").getStr("").toLowerAscii().strip()
  case status
  of "open":
    (ndKnownOpen, "")
  of "closed":
    (ndObservationOnly, "KNOWN_CLOSED")
  of "accepted":
    (ndKnownWontfix, "")
  of "duplicate":
    (ndDuplicate, "")
  of "nondebt":
    (ndNonDebt, "")
  of "exempt":
    (ndExempt, "")
  else:
    # Unknown status string — treat as new to avoid false negatives.
    (ndNew, "")

# ---------------------------------------------------------------------------
# Correlation
# ---------------------------------------------------------------------------

proc correlate*(ctx: RuleCtx; findings: seq[RuleResult]; registry: JsonNode): seq[CorrelResult] =
  ## Correlate every finding against the debt registry.  Findings are sorted
  ## deterministically by (ruleId, path) before processing.  Each result
  ## records whether the finding's path overlaps a registry entry and the
  ## classified disposition.
  ##
  ## Path matching: normalize path (strip "./"), then compare against each
  ## registry entry's "files" array strings, excluding directory entries
  ## (paths ending with "/" or entries whose id starts with "DIR#").
  ##
  ## Disposition mapping:
  ##   open → ndKnownOpen
  ##   closed → ndObservationOnly + lifecycle="KNOWN_CLOSED"
  ##   accepted → ndKnownWontfix
  ##   duplicate → ndDuplicate
  ##   nondebt → ndNonDebt
  ##   exempt → ndExempt
  ##   anything else (including no match) → ndNew

  # Sort findings deterministically by (ruleId, path).
  var sortedFindings = findings
  sortedFindings.sort(proc(a, b: RuleResult): int =
    let cmpRule = cmp(a.ruleId, b.ruleId)
    if cmpRule != 0: cmpRule
    else: cmp(a.path, b.path)
  )

  for finding in sortedFindings:
    let normPath = normalizePath(finding.path)
    let (overlaps, entry) = findRegistryMatch(normPath, registry)
    let (disp, note) = classifyDisposition(if overlaps: entry else: nil)
    let findingKey = finding.ruleId & ":" & normPath
    result.add(CorrelResult(
      finding: findingKey,
      overlapsReg: overlaps,
      regId: if overlaps: extractString(entry, "id") else: "",
      disposition: disp,
      lifecycleNote: note
    ))

# ---------------------------------------------------------------------------
# Debt number helper
# ---------------------------------------------------------------------------

func nextDebtNum*(registry: JsonNode): int {.raises: [].} =
  ## Scan all registry entries, parse numeric suffix from every id that starts
  ## with "DEBT#", and return max + 1.  Returns 1 when no DEBT# entries exist.
  result = 1
  if registry.isNil or registry.kind != JObject:
    return
  let entries = registry.getOrDefault("entries")
  if entries.isNil or entries.kind != JArray:
    return
  for entry in entries:
    if entry.isNil or entry.kind != JObject:
      continue
    let id = entry.getOrDefault("id").getStr("")
    if not id.startsWith("DEBT#"):
      continue
    let numStr = id[5 .. ^1]  # strip "DEBT#"
    try:
      let n = parseInt(numStr)
      if n >= result:
        result = n + 1
    except ValueError:
      discard

# ---------------------------------------------------------------------------
# Candidate freeze
# ---------------------------------------------------------------------------

proc writeCandidates*(bundleDir: string; correlated: seq[CorrelResult]; registry: JsonNode): tuple[written: int; nextDebtNum: int] {.raises: [CatchableError], axiomEffect: IoEffect.} =
  ## Produce debt_candidates.json and manifest.json inside `bundleDir`.
  ##
  ## Only NEW findings (disposition == ndNew) become candidates.  Each
  ## candidate gets a unique id "DEBT#&nextNum", where nextNum is the
  ## existing maximum DEBT# numeric suffix in the registry + 1.
  ##
  ## Output files:
  ##   bundleDir/debt_candidates.json — serialized candidates array
  ##   bundleDir/manifest.json        — mapping findingKey → candidateId
  ##     plus written count and nextDebtNum.

  let num = nextDebtNum(registry)
  var nextNum = num
  var candidates: seq[JsonNode]
  var manifestMapping: Table[string, string]

  for cr in correlated:
    if cr.disposition != ndNew:
      continue  # skip observationOnly / duplicate / wontfix / nonDebt / exempt
    let candidateId = "DEBT#" & $nextNum
    nextNum += 1

    # Extract finding details from the correlated result.
    # findingKey format is "ruleId:path".
    let colonPos = cr.finding.find(':')
    let ruleId = if colonPos >= 0: cr.finding[0 ..< colonPos] else: cr.finding
    let path = if colonPos >= 0: cr.finding[colonPos + 1 .. ^1] else: cr.finding

    let candidate = %*{
      "id": candidateId,
      "finding_key": cr.finding,
      "rule_id": ruleId,
      "path": path,
      "severities": newJArray(),
      "recommended_action": "review_and_create_debt_entry",
      "source": "dir_doc_debt_audit_2026-08-17",
      "status": "open"
    }
    candidates.add(candidate)
    manifestMapping[cr.finding] = candidateId

  # Write debt_candidates.json
  let candidatesPath = bundleDir / "debt_candidates.json"
  let candidatesJson = %*{"candidates": candidates}
  writeFile(candidatesPath, candidatesJson.pretty())

  # Write manifest.json
  let manifestPath = bundleDir / "manifest.json"
  var manifestObj = initTable[string, JsonNode]()
  manifestObj["findingKey_to_candidateId"] = %*manifestMapping
  manifestObj["written"] = %candidates.len
  manifestObj["nextDebtNum"] = %(nextNum)
  let manifestJson = %manifestObj
  writeFile(manifestPath, manifestJson.pretty())

  (candidates.len, nextNum)

# ---------------------------------------------------------------------------
# Registry patch
# ---------------------------------------------------------------------------

proc registryPatchJson*(candidates: seq[CorrelResult]): JsonNode {.raises: [].} =
  ## Emit a JsonNode in registry "entries" format for the given candidates.
  ## Each candidate becomes a registry entry with fields: id, category,
  ## description, files:[…], severity, source, status: "open".
  ## No extra registry keys are invented.
  let entries = newJArray()
  for cr in candidates:
    if cr.disposition != ndNew:
      continue
    let colonPos = cr.finding.find(':')
    let path = if colonPos >= 0: cr.finding[colonPos + 1 .. ^1] else: cr.finding

    let entry = %*{
      "id": "",           # placeholder — caller assigns DEBT# id
      "category": "Audit Correlation",
      "description": cr.finding,
      "files": %*[@[path]],
      "severity": "medium",
      "source": "dir_doc_debt_audit_2026-08-17",
      "status": "open"
    }
    entries.add(entry)
  %*{"entries": entries}

{.pop.}
