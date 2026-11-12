import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [CatchableError].}

## Hermetic Sandbox — `env -i` + Whitelist Environment Isolation
##
## Provides subprocess execution with a stripped environment containing ONLY
## explicitly whitelisted variables.  Mirrors `env -i` semantics via Nim's
## `osproc.startProcess(env: StringTableRef)` — passing a non-nil table
## replaces the parent environment entirely.
##
## Context7-verified: `osproc.startProcess` accepts `env: StringTableRef = nil`
## (nil = inherit parent, non-nil = isolated).  `osproc.execCmdEx` likewise
## accepts optional `env` since Nim 1.4.
##
## Usage:
##   import infrastructure/hermetic_sandbox
##   let (out, rc) = hermeticExec("nim", @["check", "src/foo.nim"])
##   let p = hermeticStartProcess("z3", @["--version"])

import std/[strtabs, osproc, os]
import core/axiom_pragmas
import core/trusted/env_types

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const
  HermeticWhitelist*: seq[string] = @[
    "PATH",              ## Nim, Z3 binary discovery
    "HOME",              ## choosenim/toolchains path
    "NIMBLE_DIR",        ## package path
    "AXIOM_ROOT",        ## project root
    "SOURCE_DATE_EPOCH", ## deterministic timestamp
    "CC",                ## C compiler (nim c --cc:env)
    "CXX",               ## C++ compiler
  ]

  DefaultEpoch* = "1735689600"
    ## 2025-01-01 00:00:00 UTC — used when SOURCE_DATE_EPOCH is unset.

# ---------------------------------------------------------------------------
# Helpers (pure)
# ---------------------------------------------------------------------------

proc epochOrDefault*(): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Return the current SOURCE_DATE_EPOCH or a fixed default for
  ## deterministic builds when the variable is absent from the parent.
  let env = getAxiomEnv(evSourceDateEpoch)
  if env.len > 0: env else: DefaultEpoch

# ---------------------------------------------------------------------------
# Core API
# ---------------------------------------------------------------------------

proc buildHermeticEnv*(extraVars: seq[string]  = @[]): StringTableRef {.
    axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Build a clean environment with ONLY whitelisted variables.
  ##
  ## `extraVars` are added to the whitelist for this invocation.
  ## Missing variables are silently omitted (no error on absent key).
  ## SOURCE_DATE_EPOCH always receives a value via `epochOrDefault`.
  result = newStringTable(modeCaseSensitive)
  var merged = HermeticWhitelist & extraVars
  for key in merged:
    if key == "SOURCE_DATE_EPOCH":
      result[key] = epochOrDefault()
    else:
      let val = getEnv(key)
      if val.len > 0:
        result[key] = val

proc hermeticExec*(command: string, args: seq[string],
 extraVars: seq[string] = @[]): (string, int) {.
                   axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Execute a command with hermetic environment.
  ##
  ## Returns (output, exitCode) where output is merged stdout+stderr.
  ## `execCmdEx` takes a single command string so args are joined with spaces.
  let env = buildHermeticEnv(extraVars)
  var fullCmd = command
  for a in args:
    fullCmd.add(" " & a)
  let (output, exitCode) = execCmdEx(
    command = fullCmd,
    options = {poStdErrToStdOut, poUsePath},
    env = env
  )
  result = (output, exitCode)

proc hermeticStartProcess*(command: string, args: seq[string],
 extraVars: seq[string] = @[]): Process {.
                           axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Start a process with hermetic environment.
  ##
  ## Caller MUST close() the returned Process and inspect its exit code.
  let env = buildHermeticEnv(extraVars)
  result = startProcess(
    command = command,
    args = args,
    options = {poUsePath, poStdErrToStdOut},
    env = env
  )

{.pop.}
