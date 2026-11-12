## ratchet_check.nim — Touched-File Legacy Violation Checker (Nim port)
## Checks changed files against legacy_violations.txt.
## Supports AXIOM_ALLOW_LEGACY_TEMP=1 bypass with audit logging.
## Also checks ratchet_ceiling.json ceiling.
##
## Exit code: 0 on success, 1 on violation found

import core/trusted/layer_declaration
axiomLayer "tools"
import std/[os, strutils, json, times]

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

const isoFmt = initTimeFormat("yyyy'-'MM'-'dd'T'HH:mm:ss")

proc now_iso(): string =
  now().format(isoFmt)

proc main() =
  let repoRoot = findRepoRoot()
  let legacyFile = repoRoot / "data" / "legacy_violations.txt"
  let auditLog = repoRoot / "logs" / "bypass_audit.jsonl"
  let ceilingFile = repoRoot / "data" / "ratchet_ceiling.json"

  let args = commandLineParams()
  if args.len == 0:
    echo "Usage: ratchet_check <changed-file-1> [changed-file-2] ..."
    quit(0)

  # Check legacy_violations.txt exists
  if not fileExists(legacyFile):
    echo "✅ No legacy violations file found — clean slate."
    quit(0)

  # Read legacy violations content
  var legacyContent: string
  try:
    legacyContent = readFile(legacyFile)
  except IOError:
    echo "✅ No legacy violations file found — clean slate."
    quit(0)

  let legacyLines = legacyContent.splitLines()

  # Check hotfix override
  let allowLegacy = getEnv("AXIOM_ALLOW_LEGACY_TEMP", "0") == "1"

  var violationsFound = 0

  for file in args:
    var found = false
    for line in legacyLines:
      if line.strip().len > 0 and line.contains(file):
        found = true
        break

    if found:
      inc violationsFound
      if allowLegacy:
        echo "⚠️  RATCHET OVERRIDE: " & file & " — AXIOM_ALLOW_LEGACY_TEMP=1"
        echo "   Legacy violation temporarily bypassed."
        try:
          createDir(auditLog.parentDir())
          let entry = %*{
            "timestamp": now_iso(),
            "file": file,
            "override": "AXIOM_ALLOW_LEGACY_TEMP",
            "reason": "hotfix-override"
          }
          let f = open(auditLog, fmAppend)
          defer: f.close()
          f.writeLine($entry)
        except IOError, OSError:
          discard  # axiom:best-effort(audit log write failure — non-fatal)
      else:
        echo "🔴 RATCHET: " & file & " has legacy violations that must be fixed."
        echo "   This file was in legacy_violations.txt — modifying it triggers compliance."
        echo "   Fix the violations, or use: AXIOM_ALLOW_LEGACY_TEMP=1 git commit ..."
        echo ""
        echo "   To see violations: nimtry --file " & file
        quit(1)

  if violationsFound > 0 and allowLegacy:
    echo ""
    echo "⚠️  " & $violationsFound & " file(s) bypassed via Hotfix Override."
    echo "   Audit log: " & auditLog
    echo "   Remember: this is a temporary escape hatch, not a permanent exception."

  # Phase 2: Ratchet Ceiling Check
  if fileExists(ceilingFile) and fileExists(legacyFile):
    try:
      let ceilingJson = parseJson(readFile(ceilingFile))
      let ceilingOpt = ceilingJson{"legacy_violations_ceiling"}
      if ceilingOpt != nil:
        let ceiling = ceilingOpt.getInt()
        let actual = legacyLines.len
        if actual > ceiling:
          echo "🔴 RATCHET CEILING VIOLATION: legacy_violations.txt has " &
               $actual & " lines, ceiling is " & $ceiling & "."
          echo "   The ratchet shrinks the ceiling over time. You must reduce violations."
          echo "   Current file: " & legacyFile & "  |  Ceiling source: " & ceilingFile
          quit(1)
        else:
          echo "✅ Ratchet ceiling OK: " & $actual & "/" & $ceiling & " legacy violations."
    except CatchableError:
      discard  # axiom:best-effort(ceiling JSON parse failure — advisory check)

  quit(0)

when isMainModule:
  main()
