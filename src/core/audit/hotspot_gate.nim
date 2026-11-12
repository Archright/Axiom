{.push raises: [].}
import core/trusted/layer_declaration
axiomLayer "domain"
import burn_down_queue
import hotspot_analyzer
import std/[os, strutils]
# axiomIoBoundary


type
  HotspotGateResult* = enum
    hgrPass    ## File is not a hotspot or has adequate coverage
    hgrWarn    ## File is a hotspot, needs attention (warn mode)
    hgrFail    ## File is a hotspot, missing test or SAD too low
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc tierLabel(tier: HotspotTier): string {.raises: [].} =
  case tier
  of htCritical, htHigh: "Tier 1 Hotspot"
  of htMedium, htLow: "Tier 2 Hotspot"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc formatHotspotContext*(entry: HotspotEntry; sinceDays: int): string {.raises: [].} =
  ## Produce a context-rich human-readable message for a hotspot entry.
  let label = tierLabel(entry.tier)
  if not entry.hasTest:
    result = "[" & label & "] " & entry.filePath & " — modified " & $entry.editCount & " times in " & $sinceDays & " days.\n" &
             "High stability required. Please add 1+ semantic assertion.\n" &
             "Priority score: " & $entry.priorityScore & ". No test found."
  elif entry.sadScore < 0.05:
    result = "[" & label & "] " & entry.filePath & " — modified " & $entry.editCount & " times in " & $sinceDays & " days.\n" &
             "SAD = " & $(entry.sadScore * 100) & "% (threshold: 5%). Please add meaningful assertions.\n" &
             "Priority score: " & $entry.priorityScore & ". Test exists but is nearly a stub."
  else:
    result = ""
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc runHotspotCheck*(
  changedFiles: seq[string];
  sinceDays: int = 30;
  topN: int = 20;
  strictMode: bool = false
): tuple[passed: bool; warnings: seq[string]; failures: seq[string]; entries: seq[HotspotEntry]] {.raises: [].} =
  ## Check changed files against hotspot priority queue.
  ## Returns (overall_passed, warning_messages, failure_messages, matched_entries)
  result.passed = true
  result.warnings = @[]
  result.failures = @[]
  result.entries = @[]

  if changedFiles.len == 0:
    return

  # Build hotspot queue from git history
  let churn = computeChurnScoresCached(sinceDays)
  let queue = buildPriorityQueue(churn, topN)

  if queue.len == 0:
    return

  for f in changedFiles:
    # Normalize path
    var normalized = f
    if normalized.startsWith("src/"):
      normalized = normalized[4 .. ^1]
    if not normalized.endsWith(".nim"):
      continue
    if normalized.startsWith("tests/") or normalized.startsWith("vendor/"):
      continue

    # Check if this file is in the top-N hotspots
    var isHot = false
    var entry: HotspotEntry
    for i in 0 ..< min(topN, queue.len):
      if queue[i].filePath == f or queue[i].filePath.endsWith("/" & normalized) or queue[i].moduleName == extractFilename(f).replace(".nim", ""):
        isHot = true
        entry = queue[i]
        break

    if not isHot:
      continue

    result.entries.add(entry)

    # Escalation rules
    let msg = formatHotspotContext(entry, sinceDays)
    if msg.len == 0:
      continue

    if strictMode:
      result.failures.add(msg)
      result.passed = false
    else:
      result.warnings.add(msg)
