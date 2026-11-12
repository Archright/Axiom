import core/trusted/layer_declaration
axiomLayer "presentation"
{.push raises: [CatchableError].}

## Gate Effect Classifier — Classify shell commands by side-effect category.
##
## Phase 1A of the gate_admin four-pillar refactoring. Provides an OpEffect
## enum and command-set constants that downstream gates (epoch validation,
## window inspection, hash derivation) consume to select the correct
## blocking / checking strategy.

import std/strutils

# ---------------------------------------------------------------------------
# Effect classification
# ---------------------------------------------------------------------------

type OpEffect* = enum
  oeIdempotent   ## 조회성 — 반복 차단 대상
  oeMutation     ## 변이성 — 에포크 검증 대상
  oeTransient    ## 일시적 — 기본 윈도우 검사
  oeDerivation   ## 빌드 — 입력 경계 해시로 판정

# ---------------------------------------------------------------------------
# Command sets
# ---------------------------------------------------------------------------

const MUTATION_COMMANDS* = [
  "git", "mkdir", "rm", "mv", "chmod", "chown", "ln", "touch",
  "docker", "pnpm", "npm", "nimble", "cargo",
]

const DERIVATION_COMMANDS* = [
  "nim", "nim c", "nim cpp", "nim js",
  "cargo build", "cargo test", "cargo run",
  "make", "cmake", "zig build",
]

const IDEMPOTENT_COMMANDS* = [
  "ls", "cat", "grep", "rg", "find", "pwd",
  "head", "tail", "wc", "diff", "file", "stat",
  "du", "df", "echo", "printf",
]

const NETWORK_RETRY_COMMANDS* = [
  "git pull", "git fetch", "curl", "wget",
]

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

proc splitTokens(s: string): seq[string] {.raises: [].} =
  ## Split *s* on whitespace, ignoring leading/trailing blanks.
  result = @[]
  for token in s.split(' '):
    if token.len > 0:
      result.add(token)

proc matchesSet(tokens: seq[string], cmdSet: openArray[string]): bool {.raises: [].} =
  ## Return true when *tokens* match any entry in *cmdSet*.
  ## Two-token entries (e.g. "nim c", "cargo build") are checked first
  ## so that "cargo build --release" matches "cargo build" while bare
  ## "cargo" does not.

  # --- two-token entries ---------------------------------------------------
  if tokens.len >= 2:
    for entry in cmdSet:
      let parts = entry.split(' ')
      if parts.len == 2 and parts[0] == tokens[0] and parts[1] == tokens[1]:
        return true

  # --- single-token entries ------------------------------------------------
  if tokens.len >= 1:
    for entry in cmdSet:
      if ' ' notin entry and entry == tokens[0]:
        return true

  return false

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

proc classifyCommand*(cmd: string): OpEffect =
  ## Classify *cmd* into its effect category.
  ##
  ## Priority order: DERIVATION > MUTATION > IDEMPOTENT, defaulting to
  ## TRANSIENT for anything that does not match a known set.

  let tokens = splitTokens(cmd)
  if tokens.len == 0:
    return oeTransient

  if matchesSet(tokens, DERIVATION_COMMANDS):
    return oeDerivation
  if matchesSet(tokens, MUTATION_COMMANDS):
    return oeMutation
  if matchesSet(tokens, IDEMPOTENT_COMMANDS):
    return oeIdempotent

  return oeTransient

proc isDerivationCommand*(cmd: string): bool =
  ## Return true if *cmd* matches a derivation (build) command.
  matchesSet(splitTokens(cmd), DERIVATION_COMMANDS)

proc isNetworkRetryCommand*(cmd: string): bool =
  ## Return true if *cmd* matches a network-retry command.
  matchesSet(splitTokens(cmd), NETWORK_RETRY_COMMANDS)

{.pop.}
