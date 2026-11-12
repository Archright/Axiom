import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
import std/sequtils
import std/strutils
import core/crypto/hash_kernel
import core/utils/text_utils
import core/types/domain_types
export domain_types.LeanDiagnostic
export domain_types.LeanFeedback
export domain_types.LeanLiveDiagnosticFeedback
export domain_types.LeanSpecComplexity

const
  hintInvariantStrengthening* = "Invariant strengthening suggestion: Specify Invariant balance -> Invariant (Transition amount balance) lemma as Nim invariant"
  hintPreConditionGuard* = "Pre-condition suggestion: Promote amount <= balance guard condition as explicit premise of Nim transition"
  hintLowerBoundInvariant* = "Invariant suggestion: Fix lower bound invariant that state value >= 0 in Nim rule"
  hintTypeMismatchSync* = "Pre-condition suggestion: Synchronize function argument type/range with Nim signature and gateway validation"

## Ha Errors.
# @axiom-hint: lean="diagnostics.size ≥ 0" smt="(assert (and (>= (seq.len diagnostics) 0)))"
# @axiom-hint: lean="ast_parse_failed_isolated" smt="(assert ast_parse_failed_isolated)"
func hasErrors*(diagnostics: seq[LeanDiagnostic]): bool =
  for d in diagnostics:
    if d.severity <= 1:
      return true
  false

## Ha Warnings.
# @axiom-hint: lean="diags.size ≥ 0" smt="(assert (and (>= (seq.len diags) 0)))"
# @axiom-hint: lean="true ∧ (diags ≥ 0)" smt="(assert (and true (>= diags 0)))"
func hasWarnings*(diags: seq[LeanDiagnostic]): bool {.raises: [], noSideEffect.} =
  for d in diags:
    if d.severity == 2:
      return true
  false

## I Near Line.
# @axiom-hint: lean="diag_line ≥ -9223372036854775808 ∧ diag_line ≤ 9223372036854775807 ∧ diag_character ≥ -9223372036854775808 ∧ diag_character ≤ 9223372036854775807 ∧ diag_severity ≥ -9223372036854775808 ∧ diag_severity ≤ 9223372036854775807 ∧ diag_message.length ≥ 0 ∧ diag_code.length ≥ 0 ∧ diag_kind.length ≥ 0 ∧ targetLine ≥ -9223372036854775808 ∧ targetLine ≤ 9223372036854775807 ∧ window ≥ -9223372036854775808 ∧ window ≤ 9223372036854775807" smt="(assert (and (and (>= diag_line -9223372036854775808) (<= diag_line 9223372036854775807)) (and (>= diag_character -9223372036854775808) (<= diag_character 9223372036854775807)) (and (>= diag_severity -9223372036854775808) (<= diag_severity 9223372036854775807)) (>= (str.len diag_message) 0) (>= (str.len diag_code) 0) (>= (str.len diag_kind) 0) (and (>= targetLine -9223372036854775808) (<= targetLine 9223372036854775807)) (and (>= window -9223372036854775808) (<= window 9223372036854775807))))"
func isNearLine*(diag: LeanDiagnostic; targetLine: int; window: int): bool {.raises: [], noSideEffect.} =
  let effectiveWindow = max(window, 0)
  abs(diag.line - targetLine) <= effectiveWindow

## Diagnostic Kind.
# @axiom-hint: lean="message.length ≥ 0" smt="(assert (and (>= (str.len message) 0)))"
func diagnosticKind*(message: string): string {.raises: [], noSideEffect.} =
  let tokens = tokenizeLowered(message)
  for i in 0 ..< tokens.len:
    if tokens[i] == "tactic" and i + 1 < tokens.len and tokens[i + 1] == "failed":
      return "tactic_failed"
    if tokens[i] == "type" and i + 1 < tokens.len and tokens[i + 1] == "mismatch":
      return "type_mismatch"
    if tokens[i] == "application" and i + 1 < tokens.len and tokens[i + 1] == "type" and i + 2 < tokens.len and tokens[i + 2] == "mismatch":
      return "type_mismatch"
    if tokens[i] == "unsolved" and i + 1 < tokens.len and tokens[i + 1] == "goals":
      return "unsolved_goals"
    if tokens[i] == "unknown" and i + 1 < tokens.len and tokens[i + 1] == "constant":
      return "missing_import_or_symbol"
    if tokens[i] == "unknown" and i + 1 < tokens.len and tokens[i + 1] == "identifier":
      return "missing_import_or_symbol"
    if tokens[i] == "synthesized" and i + 1 < tokens.len and tokens[i + 1] == "type" and i + 2 < tokens.len and tokens[i + 2] == "class":
      return "missing_instance"
    if tokens[i] == "failed" and i + 1 < tokens.len and tokens[i + 1] == "to" and i + 2 < tokens.len and tokens[i + 2] == "synthesize":
      return "missing_instance"
    if tokens[i] == "invalid" and i + 1 < tokens.len and tokens[i + 1] == "field":
      return "invalid_projection"
    if tokens[i] == "invalid" and i + 1 < tokens.len and tokens[i + 1] == "constructor":
      return "invalid_projection"
    if tokens[i] == "unexpected" and i + 1 < tokens.len and tokens[i + 1] == "token":
      return "syntax_error"
    if tokens[i] == "parse" and i + 1 < tokens.len and tokens[i + 1] == "error":
      return "syntax_error"
  "general_constraint"

## Diagnostic Kind.
func diagnosticKind*(diag: LeanDiagnostic): string {.raises: [], noSideEffect.} =
  if diag.kind.len > 0:
    return diag.kind
  diagnosticKind(diag.message)

## Diagnostic Hint.
# @axiom-hint: lean="kind.length ≥ 0" smt="(assert (and (>= (str.len kind) 0)))"
func diagnosticHint*(kind: string): string {.raises: [], noSideEffect.} =
  case kind
  of "tactic_failed":
    "Current tactic cannot close the goal. Try stronger decomposition with cases, refine, simp sequence or lemma call."
  of "type_mismatch":
    "Type mismatch between expected and actual expression in theorem body. Try equality substitution or function argument normalization first."
  of "unsolved_goals":
    "Core premise still remains in goal. Try intro, have, exact, or subst to consume remaining assumptions."
  of "missing_import_or_symbol":
    "Name resolution failed. Check lemma import path or qualified identifier name."
  of "missing_instance":
    "Insufficient automatic inference instance. Try explicit type annotation or simpler deterministic tactic."
  of "invalid_projection":
    "Struct field or constructor projection does not match current state type. Try match or cases decomposition first."
  of "syntax_error":
    "Lean syntax is broken. Try reconstructing tactic newlines and indentation or theorem/example header."
  else:
    "Lean kernel cannot accept current proof path. Try simpler rewrite or lemma-centric tactic."

## First Goal Summary.
# @axiom-hint: lean="goals.size ≥ 0 ∧ ∀ (i : Fin goals.size), (goals.get i).length ≥ 0" smt="(assert (and (>= (seq.len goals) 0) (forall ((i Int)) (=> (and (>= i 0) (< i (seq.len goals))) (>= (str.len (seq.nth goals i)) 0)))))"
# @axiom-hint: lean="goals.size ≥ 0 ∧ (∀ (goalsIdx : Fin goals.size), (goals.get goalsIdx).length ≥ 0)" smt="(assert (and (>= (seq.len goals) 0) (forall ((goalsIdx Int)) (=> (and (>= goalsIdx 0) (< goalsIdx (seq.len goals))) (>= (str.len (seq.nth goals goalsIdx)) 0)))))"
# @axiom-hint: lean="normalized.length > 0 ∧ normalized ∧ normalized.length > 0 → result = normalized ∧ (goals ≥ 0) ∧ (∀ (goalsIdx : Fin goals.size), (goals.get goalsIdx).length ≥ 0)" smt="(assert (and (> (str.len normalized) 0) normalized (=> (> (str.len normalized) 0) (= result normalized)) (>= goals 0) (forall ((goalsIdx Int)) (=> (and (>= goalsIdx 0) (< goalsIdx (seq.len goals))) (>= (str.len (seq.nth goals goalsIdx)) 0)))))"
func firstGoalSummary*(goals: seq[string]): string {.raises: [], noSideEffect.} =
  for goal in goals:
    let normalized = goal.strip()
    if normalized.len > 0:
      return normalized
  ""

## Build Diagnostic Summary.
# @axiom-hint: lean="diagnostics.size ≥ 0 ∧ goals.size ≥ 0 ∧ ∀ (i : Fin goals.size), (goals.get i).length ≥ 0 ∧ targetLine ≥ -9223372036854775808 ∧ targetLine ≤ 9223372036854775807" smt="(assert (and (>= (seq.len diagnostics) 0) (>= (seq.len goals) 0) (forall ((i Int)) (=> (and (>= i 0) (< i (seq.len goals))) (>= (str.len (seq.nth goals i)) 0))) (and (>= targetLine -9223372036854775808) (<= targetLine 9223372036854775807))))"
# @axiom-hint: lean="diagnostics.size ≥ 0 ∧ goals.size ≥ 0 ∧ (∀ (goalsIdx : Fin goals.size), (goals.get goalsIdx).length ≥ 0) ∧ targetLine ≥ -9223372036854775808 ∧ targetLine ≤ 9223372036854775807" smt="(assert (and (>= (seq.len diagnostics) 0) (>= (seq.len goals) 0) (forall ((goalsIdx Int)) (=> (and (>= goalsIdx 0) (< goalsIdx (seq.len goals))) (>= (str.len (seq.nth goals goalsIdx)) 0))) (and (>= targetLine -9223372036854775808) (<= targetLine 9223372036854775807))))"
# @axiom-hint: lean="diagnostics.length > 0 ∧ goalSummary.length > 0 ∧ hints.length = 0 ∧ (∀ (goalsIdx : Fin goals.size), (goals.get goalsIdx).length ≥ 0)" smt="(assert (and (> (str.len diagnostics) 0) (> (str.len goalSummary) 0) (= (str.len hints) 0) (forall ((goalsIdx Int)) (=> (and (>= goalsIdx 0) (< goalsIdx (seq.len goals))) (>= (str.len (seq.nth goals goalsIdx)) 0)))))"
func buildDiagnosticSummary*(
  diagnostics: seq[LeanDiagnostic];
  goals: seq[string];
  targetLine: int
): tuple[kind: string; summary: string; hints: seq[string]] {.raises: [], noSideEffect.} =
  let relevant =
    if diagnostics.len > 0: diagnostics
    else: @[
      LeanDiagnostic(
        line: targetLine,
        character: 0,
        severity: 1,
        message: "lean feedback unavailable"
      )
    ]
  let primary = relevant[0]
  let kind = diagnosticKind(primary)
  let severityLabel =
    if primary.severity <= 1: "error"
    elif primary.severity == 2: "warning"
    else: "info"
  var summary = severityLabel & " @" & $(primary.line + 1) & ":" & $(primary.character + 1) & " - " &
    diagnosticHint(kind)
  if primary.message.strip().len > 0:
    summary.add(" original: " & primary.message.strip())
  let goalSummary = firstGoalSummary(goals)
  if goalSummary.len > 0:
    summary.add(" goal: " & goalSummary)
  var hints = relevant.mapIt(diagnosticHint(diagnosticKind(it))).deduplicate()
  if hints.len == 0:
    hints.add(diagnosticHint(kind))
  (kind: kind, summary: summary, hints: hints)

## Get Live Diagnostic Feedback.
# @axiom-hint: lean="feedback_diagnostics.size ≥ 0 ∧ feedback_goals.size ≥ 0 ∧ feedback_events.size ≥ 0 ∧ line ≥ -9223372036854775808 ∧ line ≤ 9223372036854775807 ∧ window ≥ -9223372036854775808 ∧ window ≤ 9223372036854775807" smt="(assert (and (>= (seq.len feedback_diagnostics) 0) (>= (seq.len feedback_goals) 0) (>= (seq.len feedback_events) 0) (and (>= line -9223372036854775808) (<= line 9223372036854775807)) (and (>= window -9223372036854775808) (<= window 9223372036854775807))))"
# @axiom-hint: lean="filtered.length = 0 ∧ (filtered ≥ 0)" smt="(assert (and (= (str.len filtered) 0) (>= filtered 0)))"
func getLiveDiagnosticFeedback*(
  feedback: LeanFeedback;
  line: int;
  window: int = 2
): LeanLiveDiagnosticFeedback {.raises: [], noSideEffect.} =
  var filtered: seq[LeanDiagnostic] = @[]
  for diag in feedback.diagnostics:
    if isNearLine(diag, line, window):
      filtered.add(diag)
  if filtered.len == 0:
    filtered = feedback.diagnostics
  let summary = buildDiagnosticSummary(filtered, feedback.goals, line)
  LeanLiveDiagnosticFeedback(
    line: line,
    hasErrors: hasErrors(filtered),
    hasWarnings: hasWarnings(filtered),
    dominantKind: summary.kind,
    summary: summary.summary,
    diagnostics: filtered,
    goals: feedback.goals,
    actionableHints: summary.hints
  )

## Compute Proof Attempt Timeout Ms.
# @axiom-hint: lean="complexity_hasRecursiveDefs = true ∨ complexity_hasRecursiveDefs = false ∧ complexity_needsInduction = true ∨ complexity_needsInduction = false ∧ complexity_needsCases = true ∨ complexity_needsCases = false ∧ complexity_hasPatternMatching = true ∨ complexity_hasPatternMatching = false ∧ complexity_fingerprint.length ≥ 0 ∧ complexity_summary.length ≥ 0 ∧ attempt ≥ -9223372036854775808 ∧ attempt ≤ 9223372036854775807" smt="(assert (and (or (= complexity_hasRecursiveDefs true) (= complexity_hasRecursiveDefs false)) (or (= complexity_needsInduction true) (= complexity_needsInduction false)) (or (= complexity_needsCases true) (= complexity_needsCases false)) (or (= complexity_hasPatternMatching true) (= complexity_hasPatternMatching false)) (>= (str.len complexity_fingerprint) 0) (>= (str.len complexity_summary) 0) (and (>= attempt -9223372036854775808) (<= attempt 9223372036854775807))))"
# @axiom-hint: lean="attempt > 1 ∧ (timeoutMs ≥ 0) ∧ complexity_hasRecursiveDefs = true ∨ complexity_hasRecursiveDefs = false ∧ complexity_needsInduction = true ∨ complexity_needsInduction = false ∧ complexity_needsCases = true ∨ complexity_needsCases = false ∧ complexity_hasPatternMatching = true ∨ complexity_hasPatternMatching = false" smt="(assert (and (> attempt 1) (>= timeoutMs 0) (or (= complexity_hasRecursiveDefs true) (= complexity_hasRecursiveDefs false)) (or (= complexity_needsInduction true) (= complexity_needsInduction false)) (or (= complexity_needsCases true) (= complexity_needsCases false)) (or (= complexity_hasPatternMatching true) (= complexity_hasPatternMatching false))))"
func computeProofAttemptTimeoutMs*(complexity: LeanSpecComplexity; attempt: int): int =
  var timeoutMs = 60_000
  if complexity.needsInduction or complexity.hasRecursiveDefs:
    timeoutMs = max(timeoutMs, 180_000)
  if complexity.needsCases or complexity.hasPatternMatching:
    timeoutMs = max(timeoutMs, 150_000)
  if attempt > 1:
    timeoutMs += (attempt - 1) * 15_000
  timeoutMs
## Analyze Spec Complexity.
# @axiom-hint: lean="generatedSpecSource.length ≥ 0" smt="(assert (and (>= (str.len generatedSpecSource) 0)))"
# @axiom-hint: lean="complexity ∧ (complexity ≥ 0)" smt="(assert (and complexity (>= complexity 0)))"
proc analyzeSpecComplexity*(generatedSpecSource: string): LeanSpecComplexity =
  ## String-keyword analysis of Lean spec complexity.
  ## Detects recursive definitions, induction needs, case splitting, and pattern matching
  ## via lexical scanning — no external parser required.
  var complexity: LeanSpecComplexity
  let srcLower = generatedSpecSource.toLowerAscii()
  complexity.hasRecursiveDefs = "recursive" in srcLower or "rec" in srcLower
  complexity.needsInduction = "induction" in srcLower
  complexity.needsCases = "cases" in srcLower or "match" in srcLower
  complexity.hasPatternMatching = "match" in srcLower or ":=" in srcLower
  let raw = sha256Hex(
    generatedSpecSource.toLowerAscii() & "|" &
    $complexity.hasRecursiveDefs & "|" &
    $complexity.needsInduction & "|" &
    $complexity.needsCases & "|" &
    $complexity.hasPatternMatching
  )
  let fingerprint = raw
  complexity.fingerprint = fingerprint
  complexity.summary = (
    "recursive=" & $complexity.hasRecursiveDefs &
    ", induction=" & $complexity.needsInduction &
    ", cases=" & $complexity.needsCases &
    ", pattern=" & $complexity.hasPatternMatching
  )
  return complexity

## Build Initial Tactic Strategy.
# @axiom-hint: lean="complexity_hasRecursiveDefs = true ∨ complexity_hasRecursiveDefs = false ∧ complexity_needsInduction = true ∨ complexity_needsInduction = false ∧ complexity_needsCases = true ∨ complexity_needsCases = false ∧ complexity_hasPatternMatching = true ∨ complexity_hasPatternMatching = false ∧ complexity_fingerprint.length ≥ 0 ∧ complexity_summary.length ≥ 0" smt="(assert (and (or (= complexity_hasRecursiveDefs true) (= complexity_hasRecursiveDefs false)) (or (= complexity_needsInduction true) (= complexity_needsInduction false)) (or (= complexity_needsCases true) (= complexity_needsCases false)) (or (= complexity_hasPatternMatching true) (= complexity_hasPatternMatching false)) (>= (str.len complexity_fingerprint) 0) (>= (str.len complexity_summary) 0)))"
# @axiom-hint: lean="complexity_hasRecursiveDefs = true ∨ complexity_hasRecursiveDefs = false ∧ complexity_needsInduction = true ∨ complexity_needsInduction = false ∧ complexity_needsCases = true ∨ complexity_needsCases = false ∧ complexity_hasPatternMatching = true ∨ complexity_hasPatternMatching = false" smt="(assert (and (or (= complexity_hasRecursiveDefs true) (= complexity_hasRecursiveDefs false)) (or (= complexity_needsInduction true) (= complexity_needsInduction false)) (or (= complexity_needsCases true) (= complexity_needsCases false)) (or (= complexity_hasPatternMatching true) (= complexity_hasPatternMatching false))))"
func buildInitialTacticStrategy*(complexity: LeanSpecComplexity): seq[string] =
  if complexity.needsInduction:
    result.add(
      "induction steps generalizing initialBalance with\n" &
      "  | zero =>\n" &
      "      simp [Run, Invariant]\n" &
      "  | succ k ih =>\n" &
      "      simp [Run]\n" &
      "      exact ih (Transition amount initialBalance)"
    )
  if complexity.needsCases:
    result.add("first | cases h : amount ≤ balance <;> simp [Transition, Run, Invariant] at * | simp [Run, Invariant]")
  if complexity.hasPatternMatching:
    result.add("simp [Run, Transition, Invariant]")
  result.add("simpa [Invariant] using Nat.zero_le (Run steps amount initialBalance)")

## Infer Missing Hypotheses.
# @axiom-hint: lean="diagnostics.size ≥ 0 ∧ goals.size ≥ 0 ∧ ∀ (i : Fin goals.size), (goals.get i).length ≥ 0" smt="(assert (and (>= (seq.len diagnostics) 0) (>= (seq.len goals) 0) (forall ((i Int)) (=> (and (>= i 0) (< i (seq.len goals))) (>= (str.len (seq.nth goals i)) 0)))))"
# @axiom-hint: lean="diagnostics.size ≥ 0 ∧ goals.size ≥ 0 ∧ (∀ (goalsIdx : Fin goals.size), (goals.get goalsIdx).length ≥ 0)" smt="(assert (and (>= (seq.len diagnostics) 0) (>= (seq.len goals) 0) (forall ((goalsIdx Int)) (=> (and (>= goalsIdx 0) (< goalsIdx (seq.len goals))) (>= (str.len (seq.nth goals goalsIdx)) 0)))))"
# @axiom-hint: lean="hasInvariant ∧ hasRunOrTransition ∧ hasAmount ∧ hasBalance ∧ hasLe ∧ hasGe ∨ hasZeroLe ∧ hasTypeMismatch ∧ hasTypeMismatch = true ∧ hasInvariant = true ∧ hasRunOrTransition = true ∧ hasAmount = true ∧ hasBalance = true ∧ hasLe = true ∧ hasGe = true ∧ hasZeroLe = true ∧ (hasTypeMismatch ≥ 0) ∧ (hasGe ≥ 0) ∧ (hasAmount ≥ 0) ∧ (hasBalance ≥ 0) ∧ (hasInvariant ≥ 0) ∧ (hasLe ≥ 0) ∧ (result ≥ 0) ∧ (tokens ≥ 0) ∧ (hasRunOrTransition ≥ 0) ∧ (diagnostics ≥ 0) ∧ (goals ≥ 0) ∧ (hasZeroLe ≥ 0) ∧ (∀ (goalsIdx : Fin goals.size), (goals.get goalsIdx).length ≥ 0)" smt="(assert (and (and hasInvariant hasRunOrTransition) (and (and hasAmount hasBalance) hasLe) (or hasGe hasZeroLe) hasTypeMismatch (= hasTypeMismatch true) (= hasInvariant true) (= hasRunOrTransition true) (= hasAmount true) (= hasBalance true) (= hasLe true) (= hasGe true) (= hasZeroLe true) (>= hasTypeMismatch 0) (>= hasGe 0) (>= hasAmount 0) (>= hasBalance 0) (>= hasInvariant 0) (>= hasLe 0) (>= result 0) (>= tokens 0) (>= hasRunOrTransition 0) (>= diagnostics 0) (>= goals 0) (>= hasZeroLe 0) (forall ((goalsIdx Int)) (=> (and (>= goalsIdx 0) (< goalsIdx (seq.len goals))) (>= (str.len (seq.nth goals goalsIdx)) 0)))))"
func inferMissingHypotheses*(diagnostics: seq[LeanDiagnostic]; goals: seq[string]): seq[string] =
  var hasTypeMismatch = false
  for diag in diagnostics:
    if diagnosticKind(diag) == "type_mismatch":
      hasTypeMismatch = true

  for goal in goals:
    let tokens = tokenizeLowered(goal)
    var hasInvariant = false
    var hasRunOrTransition = false
    var hasAmount = false
    var hasBalance = false
    var hasLe = false
    var hasGe = false
    var hasZeroLe = false
    for tok in tokens:
      case tok
      of "invariant": hasInvariant = true
      of "run", "transition": hasRunOrTransition = true
      of "amount": hasAmount = true
      of "balance": hasBalance = true
      of "<=": hasLe = true
      of ">=": hasGe = true
      of "zero_le": hasZeroLe = true
      else: discard
    let goalLower = goal.toLowerAscii()
    if goalLower.find("≤") >= 0:
      hasLe = true
    if goalLower.find("≥") >= 0:
      hasGe = true
    if hasInvariant and hasRunOrTransition:
      result.add(hintInvariantStrengthening)
    if hasAmount and hasBalance and hasLe:
      result.add(hintPreConditionGuard)
    if hasGe or hasZeroLe:
      result.add(hintLowerBoundInvariant)

  if hasTypeMismatch:
    result.add("Pre-condition suggestion: Synchronize function argument type/range with Nim signature and gateway validation")

  result = result.deduplicate()


{.pop.}
