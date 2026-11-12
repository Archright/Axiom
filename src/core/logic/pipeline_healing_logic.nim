import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
import ../../core/trusted/axiom_pragmas
import core/logic/lean_diagnostic
import core/logic/universal_translation_types
import core/utils/text_utils
import std/sequtils
import std/strutils
## Extract Goal Lines From Compiler Output.
## Extract Goal Lines From Compiler Output.
## axiom-smt: (assert (and (>= (str.len output) 0) (>= result 0)))
## axiom-lean: output.length ≥ 0 ∧ (result ≥ 0)
func extractGoalLinesFromCompilerOutput*(output: string): seq[string] {.axiomTryImpl.} =
  for raw in output.splitLines():
    let line = raw.strip()
    let tokens = tokenizeLowered(line)
    if line.find("⊢") >= 0:
      result.add(line)
    elif "unsolved" in tokens and "goals" in tokens:
      result.add(line)
    elif "goal" in tokens or "goals" in tokens:
      result.add(line)
    elif line.find("≤") >= 0:
      result.add(line)
    elif "<=" in tokens:
      result.add(line)
  result = result.deduplicate()
func appendInvariantConjunct(
  invariant: string;
  conjunct: string
): string {.axiomTryImpl.} =
  ## axiom-smt: (assert (and (>= (str.len invariant) 0) (>= (str.len conjunct) 0) (= (str.len normalizedConjunct) 0) (= (str.len normalizedInvariant) 0) normalizedConjunct normalizedInvariant (=> (= (str.len normalizedInvariant) 0) (= result normalizedConjunct))))
  ## axiom-lean: invariant.length ≥ 0 ∧ conjunct.length ≥ 0 ∧ normalizedConjunct.length = 0 ∧ normalizedInvariant.length = 0 ∧ normalizedConjunct ∧ normalizedInvariant ∧ normalizedInvariant.length = 0 → result = normalizedConjunct
  # AxiomGuard:1118518425101503 (invinvLoop)
  discard ## Merge Invariant Clauses.  # Axiom-IR loop condition
  # EndAxiomGuard
  let normalizedConjunct = conjunct.strip()
  if normalizedConjunct.len == 0:
    return invariant.strip()
  let normalizedInvariant = invariant.strip()
  if normalizedInvariant.len == 0:
    return normalizedConjunct
  for existing in normalizedInvariant.split("∧"):
    if existing.strip() == normalizedConjunct:
      return normalizedInvariant
  normalizedInvariant & " ∧ " & normalizedConjunct

## Merge Invariant Clauses.
func mergeInvariantClauses*(
  baseInvariant: string;
  extraInvariant: string
): string {.axiomTryImpl.} =
  ## axiom-smt: (assert (and (>= (str.len baseInvariant) 0) (>= (str.len extraInvariant) 0) (= (str.len normalizedExtra) 0) result (=> (= (str.len normalizedExtra) 0) (= result result)) (>= result 0)))
  ## axiom-lean: baseInvariant.length ≥ 0 ∧ extraInvariant.length ≥ 0 ∧ normalizedExtra.length = 0 ∧ result ∧ normalizedExtra.length = 0 → result = result ∧ (result ≥ 0)
  result = baseInvariant.strip()
  let normalizedExtra = extraInvariant.strip()
  if normalizedExtra.len == 0:
    return result
  for conjunct in normalizedExtra.split("∧"):
    result = appendInvariantConjunct(result, conjunct)

## Strengthen Invariant From Lean Hints.
func strengthenInvariantFromLeanHints*(
  invariant: string;
  translation: UniversalTranslation;
  hints: seq[string]
): string {.axiomTryImpl.} =
  ## axiom-smt: (assert (and (>= (str.len invariant) 0) (>= (seq.len hints) 0) (forall ((hintsIdx Int)) (=> (and (>= hintsIdx 0) (< hintsIdx (seq.len hints))) (>= (str.len (seq.nth hints hintsIdx)) 0))) hasAmountBalance hasGeZero hasTransitionBalance (= hasAmountBalance true) (= hasGeZero true) (= hasTransitionBalance true) (>= hasAmountBalance 0) (>= hints 0) (>= result 0) (>= tokens 0) (>= hasGeZero 0) (>= hasTransitionBalance 0) (forall ((hintsIdx Int)) (=> (and (>= hintsIdx 0) (< hintsIdx (seq.len hints))) (>= (str.len (seq.nth hints hintsIdx)) 0)))))
  ## axiom-lean: invariant.length ≥ 0 ∧ hints.size ≥ 0 ∧ (∀ (hintsIdx : Fin hints.size), (hints.get hintsIdx).length ≥ 0) ∧ hasAmountBalance ∧ hasGeZero ∧ hasTransitionBalance ∧ hasAmountBalance = true ∧ hasGeZero = true ∧ hasTransitionBalance = true ∧ (hasAmountBalance ≥ 0) ∧ (hints ≥ 0) ∧ (result ≥ 0) ∧ (tokens ≥ 0) ∧ (hasGeZero ≥ 0) ∧ (hasTransitionBalance ≥ 0) ∧ (∀ (hintsIdx : Fin hints.size), (hints.get hintsIdx).length ≥ 0)
  result = invariant.strip()
  for hint in hints:
    let tokens = tokenizeLowered(hint)
    var hasAmountBalance = false
    var hasGeZero = false
    var hasTransitionBalance = false
    for tok in tokens:
      case tok
      of "amount", "balance":
        if "<=" in tokens:
          hasAmountBalance = true
      of "always", "ge", "zero", "zero_le":
        hasGeZero = true
      of "transition", "invariant":
        hasTransitionBalance = true
      else:
        discard
    let hintLower = hint.toLowerAscii()
    if hintLower.find(">=") >= 0 or hintLower.find("≥") >= 0:
      hasGeZero = true
    if hasAmountBalance:
      result = appendInvariantConjunct(result, "amount <= state.balance")
    if hasGeZero:
      result = appendInvariantConjunct(result, "0 <= state.balance")
    if hasTransitionBalance:
      for transitionInvariant in translation.transitionInvariants:
        let invTokens = tokenizeLowered(transitionInvariant)
        if "next" in invTokens and "balance" in invTokens and "<=" in invTokens:
          result = appendInvariantConjunct(result, "next.balance <= state.balance")
          break

## Build Lean Hint Assertions.
## axiom-smt: (assert (and (>= (str.len source) 0) (>= (seq.len hints) 0) (forall ((i Int)) (=> (and (>= i 0) (< i (seq.len hints))) (>= (str.len (seq.nth hints i)) 0))) (>= (str.len source) 0) (>= (seq.len hints) 0) (forall ((hintsIdx Int)) (=> (and (>= hintsIdx 0) (< hintsIdx (seq.len hints))) (>= (str.len (seq.nth hints hintsIdx)) 0))) (= hasAmountBalance true) (= hasGeZero true) (>= hasAmountBalance 0) (>= hints 0) (>= tokens 0) (>= hasGeZero 0) (forall ((hintsIdx Int)) (=> (and (>= hintsIdx 0) (< hintsIdx (seq.len hints))) (>= (str.len (seq.nth hints hintsIdx)) 0)))))
## axiom-lean: source.length ≥ 0 ∧ hints.size ≥ 0 ∧ ∀ (i : Fin hints.size), (hints.get i).length ≥ 0 ∧ source.length ≥ 0 ∧ hints.size ≥ 0 ∧ (∀ (hintsIdx : Fin hints.size), (hints.get hintsIdx).length ≥ 0) ∧ hasAmountBalance = true ∧ hasGeZero = true ∧ (hasAmountBalance ≥ 0) ∧ (hints ≥ 0) ∧ (tokens ≥ 0) ∧ (hasGeZero ≥ 0) ∧ (∀ (hintsIdx : Fin hints.size), (hints.get hintsIdx).length ≥ 0)
func buildLeanHintAssertions*(source: string; hints: seq[string]): seq[string] {.axiomTryImpl.} =
  let sourceTokens = tokenizeLowered(source)
  let sourceHasAmountGuard = "doassert" in sourceTokens and "amount" in sourceTokens and "<=" in sourceTokens
  let sourceHasBalanceGuard = "doassert" in sourceTokens and "balance" in sourceTokens and ">=" in sourceTokens
  for hint in hints:
    let tokens = tokenizeLowered(hint)
    var hasAmountBalance = false
    var hasGeZero = false
    for tok in tokens:
      case tok
      of "amount", "balance":
        if "<=" in tokens:
          hasAmountBalance = true
      of "always", "ge", "zero", "zero_le":
        hasGeZero = true
      else:
        discard
    let hintLower = hint.toLowerAscii()
    if hintLower.find(">=") >= 0 or hintLower.find("≥") >= 0:
      hasGeZero = true
    if hasAmountBalance and not sourceHasAmountGuard:
      result.add("doAssert amount <= balance")
    if hasGeZero and not sourceHasBalanceGuard:
      result.add("doAssert balance >= 0")

## Synthesize Lean Fallback Hints.
func synthesizeLeanFallbackHints*(
  source: string;
  invariant: string;
  compilerOutput: string
): seq[string] {.axiomTryImpl.} =
  ## axiom-smt: (assert (and (>= (str.len source) 0) (>= (str.len invariant) 0) (>= (str.len compilerOutput) 0) (or invHasTransition outHasTransition) (= hasUnsolvedGoals true) (= outHasTransition true) (>= outHasTransition 0) (>= result 0) (>= hasUnsolvedGoals 0)))
  ## axiom-lean: source.length ≥ 0 ∧ invariant.length ≥ 0 ∧ compilerOutput.length ≥ 0 ∧ invHasTransition ∨ outHasTransition ∧ hasUnsolvedGoals = true ∧ outHasTransition = true ∧ (outHasTransition ≥ 0) ∧ (result ≥ 0) ∧ (hasUnsolvedGoals ≥ 0)
  let sourceTokens = tokenizeLowered(source)
  let invTokens = tokenizeLowered(invariant)
  let outTokens = tokenizeLowered(compilerOutput)
  var hasUnsolvedGoals = false
  if "unsolved" in outTokens and "goals" in outTokens:
    hasUnsolvedGoals = true
  if not hasUnsolvedGoals:
    return @[]
  let sourceHasAmountGuard = "doassert" in sourceTokens and "amount" in sourceTokens and "<=" in sourceTokens
  let sourceHasBalanceGuard = "doassert" in sourceTokens and "balance" in sourceTokens and ">=" in sourceTokens
  let invHasAmountBalance = "amount" in invTokens and "balance" in invTokens and "<=" in invTokens
  let outHasAmountBalance = "amount" in outTokens and "balance" in outTokens and "<=" in outTokens
  let invHasBalanceGeZero = "balance" in invTokens and (">=" in invTokens or "zero_le" in invTokens)
  let outLower = compilerOutput.toLowerAscii()
  let outHasBalanceGeZero = "balance" in outTokens and (">=" in outTokens or "zero_le" in outTokens or outLower.find("≥") >= 0)
  let invHasTransition = "next" in invTokens and "balance" in invTokens and "<=" in invTokens
  var outHasTransition = "transition" in outTokens and "amount" in outTokens and "balance" in outTokens
  if outLower.find("⊢ invariant (transition") >= 0:
    outHasTransition = true
  if (invHasAmountBalance or outHasAmountBalance) and not sourceHasAmountGuard:
    result.add(hintPreConditionGuard)
  if (invHasBalanceGeZero or outHasBalanceGeZero) and not sourceHasBalanceGuard:
    result.add(hintLowerBoundInvariant)
  if invHasTransition or outHasTransition:
    result.add(hintInvariantStrengthening)
  result = result.deduplicate()

## Inject Nim Assertions.
func injectNimAssertions*(
  source: string;
  assertions: seq[string]
): tuple[updated: string; changed: bool] {.axiomTryImpl.} =
  ## axiom-smt: (assert (and (>= (str.len source) 0) (>= (seq.len assertions) 0) (forall ((i Int)) (=> (and (>= i 0) (< i (seq.len assertions))) (>= (str.len (seq.nth assertions i)) 0))) (>= (str.len source) 0) (>= (seq.len assertions) 0) (forall ((assertionsIdx Int)) (=> (and (>= assertionsIdx 0) (< assertionsIdx (seq.len assertions))) (>= (str.len (seq.nth assertions assertionsIdx)) 0))) (= (str.len assertions) 0) (= (str.len lines) 0) inserted (= inserted true) (>= lines 0) (>= inserted 0) (>= assertions 0) (forall ((assertionsIdx Int)) (=> (and (>= assertionsIdx 0) (< assertionsIdx (seq.len assertions))) (>= (str.len (seq.nth assertions assertionsIdx)) 0)))))
  ## axiom-lean: source.length ≥ 0 ∧ assertions.size ≥ 0 ∧ ∀ (i : Fin assertions.size), (assertions.get i).length ≥ 0 ∧ source.length ≥ 0 ∧ assertions.size ≥ 0 ∧ (∀ (assertionsIdx : Fin assertions.size), (assertions.get assertionsIdx).length ≥ 0) ∧ assertions.length = 0 ∧ lines.length = 0 ∧ inserted ∧ inserted = true ∧ (lines ≥ 0) ∧ (inserted ≥ 0) ∧ (assertions ≥ 0) ∧ (∀ (assertionsIdx : Fin assertions.size), (assertions.get assertionsIdx).length ≥ 0)
  if assertions.len == 0:
    return (updated: source, changed: false)
  let lines = source.splitLines()
  if lines.len == 0:
    return (updated: source, changed: false)
  var output: seq[string] = @[]
  var inserted = false
  for line in lines:
    output.add(line)
    let stripped = line.strip()
    if not inserted and stripped.endsWith("="):
      let indent = leadingWhitespace(line) & "  "
      for assertion in assertions:
        output.add(indent & assertion)
      inserted = true
  if inserted:
    return (updated: output.join("\n"), changed: true)
  for assertion in assertions:
    output.add(assertion)
  (updated: output.join("\n"), changed: true)

{.pop.}
