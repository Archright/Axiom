## Orphaned Step Checker — Cross-validates step registry vs YAML scenarios
## Scans source files for {.testStep: "name".} annotations and verifies
## every registered step appears in at least one scenario file.
## Exit 1 if orphaned steps found (CI Fail-Fast).

import core/trusted/layer_declaration
axiomLayer "tools"
import std/[os, strutils, sequtils, tables, algorithm]

const
  scenarioDir = "data/scenarios"
  srcDirs = ["src", "tests"]
  stepPattern = "testStep"
  yamlExt = ".yaml"

type
  StepEntry = object
    name: string
    file: string
    line: int

proc scanSourceFiles(): seq[StepEntry] =
  ## Scan all .nim files for {.testStep: "name".} annotations.
  result = @[]
  for srcDir in srcDirs:
    if not dirExists(srcDir):
      continue
    for path in walkDirRec(srcDir, yieldFilter = {pcFile}):
      if not path.endsWith(".nim"):
        continue
      let content = readFile(path)
      let lines = content.splitLines()
      for i, line in lines:
        let stripped = line.strip()
        # Skip comments and docstrings
        if stripped.startsWith("##") or stripped.startsWith("#"):
          continue
        let idx = line.find(stepPattern)
        if idx < 0:
          continue
        # Extract step name from {.testStep: "name".}
        let colonPos = line.find(':', idx + stepPattern.len)
        if colonPos < 0:
          continue
        let afterColon = line[colonPos + 1 .. ^1].strip()
        if afterColon.len > 2 and afterColon[0] == '"':
          let endQuote = afterColon.find('"', 1)
          if endQuote > 0:
            result.add(StepEntry(
              name: afterColon[1 .. endQuote - 1],
              file: path,
              line: i + 1
            ))

proc scanScenarioFiles(): seq[string] =
  ## Read all .yaml scenario files and extract step references.
  ## Returns list of step names found in scenarios.
  result = @[]
  if not dirExists(scenarioDir):
    return
  for path in walkDirRec(scenarioDir, yieldFilter = {pcFile}):
    if not path.endsWith(yamlExt):
      continue
    let content = readFile(path)
    for line in content.splitLines():
      let stripped = line.strip()
      # Look for step references: - step: "name" or Given/When/Then "name"
      if stripped.startsWith("- step:") or stripped.startsWith("step:"):
        let colonPos = stripped.find(':')
        let val = stripped[colonPos + 1 .. ^1].strip().strip(chars = {'"', '\''})
        if val.len > 0:
          result.add(val)
      elif stripped.startsWith("Given ") or stripped.startsWith("When ") or
           stripped.startsWith("Then ") or stripped.startsWith("And "):
        let spacePos = stripped.find(' ')
        let val = stripped[spacePos + 1 .. ^1].strip().strip(chars = {'"', '\''})
        if val.len > 0:
          result.add(val)

proc main() =
  let registered = scanSourceFiles()
  let scenarioSteps = scanScenarioFiles().toSeq().deduplicate()

  if registered.len == 0:
    echo "OK: No testStep annotations found (registry empty)"
    quit(0)

  var orphans: seq[StepEntry] = @[]
  for entry in registered:
    var found = false
    for s in scenarioSteps:
      if s == entry.name:
        found = true
        break
    if not found:
      orphans.add(entry)

  if orphans.len > 0:
    echo "FAIL: ", orphans.len, " orphaned step(s) found (registered but not in any scenario):"
    for o in orphans:
      echo "  - \"", o.name, "\" at ", o.file, ":", o.line
    quit(1)
  else:
    echo "OK: All ", registered.len, " registered step(s) appear in at least one scenario"

when isMainModule:
  main()
