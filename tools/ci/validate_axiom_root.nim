## validate_axiom_root.nim — Validates deterministic project root resolution.
##
## Checks that AXIOM_ROOT (when set) points to a real project root containing
## `.axiom_root` or `axiom.toml`, and that it matches the walk computed from the
## binary's own location.
##
## Exit codes:
##   0 — valid (or informational: AXIOM_ROOT unset)
##   1 — validation failed
##
## Usage:
##   nim c -d:release -o:bin/validate_axiom_root tools/ci/validate_axiom_root.nim
##   bin/validate_axiom_root

import core/trusted/layer_declaration
axiomLayer "tools"
import std/os

const
  axiomRootAnchor = ".axiom_root"
  axiomTomlFallback = "axiom.toml"

proc findProjectRoot*(startDir: string): string {.raises: [].} =
  ## Deterministic walk: mirror of repo_root.nim logic.
  ## Walks up to 10 ancestors looking for the anchor files.
  result = startDir
  for _ in 0..10:
    try:
      if fileExists(result / axiomRootAnchor):
        return result
      if fileExists(result / axiomTomlFallback):
        return result
    except CatchableError:
      discard  # axiom:best-effort(path access failure — continues walking up)
    let parent = parentDir(result)
    if parent == result:
      break
    result = parent
  # Fallback: one level up from startDir (legacy compat for bin/ layout)
  result = parentDir(startDir)

proc resolveBinaryDir(): string {.raises: [].} =
  ## Directory containing the running binary.
  getAppDir()

proc normalizePath(p: string): string {.raises: [CatchableError].} =
  ## Canonicalize path: resolve to absolute, then expand symlinks if possible.
  result = absolutePath(p)
  try:
    result = expandFilename(result)
  except CatchableError:
    discard  # axiom:best-effort(expandFilename failure — returns absolute path as-is)

proc main() =
  let binaryDir = resolveBinaryDir()
  let computedRoot = normalizePath(findProjectRoot(binaryDir))
  let envRoot = getEnv("AXIOM_ROOT")

  if envRoot.len == 0:
    # Informational: AXIOM_ROOT not set.
    echo "AXIOM_ROOT is not set."
    echo "For CI/subagent environments, set: AXIOM_ROOT=" & computedRoot
    echo "Local shells may rely on heuristic resolution."
    quit(0)

  # --- AXIOM_ROOT is set: validate it ---

  let normalizedEnv = normalizePath(envRoot)

  # 1. Directory must exist.
  if not dirExists(normalizedEnv):
    stderr.writeLine("VALIDATE AXIOM_ROOT FAIL: directory does not exist")
    stderr.writeLine("  expected (computed): " & computedRoot)
    stderr.writeLine("  actual   (AXIOM_ROOT): " & normalizedEnv)
    quit(1)

  # 2. Must contain .axiom_root or axiom.toml.
  let hasAnchor = fileExists(normalizedEnv / axiomRootAnchor)
  let hasFallback = fileExists(normalizedEnv / axiomTomlFallback)
  if not (hasAnchor or hasFallback):
    stderr.writeLine("VALIDATE AXIOM_ROOT FAIL: no project root anchor found")
    stderr.writeLine("  expected (computed): " & computedRoot)
    stderr.writeLine("  actual   (AXIOM_ROOT): " & normalizedEnv)
    stderr.writeLine("  missing: " & axiomRootAnchor & " and " & axiomTomlFallback)
    quit(1)

  # 3. Must match the deterministic walk from binary location.
  if normalizedEnv != computedRoot:
    stderr.writeLine("VALIDATE AXIOM_ROOT FAIL: path mismatch")
    stderr.writeLine("  computed from binary: " & computedRoot)
    stderr.writeLine("  AXIOM_ROOT:           " & normalizedEnv)
    quit(1)

  echo "VALIDATE AXIOM_ROOT PASS: " & normalizedEnv

when isMainModule:
  main()
