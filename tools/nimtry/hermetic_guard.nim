## hermetic_guard.nim — Verifies no gorge("grep") or external process
## dependencies remain in config.nims or core modules.
##
## This is a BUILD-TIME enforcement that prevents regression to
## external process dependencies. Part of the Hermetic Enforcement plan.
##
## Architecture (post Hermetic Build Orchestrator):
## - config.nims delegates ALL build introspection to bin/hermetic_build
## - bin/hermetic_build (tools/hermetic_build.nim) generates src/generated/build_env.nim
## - src/ modules import build_env for constants (Z3Version, CommitCount, GitHash)
## - Remaining gorge calls in config.nims: hermetic_build invocation, git CI-only,
##   git warning, sha256sum, ldd, z3, date, nim version (NimScript necessities)
##
## Scans:
## 1. config.nims — build configuration (must be hermetic)
## 2. src/ directories — source code (must not shell out for data)
##
## Run: nim c -r tools/nimtry/hermetic_guard.nim

import core/trusted/layer_declaration
axiomLayer "tools"
import std/[os, strutils]

const
  forbiddenPatterns = [
    ("gorge(\"grep", "gorge with grep — use readFile + parseJson instead"),
    ("gorge(\"find ", "gorge with find — use walkDir/walkDirRec instead"),
    ("gorge(\"stat ", "gorge with stat — use getFileInfo instead"),
    ("gorge(\"wc ", "gorge with wc — use len() on content instead"),
    ("gorge(\"cut ", "gorge with cut — use strutils.split instead"),
    ("gorge(\"awk ", "gorge with awk — use strutils/parseutils instead"),
    ("gorge(\"sed ", "gorge with sed — use strutils.replace instead"),
    ("gorge(\"sort ", "gorge with sort — use algorithm.sort instead"),
    ("gorge(\"cat ", "gorge with cat — use readFile instead"),
    ("gorge(\"head ", "gorge with head — use readFile + lines instead"),
    ("gorge(\"tail ", "gorge with tail — use readFile + lines instead"),
    ("gorge(\"diff ", "gorge with diff — use strutils comparison instead"),
    ("gorge(\"mkdir ", "gorge with mkdir — use createDir instead"),
    ("gorge(\"rm ", "gorge with rm — use removeFile/removeDir instead"),
    ("gorge(\"cp ", "gorge with cp — use copyFile/copyDir instead"),
    ("gorge(\"mv ", "gorge with mv — use moveFile/moveDir instead"),
    ("gorge(\"chmod ", "gorge with chmod — use setPermissions instead"),
    ("gorge(\"which ", "gorge with which — use findExe instead"),
    ("gorge(\"uname ", "gorge with uname — use system.hostOS/system.hostCPU instead"),
    ("execCmd(\"grep", "execCmd with grep — use readFile + parseJson instead"),
    ("execCmd(\"find ", "execCmd with find — use walkDir/walkDirRec instead"),
    ("execCmd(\"cat ", "execCmd with cat — use readFile instead"),
    ("gorgeEx(\"grep", "gorgeEx with grep — use readFile + parseJson instead"),
    ("gorgeEx(\"find ", "gorgeEx with find — use walkDir/walkDirRec instead"),
    ("gorgeEx(\"stat ", "gorgeEx with stat — use getFileInfo instead"),
    # --- Migrated from config.nims (Hermetic Build Orchestrator v28) ---
    ("gorgeEx(\"sha256sum", "gorgeEx with sha256sum — use checksums/sha2 instead"),
    ("gorge(\"sha256sum", "gorge with sha256sum — use checksums/sha2 instead"),
    ("execCmdEx(\"sha256sum", "execCmdEx with sha256sum — use checksums/sha2 instead"),
    ("gorge(\"ls ", "gorge with ls — use walkDir/walkDirRec instead"),
    ("gorge(\"git ", "gorge with git — use .git/ direct reads or native git operations instead"),
    ("gorge(\"ldd ", "gorge with ldd — use compile-time host detection instead"),
    ("gorge(\"z3 ", "gorge with z3 — use hermetic_build/build_env constants instead"),
    ("gorge(\"date ", "gorge with date — use std/times instead"),
    ("gorge(\"nim ", "gorge with nim — use compile-time version constants instead"),
  ]

  scanTargets = [
    "config.nims",
  ]

  nimscriptAccepted: seq[(string, string)] = @[
    ## Post Hermetic Build Orchestrator: ALL build introspection (grep, stat,
    ## find, sha256) has been moved to bin/hermetic_build (tools/hermetic_build.nim).
    ## src/generated/build_env.nim is auto-generated with frozen constants.
    ##
    ## Remaining gorge calls in config.nims are architectural necessities:
    ## - gorgeEx("bin/hermetic_build") — orchestrator invocation (intentional)
    ## - gorgeEx("git status/diff") — CI-only golden data check (axiomStrict)
    ## - gorge("git config") — hooksPath warning only
    ##
    ## Some now match forbiddenPatterns (git, sha256sum, ldd, z3, date, nim)
    ## because those patterns were added to prevent re-introduction in src/.
    ## Config.nims NimScript limitations are documented, not excepted.
    ## See docs/spec/nim_effect_system_quirks.md §14 for historical context.
  ]

  srcScanDirs = [
    "src/core",
    "src/cli",
    "src/engine",
    "src/gate",
    "src/api",
    "src/infrastructure",
    "src/mcp",
    "src/frontend",
    "src/generated",
    "src/verification",
    "src/sieve",
    "src/personas",
  ]

proc isNimscriptAccepted(path: string, pattern: string): bool =
  ## Check if this violation is an accepted NimScript limitation.
  for (acceptedPath, acceptedPattern) in nimscriptAccepted:
    if path.endsWith(acceptedPath) and pattern == acceptedPattern:
      return true
  return false

proc scanFile(path: string): tuple[violations: seq[string], accepted: seq[string]] =
  ## Scan a single file for forbidden external process patterns.
  ## Returns (violations, accepted_nimscript_exceptions).
  result = (@[], @[])
  try:
    let content = readFile(path)
    for lineNum, line in content.splitLines().pairs():
      let stripped = line.strip()
      # Skip comments
      if stripped.startsWith("#") or stripped.startsWith("##"):
        continue
      for (pattern, reason) in forbiddenPatterns:
        if stripped.contains(pattern):
          let entry = path & ":" & $(lineNum + 1) & ": " & stripped & "  # " & reason
          if isNimscriptAccepted(path, pattern):
            result.accepted.add(entry)
          else:
            result.violations.add(entry)
  except CatchableError: # axiom:best-effort(unreadable scan target — skipped)
    discard

proc main() =
  echo "=== Hermetic Guard ==="
  echo ""

  var violations: seq[string] = @[]
  var accepted: seq[string] = @[]

  # Scan config files
  for target in scanTargets:
    if fileExists(target):
      echo "Scanning " & target & "..."
      let (v, a) = scanFile(target)
      violations.add(v)
      accepted.add(a)
    else:
      echo "SKIP: " & target & " not found."

  # Scan src/ directories
  for dir in srcScanDirs:
    if not dirExists(dir):
      continue
    for entry in walkDirRec(dir):
      if entry.endsWith(".nim"):
        let (v, a) = scanFile(entry)
        violations.add(v)
        accepted.add(a)

  echo ""

  if accepted.len > 0:
    echo "NOTE: " & $accepted.len & " accepted NimScript limitation(s):"
    echo ""
    for a in accepted:
      echo "  [NimScript] " & a
    echo ""
    echo "These are documented in docs/spec/nim_effect_system_quirks.md §14."
    echo "Full resolution requires migrating checks to compiled gate binaries."
    echo ""

  if violations.len > 0:
    echo "FAIL: " & $violations.len & " hermetic guard violations detected:"
    echo ""
    for v in violations:
      echo "  " & v
    echo ""
    echo "These external process dependencies violate the Hermetic Enforcement policy."
    echo "Replace with Nim-native alternatives (readFile, parseJson, walkDir, etc.)."
    quit(1)
  else:
    echo "PASS: Hermetic guard — no external process dependencies found."
    quit(0)

main()
