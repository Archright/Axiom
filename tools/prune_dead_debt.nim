## tools/prune_dead_debt.nim — Debt#256 Prune stale architecture_debt.json entries
##
## Reads data/architecture_debt.json, checks every entry's `file` for disk existence.
## For missing files, attempts git rename detection. If renamed, updates the entry.
## If genuinely deleted, removes the entry. Records actions in data/debt_changelog.json.
## Re-run safe (idempotent): already-fixed files on disk are skipped.
##
## Usage: nim c -r tools/prune_dead_debt.nim

import core/trusted/layer_declaration
axiomLayer "tools"
import std/[os, strutils, json, osproc, times]

const
  ArchDebtPath = "data/architecture_debt.json"
  ChangelogPath = "data/debt_changelog.json"

type
  ActionKind = enum
    akPruned        ## entry removed (file genuinely deleted)
    akRenamedUpdated ## entry file path updated (file was renamed in git)

  ChangelogEntry = object
    timestamp: string
    file: string
    action: string
    newPath: string

proc getIsoNow(): string =
  let now = now().utc
  result = $now
  # Remove trailing sub-second precision and replace timezone
  if '.' in result:
    let dotPos = result.find('.')
    result = result[0..<dotPos] & "Z"
  elif 'Z' notin result:
    result = result & "Z"

proc tryDetectRename(gitRoot, oldPath: string): string =
  ## Attempt to find a rename target for oldPath via git.
  ## Strategy:
  ##   1. git log --diff-filter=R --follow --name-status --format="" -- <oldPath>
  ##      This can find renames even across commits.
  ##   2. If found, parse "R<score>\t<old>\t<new>" lines where the new path
  ##      exists on disk.
  let (outp, exitCode) = execCmdEx(
    "git -C " & gitRoot.quoteShell &
    " log --diff-filter=R --follow --name-status --format=\"\" -- " &
    oldPath.quoteShell, options = {poStdErrToStdOut})
  if exitCode != 0:
    return ""

  var candidates: seq[string]
  for line in outp.splitLines():
    let trimmed = line.strip()
    if trimmed.len == 0: continue
    if trimmed[0] != 'R': continue
    # Format: R<score>\t<old>\t<new> or R<score>\t<old>\t<new>
    let parts = trimmed.split('\t')
    if parts.len >= 3:
      let newPath = parts[^1]
      if fileExists(newPath):
        candidates.add(newPath)

  if candidates.len > 0:
    return candidates[^1]  # most recent rename target
  return ""

proc main() =
  let gitRoot = "."

  # Read architecture_debt.json
  if not fileExists(ArchDebtPath):
    stderr.writeLine("FATAL: " & ArchDebtPath & " not found")
    quit(1)

  let rawJson = parseJson(readFile(ArchDebtPath))
  var entries = rawJson["entries"]
  var changelog: seq[ChangelogEntry]

  # Read existing changelog if present
  if fileExists(ChangelogPath):
    try:
      let clRaw = parseJson(readFile(ChangelogPath))
      if clRaw.hasKey("records") and clRaw["records"].kind == JArray:
        for item in clRaw["records"]:
          var clEntry: ChangelogEntry
          clEntry.timestamp = item{"timestamp"}.getStr("")
          clEntry.file = item{"file"}.getStr("")
          clEntry.action = item{"action"}.getStr("")
          clEntry.newPath = item{"newPath"}.getStr("")
          changelog.add(clEntry)
    except:
      discard  # start fresh if corrupt

  var keptEntries: seq[JsonNode]
  var prunedCount = 0
  var renamedCount = 0
  var renameDetails: seq[string]

  for entry in entries:
    let filePath = entry{"file"}.getStr("")
    if filePath.len == 0:
      keptEntries.add(entry)
      continue

    if fileExists(filePath):
      keptEntries.add(entry)
      continue

    # File does not exist — try rename detection
    let newPath = tryDetectRename(gitRoot, filePath)

    if newPath.len > 0 and fileExists(newPath):
      # Renamed — update the entry
      entry["file"] = newJString(newPath)
      keptEntries.add(entry)
      inc renamedCount
      renameDetails.add(filePath & " → " & newPath)
      let now = getIsoNow()
      changelog.add(ChangelogEntry(
        timestamp: now, file: filePath,
        action: "renamed-updated", newPath: newPath))
      echo "  RENAMED: " & filePath & " → " & newPath
    else:
      # Genuinely deleted — prune
      inc prunedCount
      let now = getIsoNow()
      changelog.add(ChangelogEntry(
        timestamp: now, file: filePath,
        action: "pruned", newPath: ""))
      echo "  PRUNED: " & filePath

  # Write updated architecture_debt.json idempotently.
  # firstSeen/lastSeen are audit metadata — excluded from comparison.
  let outputJson = %*{"version": 1, "entries": keptEntries}
  var archChanged = true
  if fileExists(ArchDebtPath):
    try:
      let existing = readFile(ArchDebtPath)
      let existingJson = parseJson(existing)
      var stableExisting = existingJson
      for entry in stableExisting["entries"]:
        if entry.hasKey("firstSeen"):
          entry["firstSeen"] = %""
        if entry.hasKey("lastSeen"):
          entry["lastSeen"] = %""
      var stableOutput = outputJson
      for entry in stableOutput["entries"]:
        if entry.hasKey("firstSeen"):
          entry["firstSeen"] = %""
        if entry.hasKey("lastSeen"):
          entry["lastSeen"] = %""
      if stableExisting.pretty == stableOutput.pretty:
        archChanged = false
    except CatchableError: # axiom:best-effort(unreadable-prior-arch-debt: treated as changed, idempotent write still proceeds)
      discard
  if archChanged:
    writeFile(ArchDebtPath, outputJson.pretty())

  # Write changelog idempotently.
  # timestamp is audit metadata — excluded from comparison.
  var clArray: seq[JsonNode]
  for clEntry in changelog:
    var obj = %*{
      "timestamp": clEntry.timestamp,
      "file": clEntry.file,
      "action": clEntry.action
    }
    if clEntry.newPath.len > 0:
      obj["newPath"] = %clEntry.newPath
    clArray.add(obj)
  let clJson = (%*{"records": clArray}).pretty()
  var clChanged = true
  if fileExists(ChangelogPath):
    try:
      let existing = readFile(ChangelogPath)
      let existingJson = parseJson(existing)
      var stableExisting = existingJson
      for record in stableExisting["records"]:
        if record.hasKey("timestamp"):
          record["timestamp"] = %""
      let stableCl = parseJson(clJson)
      for record in stableCl["records"]:
        if record.hasKey("timestamp"):
          record["timestamp"] = %""
      if stableExisting.pretty == stableCl.pretty:
        clChanged = false
    except CatchableError: # axiom:best-effort(unreadable-prior-changelog: treated as changed, idempotent write still proceeds)
      discard
  if clChanged:
    writeFile(ChangelogPath, clJson)

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  Pruned: " & $prunedCount & " entries"
  echo "  Renamed/updated: " & $renamedCount & " entries"
  for d in renameDetails:
    echo "    " & d
  echo "  Remaining: " & $keptEntries.len & " entries"
  echo "  Changelog: " & ChangelogPath
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

main()
