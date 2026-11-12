## CLI spec auto-alignment tool.
## Finds .feature references that are not present in the generated CLI surface SSOT.

import std/[algorithm, os, sets, strutils, tables]

const
  CliSurfacePath = "src/cli/cli_surface_generated.nim"
  CliTypesPath = "src/cli/cli_types.nim"
  ActionPlanPath = "src/cli/action_plan_cli.nim"
  FeaturesDir = "tests/features"
  FeatureExt = ".feature"
  DebtTag = "@wip(DEBT#NEW)"
  MinFlagLen = 3

type
  ValidSet = object
    flags: HashSet[string]
    commands: HashSet[string]

  ScenarioRange = object
    path: string
    startLine: int
    hasWip: bool

  FeatureViolation = object
    kind: string
    name: string
    path: string
    line: int

  RunOptions = object
    dryRun: bool
    apply: bool

func isExcludedToken(token: string): bool {.raises: [].} =
  case token
  of "assert", "assert-not", "and", "not", "true", "false",
     "given", "when", "then", "but", "scenario", "feature",
     "rule", "background", "examples", "examples:", "example", "example:":
    result = true
  else:
    result = false

func isKnownAxSubcommand(subcommand: string): bool {.raises: [].} =
  case subcommand
  of "prove", "report", "verify", "gate", "mcp", "submit",
     "init", "dashboard", "uap", "integrity-loop", "help",
     "heal", "scan", "view", "trace", "diff", "check",
     "monitor", "status", "inspect", "submit-proof",
     "vault-sync", "cert", "procedure", "run",
     "induction", "workflow", "topology":
    result = true
  else:
    result = false

func cleanFlag(rawFlag: string): string {.raises: [].} =
  let withoutValue = rawFlag.split("=")[0]
  result = withoutValue.strip(chars = {' ', '\t', '\n', '\r', ':', ',', ';', '\'', '"'})
  var valid = true
  for ch in result:
    if ch notin {'a'..'z', 'A'..'Z', '0'..'9', '-'}:
      valid = false
      break
  if not valid or result.len < MinFlagLen:
    result = ""

func extractFlagsFromSource(content: string): HashSet[string] {.raises: [].} =
  result = initHashSet[string]()
  for rawLine in content.splitLines():
    var i = 0
    while i < rawLine.len - 1:
      if rawLine[i] == '-' and rawLine[i + 1] == '-':
        var j = i + 2
        while j < rawLine.len and rawLine[j] notin {' ', '"', '\'', ',', ')', ']', '}', '?', '.', ':', '|'}:
          j.inc
        if j > i + MinFlagLen:
          let flag = cleanFlag(rawLine[i ..< j])
          if flag.len >= MinFlagLen:
            result.incl(flag)
        i = j
      else:
        i.inc

func extractCommandsFromSource(content: string): HashSet[string] {.raises: [].} =
  result = initHashSet[string]()
  const marker = "name: \""
  for line in content.splitLines():
    let trimmed = line.strip()
    if not trimmed.contains(marker):
      continue
    let start = trimmed.find(marker) + marker.len
    let stop = trimmed.find('"', start)
    if start >= 0 and stop > start:
      let command = trimmed[start ..< stop].strip()
      if command.len >= 3 and command.startsWith("ax "):
        result.incl(command)

func parseCliTokensFromLine(line: string): (HashSet[string], HashSet[string]) {.raises: [].} =
  result = (initHashSet[string](), initHashSet[string]())
  let stripped = line.strip()
  if stripped.len == 0 or stripped.startsWith("#") or stripped.startsWith("@"):
    return

  var i = 0
  while i < stripped.len - 1:
    if stripped[i] == '-' and stripped[i + 1] == '-':
      var j = i + 2
      while j < stripped.len and stripped[j] notin {' ', '"', '\'', ',', ')', ']', '}', '?', '.', ':', '|'}:
        j.inc
      if j > i + MinFlagLen:
        let flag = cleanFlag(stripped[i ..< j])
        if flag.len >= MinFlagLen and not isExcludedToken(flag):
          result[0].incl(flag)
      i = j
    elif i + 2 < stripped.len and stripped[i] == 'a' and stripped[i + 1] == 'x' and stripped[i + 2] == ' ':
      var j = i + 3
      while j < stripped.len and stripped[j] notin {' ', '"', '\'', ')'}:
        j.inc
      let subcommand = stripped[i + 3 ..< j]
      if subcommand.len >= 3 and isKnownAxSubcommand(subcommand) and not isExcludedToken(subcommand):
        result[1].incl("ax " & subcommand)
      i = j
    else:
      i.inc

func isManualFeature(content: string): bool {.raises: [].} =
  for line in content.splitLines():
    let trimmed = line.strip()
    if trimmed.startsWith("Feature:"):
      break
    if "@manual" in trimmed:
      return true
  false

func isLegacyFeature(content: string): bool {.raises: [].} =
  for line in content.splitLines():
    let trimmed = line.strip()
    if trimmed.startsWith("Feature:"):
      break
    if "@legacy" in trimmed:
      return true
  false

type DeprecationRange = tuple[startLine, endLine: int]

func computeDeprecatedRanges(content: string): seq[DeprecationRange] {.raises: [].} =
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

func isInDeprecatedRange(ranges: seq[DeprecationRange], lineIdx: int): bool {.raises: [].} =
  for range in ranges:
    if lineIdx >= range.startLine and lineIdx <= range.endLine:
      return true
  false

func collectScenarioRanges(path: string; content: string): seq[ScenarioRange] {.raises: [].} =
  let lines = content.splitLines()
  var ranges: seq[ScenarioRange] = @[]
  var startLine = -1
  var pendingTags: seq[string] = @[]
  var pendingHasWip = false

  for i, rawLine in lines:
    let line = rawLine.strip()
    if line.len == 0:
      continue
    if line.startsWith("@"):
      pendingTags.add(line)
      if line.startsWith("@wip"):
        pendingHasWip = true
      continue
    if line.startsWith("Scenario:") or line.startsWith("Scenario Outline:"):
      if startLine >= 0:
        ranges.add(ScenarioRange(path: path, startLine: startLine, hasWip: pendingHasWip))
      startLine = i
      pendingTags = @[]
      pendingHasWip = line.contains("@wip")
      continue
    if line.startsWith("Feature:") or line.startsWith("Background:") or line.startsWith("Examples:") or line.startsWith("Example:"):
      if startLine >= 0:
        ranges.add(ScenarioRange(path: path, startLine: startLine, hasWip: pendingHasWip))
      startLine = -1
      pendingTags = @[]
      pendingHasWip = false
      continue

  if startLine >= 0:
    ranges.add(ScenarioRange(path: path, startLine: startLine, hasWip: pendingHasWip))
  result = ranges

proc scanFeatureFile(path: string; valid: ValidSet): seq[FeatureViolation] {.raises: [IOError, OSError].} =
  let content = readFile(path)
  if isManualFeature(content) or isLegacyFeature(content):
    return

  let ranges = computeDeprecatedRanges(content)
  let lines = content.splitLines()
  var fileFlags = initHashSet[string]()
  var fileCommands = initHashSet[string]()
  for lineIdx in 0 ..< lines.len:
    let line = lines[lineIdx]
    if isInDeprecatedRange(ranges, lineIdx):
      continue
    let (flags, commands) = parseCliTokensFromLine(line)
    for flag in flags:
      if flag notin valid.flags and flag notin fileFlags:
        fileFlags.incl(flag)
        result.add(FeatureViolation(kind: "flag", name: flag, path: path, line: lineIdx + 1))
    for command in commands:
      if command notin valid.commands and command notin fileCommands:
        fileCommands.incl(command)
        result.add(FeatureViolation(kind: "command", name: command, path: path, line: lineIdx + 1))

proc buildValidSet(): ValidSet {.raises: [IOError, OSError].} =
  result.flags = initHashSet[string]()
  result.commands = initHashSet[string]()

  for path in [CliSurfacePath, CliTypesPath]:
    if fileExists(path):
      for flag in extractFlagsFromSource(readFile(path)):
        result.flags.incl(flag)

  if fileExists(ActionPlanPath):
    let content = readFile(ActionPlanPath)
    for flag in extractFlagsFromSource(content):
      result.flags.incl(flag)
    for command in extractCommandsFromSource(content):
      result.commands.incl(command)

proc parseArgs(): RunOptions {.raises: [OSError].} =
  result.dryRun = true
  for arg in commandLineParams():
    case arg
    of "--dry-run":
      result.dryRun = true
    of "--apply":
      result.apply = true
      result.dryRun = false
    else:
      discard

proc collectFeatureFiles(): seq[string] {.raises: [OSError, IOError].} =
  if not dirExists(FeaturesDir):
    return @[]
  for path in walkDirRec(FeaturesDir):
    if path.endsWith(FeatureExt):
      result.add(path)
  result.sort(proc(a, b: string): int {.raises: [].} = cmp(a, b))

proc countWipScenarios(files: seq[string]): int {.raises: [IOError].} =
  for path in files:
    let content = readFile(path)
    let ranges = collectScenarioRanges(path, content)
    for range in ranges:
      if range.hasWip:
        inc result

func findScenario(ranges: seq[ScenarioRange]; line: int): ScenarioRange {.raises: [].} =
  for range in ranges:
    if line >= range.startLine:
      return range
  result = ScenarioRange(path: "", startLine: -1, hasWip: false)

proc applyTagsToScenarios(violations: seq[FeatureViolation]; rangesByPath: Table[string, seq[ScenarioRange]]; options: RunOptions) {.raises: [IOError, OSError].} =
  if options.dryRun or violations.len == 0:
    return

  var rangesToTag: seq[ScenarioRange] = @[]
  for violation in violations:
    let ranges = rangesByPath.getOrDefault(violation.path, @[])
    let range = findScenario(ranges, violation.line)
    if range.startLine < 0 or range.hasWip:
      continue
    var alreadyTagged = false
    for existing in rangesToTag:
      if existing.path == range.path and existing.startLine == range.startLine:
        alreadyTagged = true
        break
    if not alreadyTagged:
      rangesToTag.add(range)

  rangesToTag.sort(proc(a, b: ScenarioRange): int {.raises: [].} =
    if a.startLine > b.startLine:
      -1
    elif a.startLine < b.startLine:
      1
    else:
      0
  )

  for range in rangesToTag:
    let content = readFile(range.path)
    var lines = content.splitLines()
    let insertAt = Natural(range.startLine)
    let tagLine = "  " & DebtTag
    lines.insert(tagLine, insertAt)
    writeFile(range.path, lines.join("\n") & "\n")

proc main() {.raises: [IOError, OSError].} =
  let options = parseArgs()
  let valid = buildValidSet()
  let featureFiles = collectFeatureFiles()

  var violations: seq[FeatureViolation] = @[]
  var rangesByPath: Table[string, seq[ScenarioRange]] = initTable[string, seq[ScenarioRange]]()
  for path in featureFiles:
    let content = readFile(path)
    let ranges = collectScenarioRanges(path, content)
    rangesByPath[path] = ranges
    for violation in scanFeatureFile(path, valid):
      violations.add(violation)

  for violation in violations:
    if violation.kind == "flag":
      echo "[DEBT#NEW] @wip(DEBT#NEW) flag '" & violation.name & "' not found in SSOT"
    else:
      echo "[DEBT#NEW] @wip(DEBT#NEW) command '" & violation.name & "' not found in SSOT"

  applyTagsToScenarios(violations, rangesByPath, options)

  let wipAfter = countWipScenarios(featureFiles)
  echo "Total @wip scenarios: " & $wipAfter

when isMainModule:
  main()
