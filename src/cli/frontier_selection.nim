## Frontier selection helper: applies --target filter, eligibility gate,
## and limit in the correct order.
##
## Ordering: --target applies BEFORE automatic frontier filtering
## (eligibility gate + limit). Eligibility is still enforced as a
## final guard — an explicitly targeted non-eligible symbol is excluded.
##
## This helper exists to make the selection ordering testable in
## isolation without requiring a full topology analysis or E2E run.

import core/sorter/sorter_core
import std/[tables, strutils]
import infrastructure/logging_facade

type
  FrontierEligibilityCheck* = proc(fnName, modulePath: string): bool {.raises: [].}

proc stripPostfixExportMarker*(fnName: string): string {.raises: [], inline.} =
  ## Strip a single trailing `*` export marker from a function name.
  ## A lone `*` (a real operator symbol name, not an export marker) and
  ## an empty name are returned unchanged, so this never raises a range
  ## defect. Mirrors the guarded canonical `[0..^2]` rule used by
  ## ir_pipeline_runner.nim:1122: strip exactly one trailing `*` (not two).
  if fnName.endsWith("*") and fnName.len > 1:
    fnName[0..^2]
  else:
    fnName

proc selectFrontierNodes*(
  frontier: seq[SorterNodeId];
  target: string;
  nodeFnIdx: Table[string, string];
  nodeModuleIdx: Table[string, string];
  frontierLimit: int;
  isEligible: FrontierEligibilityCheck
): seq[SorterNodeId] =
  ## Apply --target filter, eligibility gate, and limit in the correct order.
  ##
  ## 1. If --target is specified, find matching nodes in the full
  ##    (pre-eligibility, pre-limit) frontier. This ensures a targeted
  ##    symbol is found even when --limit would have selected a
  ##    different node first and the eligibility gate then removed
  ##    that node.
  ##
  ##    When the target contains ``::``, it is parsed as
  ##    ``modulePath::functionName`` and exact matching is performed
  ##    against both ``nodeModuleIdx`` and ``nodeFnIdx``.
  ##    0 matches → NotFound (empty selection + explicit log).
  ##    >1 matches → Ambiguous (fail-closed).
  ##    Legacy bare-name substring matching (no ``::``) is preserved
  ##    but documented as non-canonical.
  ##
  ## 2. Apply the eligibility gate to the target-selected (or full)
  ##    frontier. Non-eligible nodes are excluded.
  ## 3. Re-apply the frontier limit in terms of eligible candidates.
  ##
  ## The eligibility gate is NEVER bypassed: explicitly targeted
  ## non-eligible symbols are still excluded.

  # Step 1: --target filter on the pre-eligibility frontier
  if target.len > 0:
    var filtered: seq[SorterNodeId] = @[]
    if target.contains("::"):
      # Exact matching against both module path and function name.
      let colonPos = target.find("::")
      let targetModule = target[0 ..< colonPos]
      let targetFn = target[colonPos + 2 .. ^1]
      for nodeId in frontier:
        let nid = sorterNodeIdString(nodeId)
        let fnName = nodeFnIdx.getOrDefault(nid, "")
        let modPath = nodeModuleIdx.getOrDefault(nid, "")
        if fnName == targetFn and modPath == targetModule:
          filtered.add(nodeId)
      if filtered.len == 0:
        logInfo("frontier_selection", "--target=" & target & " not found in frontier — canonical target: NotFound (fail-closed, empty selection)")
        result = @[]
      elif filtered.len > 1:
        logInfo("frontier_selection", "--target=" & target & " is ambiguous (" & $filtered.len & " matches) — canonical target: Ambiguous (fail-closed, empty selection)")
        result = @[]
      else:
        result = filtered
    else:
      # Legacy bare-name substring matching (non-canonical; kept for
      # backward compatibility with existing --target behavior).
      for nodeId in frontier:
        let nid = sorterNodeIdString(nodeId)
        if nid.contains(target):
          filtered.add(nodeId)
      if filtered.len > 0:
        result = filtered
      else:
        # Target not found — fall back to full frontier (same as before)
        result = frontier
  else:
    result = frontier

  # Step 2: eligibility gate
  if result.len > 0:
    var eligible: seq[SorterNodeId] = @[]
    for f in result:
      let fnId = sorterNodeIdString(f)
      let fnName = nodeFnIdx.getOrDefault(fnId, "")
      let modPath = nodeModuleIdx.getOrDefault(fnId, "")
      if isEligible(fnName, modPath):
        eligible.add(f)
    result = eligible

  # Step 3: re-apply limit
  if frontierLimit > 0 and result.len > frontierLimit:
    result.setLen(frontierLimit)
