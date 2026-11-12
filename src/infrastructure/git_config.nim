import core/trusted/layer_declaration
axiomLayer "infrastructure"
# src/infrastructure/git_config.nim
# axiomIoBoundary
# State anchoring via git config --local
# Replaces environment variables with deterministic git config values.
# Pattern established by bin/sync-branch (axiom.sync-authorized).

import std/[osproc, strutils]
import ../gate/utils/real_git
import ../core/trusted/env_access
import core/axiom_pragmas

let realGitPath = findRealGit()

proc getGitConfig*(key: string): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Read a git config value. Returns "" if not set or on error.
  try:
    let output = execProcess(realGitPath & " config --local --get " & key).strip()
    return output
  except CatchableError:
    return ""

proc setGitConfig*(key, value: string) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Write a git config value.
  try:
    discard execProcess(realGitPath & " config --local " & key & " " & value)
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)

proc unsetGitConfig*(key: string) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Remove a git config value.
  try:
    discard execProcess(realGitPath & " config --local --unset " & key)
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)

proc isSyncAuthorized*(): bool =
  ## Check if sync is authorized via git config.
  return getGitConfig("axiom.sync-authorized") == "true"

proc getStateLedgerPath*(): string =
  ## Get the state ledger path from git config, falling back to env var.
  let configPath = getGitConfig("axiom.state-ledger-path")
  if configPath.len > 0: return configPath
  return getAxiomEnv(evStateLedgerPath)

proc getProofCachePath*(): string =
  ## Get proof cache path from git config, falling back to default.
  let configPath = getGitConfig("axiom.proof-cache-path")
  if configPath.len > 0: return configPath
  return getAxiomEnv(evProofCachePath, "data/proof_cache")
