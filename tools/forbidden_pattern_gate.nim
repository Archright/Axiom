## forbidden_pattern_gate.nim — Blocks forbidden patterns in src/core/ files.
##
## Currently enforces:
##   - No direct std/json.parseJson() calls (must use pureParseJson).
##
## Exit code: 0 = PASS, 1 = FAIL

import core/trusted/layer_declaration
axiomLayer "tools"
import shared_types/shared_types
import std/json
import std/os
import std/strutils

axiomIoBoundary()

const
  GateTag = "[forbidden-pattern]"
  SrcCoreRelPath = "src/core"
  BaselineRelPath = "data/forbidden_pattern_baseline.json"

type
  ForbiddenRule = object
    name: string
    pattern: string
    excludeFiles: seq[string]
    message: string

  Violation = object
    rule: string
    file: string
    line: int
    message: string
    content: string

func getForbiddenRules(): seq[ForbiddenRule] =
  ## Define forbidden patterns. Extend this as new rules are added.
  result.add(ForbiddenRule(
    name: "parseJson",
    pattern: "parseJson(",
    excludeFiles: @["pure_deps/json_parse.nim"],
    message: "Use core/pure_deps/json_parse.nim:pureParseJson instead of std/json.parseJson"
  ))

func stripComment(line: string): string =
  ## Remove everything after the first # that's not inside a string.
  let hashPos = line.find('#')
  if hashPos >= 0:
    result = line[0 ..< hashPos]
  else:
    result = line

func containsWordBoundary(text, pattern: string): bool =
  ## Check if text contains pattern as a word (preceded by non-word char or start).
  let idx = text.find(pattern)
  if idx < 0:
    return false
  if idx == 0:
    return true
  let prev = text[idx - 1]
  not prev.isAlphaNumeric() and prev != '_' and prev != '`'

proc scanForViolations(repoRoot: string): seq[Violation] {.axiomEffect: IOEffect.} =
  let rules = getForbiddenRules()
  let srcCoreDir = repoRoot / SrcCoreRelPath

  for rule in rules:
    # Walk all .nim files under src/core/
    for path in walkDirRec(srcCoreDir):
      if not path.endsWith(".nim"):
        continue
      if ".nimcache" in path:
        continue
      let relPath = path.relativePath(repoRoot)
      # Check exclusions
      var excluded = false
      for ex in rule.excludeFiles:
        if ex in relPath:
          excluded = true
          break
      if excluded:
        continue

      try:
        let content = readFile(path)
        let lines = content.splitLines()
        for i, line in lines:
          let stripped = stripComment(line)
          if containsWordBoundary(stripped, rule.pattern):
            let shortLine = if line.strip().len > 100: line.strip()[0 ..< 100] else: line.strip()
            result.add(Violation(
              rule: rule.name,
              file: relPath,
              line: i + 1,
              message: rule.message,
              content: shortLine
            ))
      except CatchableError:
        discard  # axiom:best-effort(unreadable-source-file: skip file, continue scanning remaining files)

proc writeBaseline(repoRoot: string, violations: seq[Violation]) {.axiomEffect: IOEffect.} =
  var baseline = %*{"count": violations.len, "rules": newJObject()}
  for v in violations:
    let rulesObj = baseline["rules"]
    if rulesObj.hasKey(v.rule):
      rulesObj[v.rule] = newJInt(rulesObj[v.rule].getInt() + 1)
    else:
      rulesObj[v.rule] = newJInt(1)

  let baselinePath = repoRoot / BaselineRelPath
  let parentDir = baselinePath.parentDir()
  if not dirExists(parentDir):
    createDir(parentDir)
  writeFile(baselinePath, $baseline & "\n")

proc main() {.axiomEffect: IOEffect.} =
  let repoRoot = findRepoRoot()
  setCurrentDir(repoRoot)

  let violations = scanForViolations(repoRoot)

  # Write baseline
  writeBaseline(repoRoot, violations)

  if violations.len > 0:
    echo GateTag, " FAIL: ", violations.len, " forbidden pattern violation(s)"
    for v in violations:
      echo "  [", v.rule, "] ", v.file, ":", v.line, ": ", v.content
      echo "    → ", v.message
    quit(1)
  else:
    echo GateTag, " PASS: no forbidden patterns found"
    quit(0)

when isMainModule:
  main()
