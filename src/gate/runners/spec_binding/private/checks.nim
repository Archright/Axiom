## Binding and coherence checks, plus main entry point.
##
## Moved from spec_binding_gate.nim as part of A1-A5 split.
## Coherence check now uses parseCliTokensFromLine from utils to eliminate
## duplicated inline flag-parsing that was previously copy-pasted between
## extractCliTokensFromFeature and runCoherenceCheck.

import core/trusted/layer_declaration
axiomLayer "gate"
import std/strutils
import std/sets
import std/tables
import std/os
import core/utils/file_utils
import cli/cli_types
import gate/runners/spec_binding/private/types
import gate/runners/spec_binding/private/utils
import gate/runners/spec_binding/private/source_extract
import core/axiom_pragmas
import infrastructure/logging_facade
# axiomIoBoundary

# ---------------------------------------------------------------------------
# Binding check
# ---------------------------------------------------------------------------

proc runBindingCheck*(files: seq[string]  = @[]): seq[BindingViolation] =
  result = @[]

  let sourceIds = extractAllSourceIdentifiers()
  let featureTokens = scanAllFeatureFiles(files)
  let allFeatureTokens = collectAllFeatureTokens(featureTokens)

  for id in sourceIds:
    if id.startsWith("--") or id.startsWith("ax "):
      if id notin allFeatureTokens:
        if id.startsWith("--"):
          result.add(BindingViolation(
            message: "CLI flag '" & id & "' defined in source but not found in any .feature file",
            severity: "warning"
          ))

  for path, tokens in featureTokens:
    for token in tokens:
      if token.startsWith("--") and token notin sourceIds:
        result.add(BindingViolation(
          message: "Feature '" & path & "' references '" & token & "' which no longer exists in source (SSOT: " & CliSurfacePath & ")",
          severity: "error"
        ))
      elif token.startsWith("ax ") and token.len > 3:
        let cmdParts = token.split(" ")
        if cmdParts.len >= 2 and isKnownAxSubcommand(cmdParts[1]):
          var found = false
          let prefix = "ax " & cmdParts[1]
          for srcId in sourceIds:
            if srcId.startsWith(prefix):
              found = true
              break
          if not found:
            result.add(BindingViolation(
              message: "Feature '" & path & "' references command '" & token & "' which is not defined in source",
              severity: "error"
            ))

# ---------------------------------------------------------------------------
# Coherence Validation (enum-based, command-scoped)
# ---------------------------------------------------------------------------

proc enumFlagsForCommand*(cmd: string): HashSet[string] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  result = initHashSet[string]()
  if cmd == "prove":
    for flag in AxProveFlag:
      result.incl($flag)
  elif cmd == "report":
    for flag in AxReportFlag:
      result.incl($flag)

proc detectCommandInLine*(line: string): string {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let stripped = line.strip()
  if "ax prove" in stripped:
    result = "prove"
  elif "ax report" in stripped:
    result = "report"
  else:
    result = ""

proc runCoherenceCheck*(files: seq[string] = @[]): seq[BindingViolation] {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  result = @[]
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
            for lineIdx, rawLine in lines:
              if isInDeprecatedRange(deprecatedRanges, lineIdx):
                continue
              let cmd = detectCommandInLine(rawLine)
              if cmd.len == 0:
                continue
              let validFlags = enumFlagsForCommand(cmd)
              if validFlags.len == 0:
                continue
              let scan = parseCliTokensFromLine(rawLine)
              for cleanFlag in scan.flags:
                if cleanFlag notin validFlags:
                  result.add(BindingViolation(
                    message: "Feature '" & path & "' line " & $(lineIdx + 1) & ": flag '" & cleanFlag & "' is not valid for 'ax " & cmd & "' (not in enum)",
                    severity: "error"
                  ))
          except CatchableError:
            discard  # axiom:best-effort(ioboundary catch)
    else:
      for f in files:
        if not f.endsWith(FeatureExt):
          continue
        if not fileExists(f):
          continue
        try:
          let content = readFileSafe(f)
          if isManualFeature(content):
            continue
          if isLegacyFeature(content):
            continue
          let deprecatedRanges = computeDeprecatedRanges(content)
          let lines = content.splitLines()
          for lineIdx, rawLine in lines:
            if isInDeprecatedRange(deprecatedRanges, lineIdx):
              continue
            let cmd = detectCommandInLine(rawLine)
            if cmd.len == 0:
              continue
            let validFlags = enumFlagsForCommand(cmd)
            if validFlags.len == 0:
              continue
            let scan = parseCliTokensFromLine(rawLine)
            for cleanFlag in scan.flags:
              if cleanFlag notin validFlags:
                result.add(BindingViolation(
                  message: "Feature '" & f & "' line " & $(lineIdx + 1) & ": flag '" & cleanFlag & "' is not valid for 'ax " & cmd & "' (not in enum)",
                  severity: "error"
                ))
        except CatchableError:
          discard  # axiom:best-effort(ioboundary catch)
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

proc main*()  =
  let args = commandLineParams()
  var files: seq[string] = @[]
  for arg in args:
    if not arg.startsWith("--"):
      files.add(arg)

  let bindingViolations = runBindingCheck(files)
  let coherenceViolations = runCoherenceCheck(files)
  let allViolations = bindingViolations & coherenceViolations

  if allViolations.len == 0:
    quit(0)

  var errorCount = 0
  var warningCount = 0

  for v in allViolations:
    if v.severity == "error":
      errorCount.inc
      logError("checks", "[spec-binding-gate] ERROR: " & v.message)
    else:
      warningCount.inc
      logWarn("checks", "[spec-binding-gate] WARN: " & v.message)

  logInfo("checks", "")
  logError("checks", "[spec-binding-gate] Summary: " & $errorCount & " error(s), " & $warningCount & " warning(s)")
  logInfo("checks", "[spec-binding-gate] SSOT: " & CliSurfacePath & ", " & ActionPlanPath)
  logInfo("checks", "[spec-binding-gate] Fix: Update .feature files to match source identifiers, or update source to match features.")

  if errorCount > 0:
    quit(1)

when isMainModule:
  main()
