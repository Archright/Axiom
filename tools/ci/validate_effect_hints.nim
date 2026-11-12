## validate_effect_hints.nim — CI gate: validate [effect_hints] in architecture_policy.lock
##
## Port of tools/ci/validate_effect_hints.py
## Reads src/gate/architecture_policy.lock, extracts [effect_hints] module entries,
## and verifies each listed file:
##   1. Actually exists in the repo.
##   2. Contains at least one FFI pragma (importc/importcpp/dynlib/{.compile.})
##      OR is one of the known shield modules (stdlib_shield.nim, effect_shim.nim).
##
## These shields are conservatively classified as I/O because the Nim compiler
## cannot prove their purity (see docs/spec/nim_effect_system_quirks.md §7, §1.1).
##
## Exit code: 0 = PASS, 1 = FAIL
##
## Usage:
##   nim c tools/ci/validate_effect_hints.nim
##   ./validate_effect_hints
##   # or from repo root:
##   nim c -o:bin/validate_effect_hints tools/ci/validate_effect_hints.nim

import core/trusted/layer_declaration
axiomLayer "tools"
import shared_types/shared_types
import api/tools_facade
import std/os
import std/strutils
const
  LockRelPath = "src/gate/architecture_policy.lock"
  # Modules exempt from FFI-pragma check: effect-isolation shields wrapping stdlib calls.
  ShieldModules = ["stdlib_shield.nim", "effect_shim.nim"]

# ---------------------------------------------------------------------------
# Repo root resolution (compile-time anchor via currentSourcePath)
# ---------------------------------------------------------------------------
## validate_effect_hints.nim — CI gate: validate [effect_hints] in architecture_policy.lock
##
## Port of tools/ci/validate_effect_hints.py
## Reads src/gate/architecture_policy.lock, extracts [effect_hints] module entries,
## and verifies each listed file:
##   1. Actually exists in the repo.
##   2. Contains at least one FFI pragma (importc/importcpp/dynlib/{.compile.})
##      OR is one of the known shield modules (stdlib_shield.nim, effect_shim.nim).
##
## These shields are conservatively classified as I/O because the Nim compiler
## cannot prove their purity (see docs/spec/nim_effect_system_quirks.md §7, §1.1).
##
## Exit code: 0 = PASS, 1 = FAIL
##
## Usage:
##   nim c tools/ci/validate_effect_hints.nim
##   ./validate_effect_hints
##   # or from repo root:
##   nim c -o:bin/validate_effect_hints tools/ci/validate_effect_hints.nim
func repoRoot(): string {.raises: [].} =
  ## Resolve repo root from the source file location (tools/ci/ → repo root).
  parentDir(parentDir(parentDir(currentSourcePath())))

# ---------------------------------------------------------------------------
# Pure helpers (func — no side effects)
# ---------------------------------------------------------------------------
func containsFfiPragma(line: string): bool {.raises: [].} =
  ## Return true if line contains an FFI pragma pattern.
  ## Mirrors Python: r"\bimportc[.:]|importcpp[.:]|dynlib[.:]|compile[.:]"
  const patterns = [
    "importc.", "importc:",
    "importcpp.", "importcpp:",
    "dynlib.", "dynlib:",
    "compile.", "compile:"
  ]
  for p in patterns:
    if p in line:
      return true
  false
func isShieldModule(modulePath: string): bool {.raises: [].} =
  ## Return true if the module is a known effect-isolation shield.
  let basename = lastPathPart(modulePath)
  for s in ShieldModules:
    if basename == s:
      return true
  false
type
  HintEntry = object
    path: string
    reason: string
func parseEffectHintModules(lockText: string): seq[HintEntry] {.raises: [].} =
  ## Extract module paths from [effect_hints] section (not [effect_hints.functions]).
  var inSection = false
  for line in lockText.splitLines():
    let stripped = line.strip()

    # Section header detection
    if stripped.startsWith("["):
      if stripped == "[effect_hints]":
        inSection = true
      elif inSection and (
          stripped.startsWith("[effect_hints.") or
          (stripped.startsWith("[") and stripped != "[effect_hints]")):
        inSection = false
      continue

    if not inSection:
      continue

    # Skip blank / comment lines
    if stripped.len == 0 or stripped.startsWith("#"):
      continue

    # Format: "src/path/to/file.nim" = { ... }
    if stripped.startsWith("\"") and ".nim\" =" in stripped:
      let startIdx = 1
      let endIdx = stripped.find("\"", startIdx)
      if endIdx > startIdx:
        let path = stripped[startIdx ..< endIdx]
        # Extract reason for diagnostic output
        var reason = ""
        let reasonIdx = stripped.find("reason")
        if reasonIdx >= 0:
          let eqIdx = stripped.find("=", reasonIdx + 6)
          if eqIdx >= 0:
            let q1 = stripped.find("\"", eqIdx + 1)
            if q1 >= 0:
              let q2 = stripped.find("\"", q1 + 1)
              if q2 > q1:
                reason = stripped[q1 + 1 ..< q2]
        result.add(HintEntry(path: path, reason: reason))

# ---------------------------------------------------------------------------
# I/O procs — these use {.axiomEffect: IoEffect.}
# ---------------------------------------------------------------------------
proc readFileContent(path: string): string {.axiomEffect: IoEffect.} =
  ## Read file contents, returning empty string on error.
  try:
    result = readFile(path)
  except IOError, OSError:
    result = ""
proc printMsg(msg: string) {.axiomEffect: IoEffect.} =
  ## Print a message to stdout.
  echo msg

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
proc main() {.axiomEffect: IoEffect.} =
  let root = repoRoot()
  let lockFile = root / LockRelPath

  if not fileExists(lockFile):
    printMsg("FAIL: lock file not found: " & lockFile)
    quit(1)

  let lockText = readFileContent(lockFile)
  if lockText.len == 0:
    printMsg("FAIL: lock file is empty: " & lockFile)
    quit(1)

  let entries = parseEffectHintModules(lockText)

  if entries.len == 0:
    printMsg("WARN: [effect_hints] section is empty or missing — nothing to validate")
    quit(0)

  var errors: seq[string] = @[]
  var checked = 0

  for entry in entries:
    let absPath = root / entry.path
    inc checked

    # Check 1: file exists
    if not fileExists(absPath):
      errors.add("  MISSING: " & entry.path &
        " — listed in [effect_hints] but not found in repo")
      continue

    # Check 2: FFI pragma or shield module
    if isShieldModule(entry.path):
      printMsg("  OK (shield): " & entry.path)
      continue

    let content = readFileContent(absPath)
    var hasFfi = false
    if content.len > 0:
      for line in content.splitLines():
        if containsFfiPragma(line):
          hasFfi = true
          break

    if hasFfi:
      printMsg("  OK (FFI):    " & entry.path)
      continue

    errors.add("  NO-FFI:     " & entry.path &
      " — listed in [effect_hints] but contains no " &
      "FFI pragma (importc/importcpp/dynlib/compile) and is not a known shield module")

  # Result
  printMsg("")
  if errors.len > 0:
    printMsg("FAIL: " & $errors.len &
      " effect_hints entry(ies) failed validation (" & $checked & " checked)")
    for e in errors:
      printMsg(e)
    quit(1)
  else:
    printMsg("PASS: all " & $checked & " [effect_hints] entries are valid")
    quit(0)

when isMainModule:
  main()
