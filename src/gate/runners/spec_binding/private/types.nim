## Feature-file scanning types and token collection.
##
## Moved from spec_binding_gate.nim as part of A1-A5 split.
## Uses parseCliTokensFromLine from utils to eliminate duplicated inline parsing.

import core/trusted/layer_declaration
axiomLayer "gate"
import std/tables
import std/strutils
import std/sets
import std/os
import core/utils/file_utils
import gate/runners/spec_binding/private/utils
import core/trusted/axiom_pragmas
# axiomIoBoundary

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const
  FeaturesDir* = "tests/features/"
  FeatureExt* = ".feature"
  CliSurfacePath* = "src/cli/cli_surface_generated.nim"
  ActionPlanPath* = "src/cli/action_plan_cli.nim"

# ---------------------------------------------------------------------------
# Types
# ---------------------------------------------------------------------------

type
  BindingViolation* = object
    message*: string
    severity*: string  # "error" or "warning"

  DeprecationRange* = tuple[startLine, endLine: int]

# ---------------------------------------------------------------------------
# Feature-file tagging
# ---------------------------------------------------------------------------

func isManualFeature*(content: string): bool =
  for line in content.splitLines():
    let trimmed = line.strip()
    if trimmed.startsWith("Feature:"):
      break
    if "@manual" in trimmed:
      return true
  false

func isLegacyFeature*(content: string): bool =
  for line in content.splitLines():
    let trimmed = line.strip()
    if trimmed.startsWith("Feature:"):
      break
    if "@legacy" in trimmed:
      return true
  false

# ---------------------------------------------------------------------------
# Deprecated-range helpers
# ---------------------------------------------------------------------------

proc computeDeprecatedRanges*(content: string): seq[DeprecationRange] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let lines = content.splitLines()
  var currentStart = -1
  for i in 0 ..< lines.len:
    let stripped = lines[i].strip()
    if stripped.startsWith("Scenario:") or stripped.startsWith("Scenario Outline:") or stripped.startsWith("Rule:"):
      if currentStart >= 0:
        result.add((startLine: currentStart, endLine: i - 1))
        currentStart = -1
      var isDeprecated = false
      for j in countdown(i - 1, 0):
        let prev = lines[j].strip()
        if prev.startsWith("@"):
          if "@deprecated" in prev or "@legacy" in prev:
            isDeprecated = true
        elif prev.len > 0 and not prev.startsWith("#"):
          break
      if isDeprecated:
        currentStart = i
  if currentStart >= 0:
    result.add((startLine: currentStart, endLine: lines.len - 1))

proc isInDeprecatedRange*(ranges: seq[DeprecationRange], lineIdx: int): bool {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  for r in ranges:
    if lineIdx >= r.startLine and lineIdx <= r.endLine:
      return true
  false

# ---------------------------------------------------------------------------
# Feature scanning — now uses parseCliTokensFromLine from utils
# ---------------------------------------------------------------------------

proc scanAllFeatureFiles*(files: seq[string] = @[]): Table[string, HashSet[string]] =
  result = initTable[string, HashSet[string]]()
  if not dirExists(FeaturesDir):
    return
  try:
    if files.len == 0:
      for kind, path in walkDir(FeaturesDir):
        if kind == pcFile and path.endsWith(FeatureExt):
          try:
            let content = readFileSafe(path)
            if isManualFeature(content):
              continue
            if isLegacyFeature(content):
              continue
            let deprecatedRanges = computeDeprecatedRanges(content)
            let lines = content.splitLines()
            var fileTokens = initHashSet[string]()
            for lineIdx, line in lines:
              if isInDeprecatedRange(deprecatedRanges, lineIdx):
                continue
              let scan = parseCliTokensFromLine(line)
              for f in scan.flags:
                fileTokens.incl(f)
              for c in scan.commands:
                fileTokens.incl(c)
            if fileTokens.len > 0:
              result[path] = fileTokens
          except CatchableError:
            discard  # axiom:best-effort(ioboundary catch)
    else:
      for f in files:
        if not f.endsWith(FeatureExt):
          continue
        try:
          if not fileExists(f):
            continue
          let content = readFileSafe(f)
          if isManualFeature(content):
            continue
          if isLegacyFeature(content):
            continue
          let deprecatedRanges = computeDeprecatedRanges(content)
          let lines = content.splitLines()
          var fileTokens = initHashSet[string]()
          for lineIdx, line in lines:
            if isInDeprecatedRange(deprecatedRanges, lineIdx):
              continue
            let scan = parseCliTokensFromLine(line)
            for fl in scan.flags:
              fileTokens.incl(fl)
            for c in scan.commands:
              fileTokens.incl(c)
          if fileTokens.len > 0:
            result[f] = fileTokens
        except CatchableError:
            discard  # axiom:best-effort(ioboundary catch)
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)

func collectAllFeatureTokens*(featureTokens: Table[string, HashSet[string]]): HashSet[string] =
  result = initHashSet[string]()
  for _, tokens in featureTokens:
    for token in tokens:
      result.incl(token)
