## ratchet_shrink.nim — Weekly ceiling reduction for the ratchet effect (Nim port)
## Reduces legacy_violations_ceiling and impure_proc_ceiling by shrink_rate_percent.
## Usage: ratchet_shrink [--dry-run]
## Exit code: 0 on success

import core/trusted/layer_declaration
axiomLayer "tools"
import std/[os, strutils, json, times, math]

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

proc main() =
  let repoRoot = findRepoRoot()
  let ceilingFile = repoRoot / "data" / "ratchet_ceiling.json"
  let args = commandLineParams()
  let dryRun = args.len > 0 and args[0] == "--dry-run"

  if not fileExists(ceilingFile):
    echo "❌ ratchet_ceiling.json not found at " & ceilingFile
    quit(1)

  var ceilingJson: JsonNode
  try:
    ceilingJson = parseJson(readFile(ceilingFile))
  except CatchableError as e:
    echo "❌ Failed to read ratchet_ceiling.json: " & e.msg
    quit(1)

  let legacyCeiling = ceilingJson["legacy_violations_ceiling"].getInt()
  let impureCeiling = ceilingJson["impure_proc_ceiling"].getInt()
  let shrinkRate = ceilingJson["shrink_rate_percent"].getInt()
  let lastShrink = ceilingJson["last_shrink_date"].getStr()
  let nextShrinkDate = ceilingJson["next_shrink_date"].getStr()

  let today = now().format("yyyy-MM-dd")

  if today < nextShrinkDate:
    echo "⏭ Ratchet shrink not due yet. Next shrink: " & nextShrinkDate
    quit(0)

  let newLegacy = ceil(legacyCeiling.float * (1.0 - shrinkRate.float / 100.0)).int
  let newImpure = ceil(impureCeiling.float * (1.0 - shrinkRate.float / 100.0)).int
  let nextShrink = (now() + initDuration(days = 7)).format("yyyy-MM-dd")

  echo "📊 Ratchet Shrink Report"
  echo "   Legacy violations: " & $legacyCeiling & " → " & $newLegacy &
       " (-" & $shrinkRate & "%)"
  echo "   Impure procs:      " & $impureCeiling & " → " & $newImpure &
       " (-" & $shrinkRate & "%)"
  echo "   Last shrink:       " & lastShrink & " → " & today
  echo "   Next shrink:       " & nextShrink

  if dryRun:
    echo "🔒 [DRY RUN] No changes written."
    quit(0)

  ceilingJson["legacy_violations_ceiling"] = newJInt(newLegacy)
  ceilingJson["impure_proc_ceiling"] = newJInt(newImpure)
  ceilingJson["last_shrink_date"] = newJString(today)
  ceilingJson["next_shrink_date"] = newJString(nextShrink)

  try:
    writeFile(ceilingFile, pretty(ceilingJson, indent = 2))
  except IOError as e:
    echo "❌ Failed to write ratchet_ceiling.json: " & e.msg
    quit(1)

  echo "✅ ratchet_ceiling.json updated."

when isMainModule:
  main()
