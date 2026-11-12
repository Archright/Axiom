import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

import std/json
import std/options
import std/os
import std/sequtils
import std/strutils
import std/times
import core/logic/lean_diagnostic
import core/spec/spec_generator_types
import core/spec/spec_generator_main
import core/utils/file_utils
import core/utils/io_utils
import core/json/json_utils
import core/results
import core/axiom_pragmas
import infrastructure/logging_facade
# axiomIoBoundary

func generateContextAwareTactic*(
  diagnostics: seq[LeanDiagnostic];
  goals: seq[string];
  complexity: LeanSpecComplexity = LeanSpecComplexity();
  usedTactics: seq[string] = @[]
): string {.raises: [].} =
  var hasUnsolvedGoals = false
  var hasUnknownTactic = false
  var hasTypeMismatch = false
  let hasGoals = goals.len > 0

  for diag in diagnostics:
    let kind = diagnosticKind(diag)
    case kind
    of "unsolved_goals":
      hasUnsolvedGoals = true
    of "missing_import_or_symbol":
      hasUnknownTactic = true
    of "type_mismatch":
      hasTypeMismatch = true
    else:
      discard

  let initial = buildInitialTacticStrategy(complexity)
  for candidate in initial:
    if candidate notin usedTactics:
      if hasUnsolvedGoals or hasGoals:
        return candidate

  if hasUnsolvedGoals:
    return "simpa [Invariant] using Nat.zero_le (Run steps amount initialBalance)"
  if hasUnknownTactic:
    return "simp [Run, Transition, Invariant]"
  if hasTypeMismatch:
    return "simp [Run, Transition, Invariant]"
  if hasGoals:
    return "simpa [Invariant] using Nat.zero_le (Run steps amount initialBalance)"
  "simpa [Invariant] using Nat.zero_le (Run steps amount initialBalance)"

# @axiom-hint: lean="baseSpec.length ≥ 0 ∧ theoremName.length ≥ 0 ∧ tactic.length ≥ 0" smt="(assert (and (>= (str.len baseSpec) 0) (>= (str.len theoremName) 0) (>= (str.len tactic) 0)))"
func theoremSource*(baseSpec: string; theoremName: string; tactic: string): string =
  baseSpec.strip() &
  "\n\nnamespace Axiom.Verification\n" &
  "theorem " & theoremName & " (steps amount initialBalance : Nat) :\n" &
  "    Invariant (Run steps amount initialBalance) := by\n" &
  "  " & tactic & "\n\n" &
  "variable (balance : Nat)\n" &
  "example : balance >= 0 := by\n" &
  "  exact Nat.zero_le balance\n" &
  "end Axiom.Verification\n"

# @axiom-hint: lean="corePath.length ≥ 0 ∧ external_io_isolated" smt="(assert (and (>= (str.len corePath) 0) external_io_isolated))"
# @axiom-hint: lean="ast_parse_failed_isolated" smt="(assert (and ast_parse_failed_isolated))"
proc collectCoreSources(corePath: string): seq[NimSourceUnit] {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## [impure: calls dirExists, walkDirRec, readFileOpt — file I/O]
  if not dirExists(corePath):
    return @[]
  let root = absolutePath(corePath)
  for filePath in walkDirRec(root):
    if not filePath.endsWith(".nim"):
      continue
    let rel = normalizePathSeparators(relativePath(filePath, getCurrentDir()))
    let readRes = readFileOpt(filePath)
    if readRes.isOk:
      result.add(NimSourceUnit(modulePath: rel, source: readRes.get))

# @axiom-hint: lean="baseSpec.length ≥ 0 ∧ corePath.length ≥ 0" smt="(assert (and (>= (str.len baseSpec) 0) (>= (str.len corePath) 0)))"
# @axiom-hint: lean="sources.length = 0" smt="(assert (and (= (str.len sources) 0)))"
proc appendGeneratedCoreSpec*(baseSpec: string; corePath: string): tuple[source: string; structureCount: int; enumCount: int; functionCount: int; untrustedFunctionCount: int; warnings: seq[string]] {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## [impure: calls collectCoreSources (file I/O), axiomEffect: IOEffect]
  let sources = collectCoreSources(corePath)
  if sources.len == 0:
    return (source: baseSpec, structureCount: 0, enumCount: 0, functionCount: 0, untrustedFunctionCount: 0, warnings: @[])
  let generated = generateLeanSpecFromSources(sources)
  (
    source: baseSpec.strip() & "\n\n" & generated.leanCode,
    structureCount: generated.structureCount,
    enumCount: generated.enumCount,
    functionCount: generated.functionCount,
    untrustedFunctionCount: generated.untrustedFunctionCount,
    warnings: generated.warnings
  )

# @axiom-hint: lean="source.length ≥ 0 ∧ external_io_isolated" smt="(assert (and (>= (str.len source) 0) external_io_isolated))"
# @axiom-hint: lean="external_io_isolated" smt="(assert (and external_io_isolated))"
proc writeGeneratedSpecArtifact*(source: string): string {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## [impure: calls existsOrCreateDir, writeFileSafe — file I/O]
  discard existsOrCreateDir("logs")
  let path = joinPath("logs", "generated_core_spec.lean")
  try:
    discard writeFileSafe(path, source)
    path
  except CatchableError:
    ""

# @axiom-hint: lean="raw.length ≥ 0" smt="(assert (and (>= (str.len raw) 0)))"
# @axiom-hint: lean="buf.length = 0 ∧ (raw ≥ 0)" smt="(assert (and (= (str.len buf) 0) (>= raw 0)))"
func normalizeVaultToken(raw: string): string =
  var buf = newStringOfCap(raw.len)
  for ch in raw:
    if ch.isAlphaNumeric or ch == '_' or ch == '-':
      buf.add(ch)
  if buf.len == 0:
    return "proof"
  buf

# @axiom-hint: lean="theoremName.length ≥ 0" smt="(assert (and (>= (str.len theoremName) 0)))"
# @axiom-hint: lean="ast_parse_failed_isolated" smt="(assert (and ast_parse_failed_isolated))"
proc loadWarmStartTactics*(theoremName: string; complexity: LeanSpecComplexity): seq[string] =
  ## [impure: calls fileExists, readJsonFile (parseJson — side effects)]
  let vaultDir = joinPath(".axiom", "vault")
  let key = normalizeVaultToken(theoremName) & "_" & normalizeVaultToken(complexity.fingerprint)
  let path = joinPath(vaultDir, key & ".json")
  if not fileExists(path):
    return @[]
  try:
    let node = readJsonFile(path).get()
    if node.kind == JObject and node.hasKey("tactics") and node["tactics"].kind == JArray:
      for entry in node["tactics"].elems:
        if entry.kind == JString:
          result.add(entry.getStr())
      return result.deduplicate()
    if node.kind == JObject and node.hasKey("finalTactic") and node["finalTactic"].kind == JString:
      return @[node["finalTactic"].getStr()]
  except CatchableError:
    discard  # best-effort  # axiom:best-effort(ioboundary catch)
  @[]

# @axiom-hint: lean="theoremName.length ≥ 0 ∧ attempts ≥ -9223372036854775808 ∧ attempts ≤ 9223372036854775807 ∧ tactics.size ≥ 0 ∧ (∀ (tacticsIdx : Fin tactics.size), (tactics.get tacticsIdx).length ≥ 0) ∧ goals.size ≥ 0 ∧ (∀ (goalsIdx : Fin goals.size), (goals.get goalsIdx).length ≥ 0)" smt="(assert (and (>= (str.len theoremName) 0) (and (>= attempts -9223372036854775808) (<= attempts 9223372036854775807)) (>= (seq.len tactics) 0) (forall ((tacticsIdx Int)) (=> (and (>= tacticsIdx 0) (< tacticsIdx (seq.len tactics))) (>= (str.len (seq.nth tactics tacticsIdx)) 0))) (>= (seq.len goals) 0) (forall ((goalsIdx Int)) (=> (and (>= goalsIdx 0) (< goalsIdx (seq.len goals))) (>= (str.len (seq.nth goals goalsIdx)) 0)))))"
# @axiom-hint: lean="ast_parse_failed_isolated" smt="(assert (and ast_parse_failed_isolated))"
proc saveProofVaultArtifact*(
  theoremName: string;
  complexity: LeanSpecComplexity;
  attempts: int;
  tactics: seq[string];
  goals: seq[string]
): string {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  ## [impure: calls existsOrCreateDir, file I/O — axiomEffect: IOEffect]
  let vaultDir = joinPath(".axiom", "vault")
  discard existsOrCreateDir(".axiom")
  discard existsOrCreateDir(vaultDir)
  let key = normalizeVaultToken(theoremName) & "_" & normalizeVaultToken(complexity.fingerprint)
  let path = joinPath(vaultDir, key & ".json")
  var shouldWrite = true
  if fileExists(path):
    try:
      let existing = readJsonFile(path).get()
      if existing.kind == JObject and existing.hasKey("attempts") and existing["attempts"].kind in {JInt, JFloat}:
        let existingAttempts = existing["attempts"].getInt()
        if existingAttempts < attempts:
          shouldWrite = false
        elif existingAttempts == attempts and existing.hasKey("tactics") and existing["tactics"].kind == JArray:
          let existingTacticCount = existing["tactics"].len
          if existingTacticCount <= tactics.len:
            shouldWrite = false
    except CatchableError:
      discard  # best-effort  # axiom:best-effort(ioboundary catch)
  if not shouldWrite:
    return path
  try:
    if not writePrettyJsonFile(path, %*{
      "theorem": theoremName,
      "fingerprint": complexity.fingerprint,
      "complexity": complexity.summary,
      "attempts": attempts,
      "tactics": tactics,
      "finalTactic": (if tactics.len > 0: tactics[^1] else: ""),
      "goals": goals,
      "updatedAt": now().format("yyyy-MM-dd'T'HH:mm:ss.fff'Z'")
    }):
      logError("lean_lsp_tactic", "Failed to write proof vault artifact to " & path)
    path
  except CatchableError:
    ""

# @axiom-hint: lean="source.length ≥ 0 ∧ tactic.length ≥ 0" smt="(assert (and (>= (str.len source) 0) (>= (str.len tactic) 0)))"
# @axiom-hint: lean="i ∧ (lines ≥ 0)" smt="(assert (and i (>= lines 0)))"
func lineOfTactic*(source: string; tactic: string): int =
  let lines = source.splitLines()
  for i, line in lines:
    if line.strip() == tactic:
      return i
{.pop.}
