{.push raises: [].}
## z3_solver_config.nim — SSOT for Z3 binary path resolution.
##
## Priority chain:
##   1. AXIOM_Z3_PATH environment variable (explicit override)
##   2. $HOME/.local/bin/z3 (known installation location)
##   3. "z3" (bare PATH lookup — may fail if ~/.local/bin not in PATH)
##
## This module exists because the compiled binary may not inherit
## the user's full PATH, causing startProcess("z3", ...) to fail
## when Z3 is installed outside standard PATH locations.

import core/trusted/layer_declaration
axiomLayer "domain"
import std/os
import core/trusted/env_types

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc resolveZ3Path*(): string =
  ## Resolve the Z3 binary path at runtime.
  ## Returns the first existing path from the priority chain.
  let envPath = getAxiomEnv(evZ3Path)
  if envPath.len > 0 and fileExists(envPath):
    return envPath
  let homePath = getHomeDir() / ".local" / "bin" / "z3"
  if fileExists(homePath):
    return homePath
  try:
    result = findExe("z3")
  except OSError:
    result = ""
  if result.len == 0:
    result = "z3"
