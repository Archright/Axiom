import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

## DiscoveryError Taxonomy (Wave 2)
##
## Structured error classification for Lean compiler failures.
## Each error is classified into a taxonomy kind, archived with metadata,
## and translated into a strategic hint for the next synthesis round.

import std/strutils
import std/os
import core/json/std_redirect
import core/utils/io_utils
import core/axiom_pragmas
# axiomIoBoundary

type
  DiscoveryErrorKind* = enum
    dekSyntaxError = "syntax_error"
    dekTypeMismatch = "type_mismatch"
    dekUnknownConstant = "unknown_constant"
    dekUnsolvedGoals = "unsolved_goals"
    dekNoGoals = "no_goals"
    dekAgentBehavior = "agent_behavior"
    dekTimeout = "timeout"
    dekInfrastructure = "infrastructure"
    dekNamespaceConflict = "namespace_conflict"  # Wave I
    dekUnknown = "unknown"

  DiscoveryError* = object
    kind*: DiscoveryErrorKind
    rawMessage*: string
    line*: int
    column*: int
    leanSource*: string
    timestamp*: string
    round*: int
    nodeId*: string
    strategy*: string
    strategicHint*: string

# ---------------------------------------------------------------------------
# Classification Engine
# ---------------------------------------------------------------------------

## Classify Lean Compiler Error.
# @axiom-hint: lean="dekAgentBehavior ∧ dekTimeout ∧ dekSyntaxError ∧ dekTypeMismatch ∧ dekUnknownConstant ∧ dekUnsolvedGoals ∧ dekNoGoals ∧ dekInfrastructure" smt="(assert (and dekAgentBehavior dekTimeout dekSyntaxError dekTypeMismatch dekUnknownConstant dekUnsolvedGoals dekNoGoals dekInfrastructure))"
proc classifyLeanCompilerError*(diagnostics: string): DiscoveryErrorKind {.raises: [].} =
  ## Map a raw Lean compiler diagnostic string to a structured error kind.
  let lower = diagnostics.toLowerAscii()
  if "agent behavior" in lower or "tool_use" in lower or "bash" in lower:
    return dekAgentBehavior
  if "timeout" in lower or "timed out" in lower:
    return dekTimeout
  ## Wave I (Discovery Intelligence): expanded pattern matching for
  ## Leanstral-generated syntax errors that were previously classified as unknown.
  if "expected" in lower and ("token" in lower or "command" in lower):
    return dekSyntaxError
  if "unexpected token" in lower and "%" in lower:
    return dekSyntaxError  # Nim operator residue in Lean
  if "already been declared" in lower:
    return dekNamespaceConflict  # theorem name collision
  if "unexpected identifier" in lower and "expected command" in lower:
    return dekSyntaxError
  if "type mismatch" in lower:
    return dekTypeMismatch
  if "is not a proposition" in lower:
    return dekTypeMismatch
  if "has type" in lower and "but is expected" in lower:
    return dekTypeMismatch
  if "unknown constant" in lower or "unknown module prefix" in lower:
    return dekUnknownConstant
  if "unsolved goals" in lower:
    return dekUnsolvedGoals
  if "no goals to be solved" in lower or "no goals" in lower:
    return dekNoGoals
  if "infrastructure" in lower or "network" in lower or "filesystem" in lower:
    return dekInfrastructure
  dekUnknown

# ---------------------------------------------------------------------------
# Strategic Hint Generator
# ---------------------------------------------------------------------------

## Generate Strategic Hint.
# @axiom-hint: lean="dekSyntaxError ∧ dekTypeMismatch ∧ dekUnknownConstant ∧ dekUnsolvedGoals ∧ dekNoGoals ∧ dekAgentBehavior ∧ dekTimeout ∧ dekInfrastructure ∧ dekUnknown" smt="(assert (and dekSyntaxError dekTypeMismatch dekUnknownConstant dekUnsolvedGoals dekNoGoals dekAgentBehavior dekTimeout dekInfrastructure dekUnknown))"
proc generateStrategicHint*(kind: DiscoveryErrorKind; rawMessage: string): string {.raises: [].} =
  ## Convert a classified error into an actionable hint for the next round.
  case kind
  of dekSyntaxError:
    "Fix syntax: ensure all parentheses/brackets match, complete tactic blocks, and use valid Lean 4 syntax. Do not leave incomplete expressions."
  of dekTypeMismatch:
    if "is not a proposition" in rawMessage:
      "The theorem type must be a Prop (proposition), not a function type or data type. Wrap the assertion in a proper logical statement using ∀, ∃, or equality. Do not declare a theorem with a non-Prop type."
    elif "type mismatch" in rawMessage:
      "Type mismatch detected. Ensure all expressions have the expected types. Check function argument types and return types carefully."
    else:
      "Type error detected. Verify that the theorem statement and all tactics produce correct types."
  of dekUnknownConstant:
    if "module prefix" in rawMessage:
      "Do NOT use 'import Mathlib' or any external dependency. Use ONLY 'import Std'. The local Lean 4 toolchain does not have Mathlib installed."
    else:
      "Use only functions and constants available in the 'import Std' namespace. Do not reference undefined functions or constants. Check spelling and namespace prefixes."
  of dekUnsolvedGoals:
    "The proof is incomplete. Add more tactics to solve all remaining goals. Consider using 'simp', 'rw', 'exact', 'intro', or 'apply'."
  of dekNamespaceConflict:
    "Theorem name collision detected. Rename the generated theorem or use a namespace prefix to avoid conflicts with pre-existing declarations."
  of dekNoGoals:
    "A tactic was applied when no goals remained. Remove redundant tactics or restructure the proof so tactics match the remaining goals."
  of dekAgentBehavior:
    "DO NOT use tools, bash, webfetch, or grep. Output ONLY Lean 4 theorem source code inside a markdown code block."
  of dekTimeout:
    "The response timed out. Generate shorter, simpler proofs. Avoid deeply nested tactics."
  of dekInfrastructure:
    "Infrastructure error (network/filesystem). Retry with the same prompt."
  of dekUnknown:
    "Review the error message carefully and fix the corresponding issue in the Lean 4 source."

# ---------------------------------------------------------------------------
# Serialization
# ---------------------------------------------------------------------------

## To Json.
# @axiom-hint: lean="err_rawMessage.length ≥ 0 ∧ err_line ≥ -9223372036854775808 ∧ err_line ≤ 9223372036854775807 ∧ err_column ≥ -9223372036854775808 ∧ err_column ≤ 9223372036854775807 ∧ err_leanSource.length ≥ 0 ∧ err_timestamp.length ≥ 0 ∧ err_round ≥ -9223372036854775808 ∧ err_round ≤ 9223372036854775807 ∧ err_nodeId.length ≥ 0 ∧ err_strategy.length ≥ 0 ∧ err_strategicHint.length ≥ 0" smt="(assert (and (>= (str.len err_rawMessage) 0) (and (>= err_line -9223372036854775808) (<= err_line 9223372036854775807)) (and (>= err_column -9223372036854775808) (<= err_column 9223372036854775807)) (>= (str.len err_leanSource) 0) (>= (str.len err_timestamp) 0) (and (>= err_round -9223372036854775808) (<= err_round 9223372036854775807)) (>= (str.len err_nodeId) 0) (>= (str.len err_strategy) 0) (>= (str.len err_strategicHint) 0)))"
proc toJson*(err: DiscoveryError): JsonNode {.raises: [].} =
  try:
    %*{
      "kind": $err.kind,
      "rawMessage": err.rawMessage,
      "line": err.line,
      "column": err.column,
      "leanSource": err.leanSource,
      "timestamp": err.timestamp,
      "round": err.round,
      "nodeId": err.nodeId,
      "strategy": err.strategy,
      "strategicHint": err.strategicHint
    }
  except CatchableError:
    newJNull()

# ---------------------------------------------------------------------------
# Archiving
# ---------------------------------------------------------------------------

## Archive Discovery Error.
# @axiom-hint: lean="dir.length = 0 ∧ (dir ≥ 0) ∧ external_io_isolated" smt="(assert (and (= (str.len dir) 0) (>= dir 0) external_io_isolated))"
proc archiveDiscoveryError*(err: DiscoveryError; archiveDir: string = "") {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Persist a DiscoveryError (metadata JSON + Lean source) to the archive.
  var dir = archiveDir
  if dir.len == 0:
    try:
      dir = joinPath(getCurrentDir(), "logs", "archive", "leanstral_failures")
    except CatchableError:
      dir = "logs/archive/leanstral_failures"
  try:
    discard existsOrCreateDir(dir)
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)

  let ts = err.timestamp.replace(":", "-").replace("T", "_")
  let safeNodeId = err.nodeId.replace("::", "_").replace(".", "_").replace("/", "_")
  let baseName = ts & "_" & safeNodeId & "_r" & $err.round
  let metaPath = joinPath(dir, baseName & ".json")
  let sourcePath = joinPath(dir, baseName & ".lean")

  try:
    ## intentional-discard: legacy-approved (spec §4.1)
    discard writeFileOpt(metaPath, $toJson(err))
    if err.leanSource.len > 0:
      ## intentional-discard: legacy-approved (spec §4.1)
      discard writeFileOpt(sourcePath, err.leanSource)
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)

{.pop.}

