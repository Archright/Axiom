## test_helper.nim — Deterministic test helper for gateway tests.
## Provides runGateInRepo for running gate binaries with AXIOM_ROOT injected
## and working directory set to the project root.

import core/trusted/layer_declaration
axiomLayer "domain"
import std/[os, osproc]
import core/utils/repo_root
import core/trusted/axiom_pragmas
{.push raises: [].}

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc runGateInRepo*(gateBinary: string; args: seq[string] = @[]): tuple[output: string, exitCode: int] {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Run a gate binary from the project root with AXIOM_ROOT env var set.
  ## stderr is redirected to stdout for capture.
  ## The child process inherits AXIOM_ROOT pointing to the project root.
  let root = findRepoRoot()
  putEnv("AXIOM_ROOT", root)
  var fullCmd = quoteShell(root / gateBinary)
  for arg in args:
    fullCmd &= " " & quoteShell(arg)
  fullCmd &= " 2>&1"
  result = execCmdEx(fullCmd, options = {}, workingDir = root)

{.pop}
