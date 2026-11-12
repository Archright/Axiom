## nimtry_snapshot.nim — Capture a nimtry violation snapshot (Nim port)
## Runs nimtry (or reuses cached output), parses violations by rule,
## and saves a structured JSON snapshot to logs/nimtry_history/.
##
## Usage: nimtry_snapshot [--use-cache]
## Exit code: 0 on success

import core/trusted/layer_declaration
axiomLayer "tools"
import std/[os, strutils, json, re, times, tables, osproc]

type
  ViolationCounts = object
    total: int
    errors: int
    warnings: int
    byRule: Table[string, int]

const isoFmt = initTimeFormat("yyyy'-'MM'-'dd'T'HH:mm:ss")
const fileFmt = initTimeFormat("yyyy'-'MM'-'dd'_'HHmmss")

proc findRepoRoot(): string =
  var dir = getAppDir()
  while dir.len > 0:
    if fileExists(dir / ".axiom_root"):
      return dir
    let parent = parentDir(dir)
    if parent == dir:
      break
    dir = parent
  result = getAppDir() / ".." / ".."
  normalizePath(result)

proc parseNimtryOutput(output: string): ViolationCounts =
  result = ViolationCounts(
    total: 0, errors: 0, warnings: 0,
    byRule: initTable[string, int]()
  )
  let rulePat = re"\[([a-z][a-z0-9_-]+)\]"
  for line in output.splitLines():
    let stripped = line.strip()
    if stripped.len == 0:
      continue
    let isError = stripped.contains(re"(?i)\berror\b")
    let isWarning = stripped.contains(re"(?i)\bwarning\b")
    if isError or isWarning:
      inc result.total
      if isError:
        inc result.errors
      if isWarning:
        inc result.warnings
      let m = stripped.findAll(rulePat)
      if m.len > 0:
        let ruleName = m[0].strip(chars = {'[', ']'})
        if ruleName.len > 0:
          result.byRule[ruleName] = result.byRule.getOrDefault(ruleName, 0) + 1

proc getShortSha(repoRoot: string): string =
  try:
    let (output, exitCode) = execCmdEx("git -C \"" & repoRoot & "\" rev-parse --short HEAD")
    if exitCode == 0:
      return output.strip()
  except OSError:
    discard
  result = "unknown"

proc main() =
  let repoRoot = findRepoRoot()
  let historyDir = repoRoot / "logs" / "nimtry_history"
  let args = commandLineParams()
  let useCache = args.len > 0 and args[0] == "--use-cache"

  try:
    createDir(historyDir)
  except OSError:
    discard

  let timestamp = now().format(isoFmt)
  let shortSha = getShortSha(repoRoot)
  let fileTimestamp = now().format(fileFmt)
  let outFile = historyDir / fileTimestamp & "_" & shortSha & ".json"

  let nimtryCache = getTempDir() / "nimtry_snapshot_cache.txt"
  var nimtryOutput: string

  if useCache and fileExists(nimtryCache):
    try:
      nimtryOutput = readFile(nimtryCache)
    except IOError:
      nimtryOutput = ""
  else:
    let nimtryBin = repoRoot / "bin" / "nimtry"
    if not fileExists(nimtryBin):
      echo "⚠️  bin/nimtry not found. Skipping snapshot."
      quit(0)
    try:
      let (output, exitCode) = execCmdEx(
        nimtryBin & " --full-tree --list",
        workingDir = repoRoot
      )
      nimtryOutput = output
      writeFile(nimtryCache, nimtryOutput)
    except OSError:
      nimtryOutput = ""

  let counts = parseNimtryOutput(nimtryOutput)

  var byRuleJson = newJObject()
  for rule, count in counts.byRule:
    byRuleJson[rule] = newJInt(count)

  let snapshot = %*{
    "timestamp": timestamp,
    "commit": shortSha,
    "total": counts.total,
    "errors": counts.errors,
    "warnings": counts.warnings,
    "by_rule": byRuleJson
  }

  try:
    writeFile(outFile, pretty(snapshot))
  except IOError as e:
    echo "❌ Failed to write snapshot: " & e.msg
    quit(1)

  echo "✅ nimtry snapshot saved: " & outFile
  echo "   Total: " & $counts.total & " | Errors: " & $counts.errors &
       " | Warnings: " & $counts.warnings

when isMainModule:
  main()
