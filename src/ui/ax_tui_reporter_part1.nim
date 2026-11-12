import core/trusted/layer_declaration
axiomLayer "presentation"
{.push raises: [CatchableError].}

import cli/cli_types
import core/utils/constants
import core/utils/file_utils
import core/utils/text_utils
import std/json
import std/options
import std/strutils
import std/unicode
import cli/report_render
type

  AxProofEntry* = object
    id*: int
    label*: string
    status*: AxProofStatus
    engine*: string
    depth*: int
    impactIndex*: int
    premises*: int

  AxProofSummary* = object
    target*: string
    sourceRoot*: string
    timestamp*: string
    totalNodes*: int
    attemptedNodes*: int
    verified*: int
    counterExamples*: int
    vacuousContradictions*: int
    timedOut*: int
    unattempted*: int
    totalWallTimeMs*: int
    cpuEfficiency*: float
    cacheHits*: int
    shortcutState*: string
    stateFile*: string
    certificateVkdFixed4*: string
    vkdFixed4*: string
    engineVkdFixed4*: string
    weightedVkdFixed4*: string
    entropyVkdFixed4*: string
    substantiveVkdFixed4*: string
    certificateAsiFixed4*: string
    engineAsiFixed4*: string
    weightedAsiFixed4*: string
    entropyAsiFixed4*: string
    substantiveAsiFixed4*: string

  AxProofReport* = object
    summary*: AxProofSummary
    entries*: seq[AxProofEntry]
    attemptedEntryIds*: seq[tuple[label: string, id: int]]
    reproofRequired*: seq[tuple[label: string, reason: string]]
# @axiom-hint: lean="statusStr.length ≥ 0" smt="(assert (and (>= (str.len statusStr) 0)))"
# @axiom-hint: lean="verifiedKey ∧ unattemptedKey" smt="(assert (and verifiedKey unattemptedKey))"

proc parseAxProofStatus*(statusStr: string): AxProofStatus =
  case statusStr
  of verifiedKey: axProofVerified
  of "counter_example_found": axProofCounterExampleFound
  of "blocked": axProofBlocked
  of "partially_verified", "bounded": axProofBlocked
  of "timed_out": axProofTimedOut
  of "vacuous_contradiction": axProofVacuousContradiction
  of unattemptedKey: axProofUnattempted
  else: axProofUnknown

## Ellipsize Path.
# @axiom-hint: lean="maxLen ≤ 3 ∧ path ∧ path.length ≤ maxLen → result = path" smt="(assert (and (<= maxLen 3) path (=> (<= (str.len path) maxLen) (= result path))))"
proc ellipsizePath*(path: string; maxLen: int): string =
  if path.len <= maxLen:
    return path
  if maxLen <= 3:
    return "..." & path[^maxLen..^1]
  let halfLen = (maxLen - 3) div 2
  return path[0..<halfLen] & "..." & path[^halfLen..^1]

# @axiom-hint: lean="sourceRoot.length ≥ 0 ∧ target.length ≥ 0" smt="(assert (and (>= (str.len sourceRoot) 0) (>= (str.len target) 0)))"
# @axiom-hint: lean="relative" smt="(assert (and relative))"
proc extractRelativeTarget*(sourceRoot: string; target: string): string =
  let normalizedRoot = normalizePathSeparators(sourceRoot)
  let normalizedTarget = normalizePathSeparators(target)
  if normalizedTarget.startsWith(normalizedRoot):
    let relative = normalizedTarget[normalizedRoot.len..^1]
    if relative.startsWith("/"):
      return relative[1..^1]
    return relative
  normalizedTarget

# @axiom-hint: lean="label.length ≥ 0 ∧ maxLabelWidth ≥ -9223372036854775808 ∧ maxLabelWidth ≤ 9223372036854775807" smt="(assert (and (>= (str.len label) 0) (and (>= maxLabelWidth -9223372036854775808) (<= maxLabelWidth 9223372036854775807))))"
# @axiom-hint: lean="label.length > maxLabelWidth" smt="(assert (and (> (str.len label) maxLabelWidth)))"
proc formatEntryLabelField*(label: string; maxLabelWidth: int): string =
  let displayLabel =
    if label.len > maxLabelWidth:
      ellipsizePath(label, maxLabelWidth)
    else:
      label
  unicode.alignLeft(displayLabel, maxLabelWidth)

## Entry Status Label.
# @axiom-hint: lean="axProofCounterExampleFound ∧ axProofVacuousContradiction ∧ axProofBlocked ∧ axProofTimedOut ∧ axProofVerified ∧ axProofUnattempted ∧ axProofUnverifiable ∧ axProofUnknown" smt="(assert (and axProofCounterExampleFound axProofVacuousContradiction axProofBlocked axProofTimedOut axProofVerified axProofUnattempted axProofUnverifiable axProofUnknown))"
proc entryStatusLabel*(status: AxProofStatus): string =
  case status
  of axProofCounterExampleFound: "counter_example"
  of axProofVacuousContradiction: "vacuous_contradiction"
  of axProofBlocked: "blocked_branch"
  of axProofTimedOut: "timeout"
  of axProofVerified: verifiedKey
  of axProofUnattempted: unattemptedKey
  of axProofUnverifiable: "unverifiable"
  of axProofUnknown: "unknown"

# @axiom-hint: lean="entries.size ≥ 0 ∧ maxAllowedWidth ≥ -9223372036854775808 ∧ maxAllowedWidth ≤ 9223372036854775807 ∧ maxEntries ≥ -9223372036854775808 ∧ maxEntries ≤ 9223372036854775807" smt="(assert (and (>= (seq.len entries) 0) (and (>= maxAllowedWidth -9223372036854775808) (<= maxAllowedWidth 9223372036854775807)) (and (>= maxEntries -9223372036854775808) (<= maxEntries 9223372036854775807))))"
## displayWidth shim — Nim 2.2.x std/unicode lacks displayWidth; len() suffices for ASCII labels.
func displayWidth*(s: string): int {.inline, raises: [].} = s.len

# @axiom-hint: lean="entries.size ≥ 0 ∧ maxAllowedWidth ≥ -9223372036854775808 ∧ maxAllowedWidth ≤ 9223372036854775807 ∧ maxEntries ≥ -9223372036854775808 ∧ maxEntries ≤ 9223372036854775807" smt="(assert (and (>= (seq.len entries) 0) (and (>= maxAllowedWidth -9223372036854775808) (<= maxAllowedWidth 9223372036854775807)) (and (>= maxEntries -9223372036854775808) (<= maxEntries 9223372036854775807))))"
# @axiom-hint: lean="maxEntries > 0 ∧ currentDisplayWidth > result ∧ result = 20 ∧ (result ≥ 0)" smt="(assert (and (> maxEntries 0) (> currentDisplayWidth result) (= result 20) (>= result 0)))"
proc computeDisplayLabelWidth*(entries: seq[AxProofEntry]; maxAllowedWidth: int; maxEntries: int = 0): int =
  result = 20
  let displayCount = if maxEntries > 0: min(entries.len, maxEntries) else: entries.len
  for i in 0..<displayCount:
    let currentDisplayWidth = displayWidth(entries[i].label)
    if currentDisplayWidth > result:
      result = min(currentDisplayWidth, maxAllowedWidth)
proc parseEntryDisplayId*(entry: JsonNode; attemptedOrdinal: int): int =
  for key in ["id", "proof_id", "proofId"]:
    if not entry.hasKey(key):
      continue
    let idNode = entry[key]
    case idNode.kind
    of JString:
      let raw = idNode.getStr().strip()
      if raw.len == 0:
        continue
      let digits =
        if raw.startsWith("#"):
          raw[1..^1].strip()
        else:
          raw
      if digits.len == 0 or not digits.allCharsInSet({'0'..'9'}):
        continue
      let parsedOpt = parseIntOpt(digits)
      if parsedOpt.isSome:
        return parsedOpt.get()
    of JInt, JFloat:
      return idNode.getInt()
    else:
      discard
  attemptedOrdinal
## Parse Ax Proof Report From Json.
# @axiom-hint: lean="attempted ∧ status = axProofUnattempted ∧ (verified ≥ 0) ∧ (entropyAsiFixed4 ≥ 0) ∧ (engine ≥ 0) ∧ (sourceRoot ≥ 0) ∧ (totalNodes ≥ 0) ∧ (timestamp ≥ 0) ∧ (totalWallTimeMs ≥ 0) ∧ (cpuEfficiency ≥ 0) ∧ (target ≥ 0) ∧ (vacuousContradictions ≥ 0) ∧ (substantiveAsiFixed4 ≥ 0) ∧ (counterExamples ≥ 0) ∧ (shortcutState ≥ 0) ∧ (engineAsiFixed4 ≥ 0) ∧ (weightedAsiFixed4 ≥ 0) ∧ (timedOut ≥ 0) ∧ (cacheHits ≥ 0) ∧ (attemptedNodes ≥ 0) ∧ (unattempted ≥ 0)" smt="(assert (and attempted (= status axProofUnattempted) (>= verified 0) (>= entropyAsiFixed4 0) (>= engine 0) (>= sourceRoot 0) (>= totalNodes 0) (>= timestamp 0) (>= totalWallTimeMs 0) (>= cpuEfficiency 0) (>= target 0) (>= vacuousContradictions 0) (>= substantiveAsiFixed4 0) (>= counterExamples 0) (>= shortcutState 0) (>= engineAsiFixed4 0) (>= weightedAsiFixed4 0) (>= timedOut 0) (>= cacheHits 0) (>= attemptedNodes 0) (>= unattempted 0)))"
# Wave Y: Extracted parse helpers (tkStructuralDecomp)
# ---------------------------------------------------------------------------

# @axiom-hint: lean="reportNode_object_or_empty" smt="(assert true)"
proc parseSummaryFields*(reportNode: JsonNode; summary: var AxProofSummary) =
  if reportNode.hasKey(targetKey) and reportNode[targetKey].kind == JString:
    summary.target = reportNode[targetKey].getStr()
  if reportNode.hasKey(sourceRootKey) and reportNode[sourceRootKey].kind == JString:
    summary.sourceRoot = reportNode[sourceRootKey].getStr()
  if reportNode.hasKey(timestampKey) and reportNode[timestampKey].kind == JString:
    summary.timestamp = reportNode[timestampKey].getStr()
  if reportNode.hasKey("summary"):
    let s = reportNode["summary"]
    if s.hasKey(totalNodesKey) and s[totalNodesKey].kind in {JInt, JFloat}:
      summary.totalNodes = s[totalNodesKey].getInt()
    if s.hasKey(attemptedNodesKey) and s[attemptedNodesKey].kind in {JInt, JFloat}:
      summary.attemptedNodes = s[attemptedNodesKey].getInt()
    if s.hasKey(verifiedKey) and s[verifiedKey].kind in {JInt, JFloat}:
      summary.verified = s[verifiedKey].getInt()
    if s.hasKey(counterExamplesKey) and s[counterExamplesKey].kind in {JInt, JFloat}:
      summary.counterExamples = s[counterExamplesKey].getInt()
    if s.hasKey(vacuousContradictionsKey) and s[vacuousContradictionsKey].kind in {JInt, JFloat}:
      summary.vacuousContradictions = s[vacuousContradictionsKey].getInt()
    if s.hasKey(timedOutKey) and s[timedOutKey].kind in {JInt, JFloat}:
      summary.timedOut = s[timedOutKey].getInt()
    if s.hasKey(unattemptedKey) and s[unattemptedKey].kind in {JInt, JFloat}:
      summary.unattempted = s[unattemptedKey].getInt()
    if s.hasKey(vkdFixed4Key) and s[vkdFixed4Key].kind == JString:
      summary.vkdFixed4 = s[vkdFixed4Key].getStr()
    if s.hasKey("engineAsiFixed4") and s["engineAsiFixed4"].kind == JString:
      summary.engineAsiFixed4 = s["engineAsiFixed4"].getStr()
    if s.hasKey("weightedAsiFixed4") and s["weightedAsiFixed4"].kind == JString:
      summary.weightedAsiFixed4 = s["weightedAsiFixed4"].getStr()
    if s.hasKey("entropyAsiFixed4") and s["entropyAsiFixed4"].kind == JString:
      summary.entropyAsiFixed4 = s["entropyAsiFixed4"].getStr()
    if s.hasKey("substantiveAsiFixed4") and s["substantiveAsiFixed4"].kind == JString:
      summary.substantiveAsiFixed4 = s["substantiveAsiFixed4"].getStr()

# @axiom-hint: lean="reportNode_object_or_empty" smt="(assert true)"
proc parseWorkflowFields*(reportNode: JsonNode; summary: var AxProofSummary) =
  if reportNode.hasKey("workflow") and reportNode["workflow"].kind == JObject:
    let workflow = reportNode["workflow"]
    if workflow.hasKey("performance") and workflow["performance"].kind == JObject:
      let perf = workflow["performance"]
      if perf.hasKey(totalWallTimeMsKey) and perf[totalWallTimeMsKey].kind in {JInt, JFloat}:
        summary.totalWallTimeMs = perf[totalWallTimeMsKey].getInt()
      if perf.hasKey(cpuEfficiencyKey) and perf[cpuEfficiencyKey].kind in {JInt, JFloat, JFloat}:
        summary.cpuEfficiency = perf[cpuEfficiencyKey].getFloat()
      if perf.hasKey(cacheHitCountKey) and perf[cacheHitCountKey].kind in {JInt, JFloat}:
        summary.cacheHits = perf[cacheHitCountKey].getInt()

# @axiom-hint: lean="reportNode_object_or_empty" smt="(assert true)"
proc parseReproofRequired*(reportNode: JsonNode; result: var AxProofReport) =
  if reportNode.hasKey("workflow") and reportNode["workflow"].kind == JObject:
    let workflow = reportNode["workflow"]
    if workflow.hasKey(reproofRequiredKey) and workflow[reproofRequiredKey].kind == JArray:
      for entry in workflow[reproofRequiredKey].elems:
        if entry.kind == JObject and entry.hasKey(labelKey) and entry[labelKey].kind == JString:
          let label = entry[labelKey].getStr()
          let reason =
            if entry.hasKey(reasonKey) and entry[reasonKey].kind == JString:
              entry[reasonKey].getStr()
            else: "unknown"
          result.reproofRequired.add((label, reason))
{.pop.}

