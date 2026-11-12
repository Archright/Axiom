import core/trusted/layer_declaration
axiomLayer "tools"
import api/tools_facade
import shared_types/shared_types
import std/[os, strutils, json, times, tables, algorithm, osproc]
const
  CachePath = "/tmp/nimtry_snapshot_cache.txt"
func extractRule(line: string): string =
  ## Extract rule name from brackets [rule-name] in a violation line.
  result = ""
  let start = line.find('[')
  if start < 0:
    return
  let endPos = line.find(']', start + 1)
  if endPos < 0:
    return
  let candidate = line[start + 1 .. endPos]
  # Rule names: lowercase alpha, digits, hyphens, underscores
  if candidate.len > 0 and candidate[0] in Letters:
    var valid = true
    for c in candidate:
      if c notin Letters and c notin Digits and c != '-' and c != '_':
        valid = false
        break
    if valid:
      result = candidate
proc findRepoRoot(): string {.axiomEffect: IoEffect.} =
  ## Walk up from tools/ to find the repo root (.axiom_root anchor).
  result = getCurrentDir()
  var d = result
  while d != "/":
    if fileExists(d / ".axiom_root"):
      return d
    d = parentDir(d)
  # Fallback: assume two levels up from tools/
  result = getCurrentDir().parentDir().parentDir()
proc main() {.axiomEffect: IoEffect.} =
  let params = commandLineParams()
  var useCache = false

  for p in params:
    if p == "--use-cache":
      useCache = true

  let repoRoot = findRepoRoot()
  let historyDir = repoRoot / "logs" / "nimtry_history"

  if not dirExists(historyDir):
    createDir(historyDir)

  # Get timestamp and commit SHA
  let timestamp = now().format("yyyy-MM-dd'T'HH:mm:sszz")
  var shortSha = "unknown"
  let (shaOutput, shaExit) = execCmdEx(
    "git -C " & quoteShell(repoRoot) & " rev-parse --short HEAD",
    options = {poUsePath}
  )
  if shaExit == 0:
    shortSha = shaOutput.strip()

  let outFileName = now().format("yyyy-MM-dd'_'HHmmss") & "_" & shortSha & ".json"
  let outFile = historyDir / outFileName

  # Run nimtry or use cache
  var nimtryOutput = ""

  if useCache and fileExists(CachePath):
    nimtryOutput = readFile(CachePath)
  else:
    let nimtryBin = repoRoot / "bin" / "nimtry"
    if not fileExists(nimtryBin):
      echo "⚠️  bin/nimtry not found or not executable. Skipping snapshot."
      quit(0)
    # Run nimtry
    let (output, _) = execCmdEx(
      nimtryBin & " --full-tree --list",
      options = {poUsePath, poStdErrToStdOut},
      workingDir = repoRoot
    )
    nimtryOutput = output
    writeFile(CachePath, nimtryOutput)

  # Parse output
  var total = 0
  var errors = 0
  var warnings = 0
  var byRule = initTable[string, int]()

  for line in nimtryOutput.splitLines():
    let lower = line.toLowerAscii()
    if "error" in lower:
      inc errors
      inc total
      let rule = extractRule(line)
      if rule.len > 0:
        byRule.mgetOrPut(rule, 0) += 1
    elif "warning" in lower:
      inc warnings
      inc total
      let rule = extractRule(line)
      if rule.len > 0:
        byRule.mgetOrPut(rule, 0) += 1

  # Build by_rule JSON object (sorted keys for determinism)
  var byRuleJson = newJObject()
  var ruleKeys: seq[string] = @[]
  for k in byRule.keys:
    ruleKeys.add(k)
  ruleKeys.sort()
  for k in ruleKeys:
    byRuleJson[k] = %byRule[k]

  # Build full snapshot JSON
  let snapshot = %*{
    "timestamp": timestamp,
    "commit": shortSha,
    "total": total,
    "errors": errors,
    "warnings": warnings,
    "by_rule": byRuleJson,
  }

  writeFile(outFile, pretty(snapshot) & "\n")

  echo "✅ nimtry snapshot saved: ", outFile
  echo "   Total: ", total, " | Errors: ", errors, " | Warnings: ", warnings

when isMainModule:
  main()
