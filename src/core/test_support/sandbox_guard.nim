## Hermetic PBT Sandbox Guard
##
## Provides a `hermeticSandbox` macro that isolates PBT (Property-Based Test)
## execution environments from ambient system state. Ensures deterministic,
## repeatable test runs by capturing and restoring global side effects.
##
## Design: Layer 3 of Shadow-AST Metaprogramming Pipeline
## Reference: AGENTS.md §0.2 (First-Principles Elegance)
##   - Ideal:       compile-time enforcement of sandbox boundary
##   - Elegant:     language-native macro (no external tooling)
##   - Fundamental: no hardcoded exceptions
##   - Deterministic: identical input → identical output

import core/trusted/layer_declaration
axiomLayer "domain"
import std/macros
import std/os
import ../trusted/env_access
import core/trusted/axiom_pragmas

# ── Environment Snapshot Types ────────────────────────────────────────────────

{.push raises: [].}
# axiomIoBoundary

type
  EnvSnapshot* = object
    ## Captured environment state for deterministic restoration
    workingDir: string
    envVars: seq[(string, string)]

{.pop.}

# ── Snapshot Operations (I/O boundary — proc, raises: [OSError]) ─────────────

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc captureEnv*(vars: openArray[EnvVar]): EnvSnapshot {.raises: [OSError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Capture current environment state for specified variables.
  ## Only captures listed variables — minimal footprint.
  result.workingDir = getCurrentDir()
  result.envVars = @[]
  for v in vars:
    result.envVars.add((envName(v), getAxiomEnv(v)))

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc restoreEnv*(snap: EnvSnapshot) {.raises: [OSError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Restore environment to captured snapshot.
  setCurrentDir(snap.workingDir)
  for (k, v) in snap.envVars:
    if v.len == 0:
      os.delEnv(k)
    else:
      os.putEnv(k, v)

# ── Hermetic Sandbox Macro ────────────────────────────────────────────────────

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
macro hermeticSandbox*(envVars: static openArray[EnvVar]; body: untyped): untyped =
  ## Wraps `body` in an environment-isolated sandbox for PBT execution.
  ##
  ## At compile time: generates capture/restore wrappers around the body.
  ## At runtime: captures specified env vars + CWD, executes body, restores.
  ## If body raises, restoration is guaranteed via try/finally.
  ##
  ## Usage:
  ##   hermeticSandbox(["HOME", "PATH", "AXIOM_ENV"]):
  ##     let result = somePropertyTest(input)
  ##     assert result.passed
  ##
  ## Guarantees:
  ##   1. Environment state is captured before body execution
  ##   2. Environment state is restored after body (success or failure)
  ##   3. Compile-time error if envVars is empty (degenerate sandbox)
  ##
  ## Design:
  ##   - Snapshot pattern: capture → execute → restore (finally)
  ##   - No runtime overhead in non-sandbox contexts
  ##   - Zero-footprint: no persistent state after restoration

  # Compile-time guard: reject empty envVars
  # (use `if` + `error()` — `when` cannot see static params in macro body)
  if envVars.len == 0:
    error("hermeticSandbox: envVars must not be empty. " &
          "Specify at least one environment variable to isolate.", body)

  let snapshotSym = genSym(nskLet, "sandboxSnapshot")
  let varsLit = newNimNode(nnkBracket)
  for v in envVars:
    varsLit.add(newLit(v))

  result = quote do:
    block:
      let `snapshotSym` = captureEnv(`varsLit`)
      try:
        `body`
      finally:
        restoreEnv(`snapshotSym`)

# ── Convenience Templates ─────────────────────────────────────────────────────

{.push raises: [].}

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
template hermeticPbt*(body: untyped): untyped =
  ## Pre-configured hermetic sandbox for standard PBT runs.
  ## Isolates HOME, PATH, and project-specific AXIOM_* variables.
  hermeticSandbox([evHome, evPath, evAxiomEnv, evAxiomLogLevel]):
    body

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
template hermeticMinimal*(body: untyped): untyped =
  ## Minimal hermetic sandbox — isolates only HOME and PATH.
  ## Use when test logic does not depend on Axiom-specific env vars.
  hermeticSandbox([evHome, evPath]):
    body

{.pop.}


