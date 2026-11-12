import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

## Semantic Rule Extractor — derives TransitionRule/InvariantRule from UniversalTranslation.
##
## Phase 1 of feature/k-induction-soundness refactor.
## Replaces hardcoded defaultRule with AST-semantics-based extraction.
##
## Design principles:
##   - Fail-fast: return none when patterns are ambiguous
##   - Conservative: only extract when numeric bounds/operators are clear
##   - Pure: no I/O, no side effects, no exceptions

import std/[options, strutils]
import core/domain_types
import core/bmc/bmc_types

type
  SemanticRuleBundle* = object
    transition*: Option[TransitionRule]
    invariant*: Option[InvariantRule]
    diagnosis*: string  ## reason when both are none

# ---------------------------------------------------------------------------
# Internal: safe integer parsing (no exceptions)
# ---------------------------------------------------------------------------

func parseIntSafe(s: string): (int, bool) =
  ## Parse an integer from a whitespace/paren-stripped string.
  ## Returns (value, true) on success, (0, false) otherwise.
  let trimmed = s.strip()
  if trimmed.len == 0:
    return (0, false)
  var pos = 0
  var negative = false
  if trimmed[0] == '-':
    negative = true
    pos = 1
  elif trimmed[0] == '+':
    pos = 1
  var val = 0
  var foundDigit = false
  while pos < trimmed.len:
    let c = trimmed[pos]
    if c >= '0' and c <= '9':
      foundDigit = true
      val = val * 10 + (ord(c) - ord('0'))
      inc pos
    else:
      break
  if not foundDigit:
    return (0, false)
  if negative:
    val = -val
  (val, true)

func stripParens(s: string): string =
  ## Remove outermost parentheses and whitespace from an SMT-LIB expression.
  result = s.strip()
  while result.len >= 2 and result[0] == '(' and result[^1] == ')':
    result = result[1..^2].strip()

# ---------------------------------------------------------------------------
# Internal: extract last numeric token from a string fragment
# ---------------------------------------------------------------------------

func extractLastNumber(s: string): (int, bool) =
  ## Find the last whitespace-delimited token in `s` and parse it as int.
  ## Tokens may be followed by trailing `)` or whitespace — both are stripped.
  let cleaned = s.strip(chars = {' ', ')', '(', '\t', '\n'})
  if cleaned.len == 0:
    return (0, false)
  # Walk backwards to find last space
  var lastSpace = -1
  for i in countdown(cleaned.len - 1, 0):
    if cleaned[i] == ' ':
      lastSpace = i
      break
  let numStr = cleaned[(lastSpace + 1)..^1]
  parseIntSafe(numStr)

# ---------------------------------------------------------------------------
# Internal: invariant parsing
# ---------------------------------------------------------------------------

func tryParseInvariant(entry: string): Option[InvariantRule] =
  ## Extract an InvariantRule from a single state-invariant entry.
  ## Handles SMT-LIB patterns like `(>= x N)`, `(<= x N)`, and bare `>= N`.
  let s = stripParens(entry)
  if s.len == 0:
    return none(InvariantRule)

  # >= pattern (minimum bound)
  let geIdx = s.find(">=")
  if geIdx >= 0:
    let after = s[(geIdx + 2)..^1]
    let (val, ok) = extractLastNumber(after)
    if ok:
      return some(makeMinValueInvariant(val))

  # <= pattern (maximum bound)
  let leIdx = s.find("<=")
  if leIdx >= 0:
    let after = s[(leIdx + 2)..^1]
    let (val, ok) = extractLastNumber(after)
    if ok:
      return some(makeMaxValueInvariant(val))

  none(InvariantRule)

# ---------------------------------------------------------------------------
# Internal: transition parsing
# ---------------------------------------------------------------------------

func tryParseTransition(entry: string): Option[TransitionRule] =
  ## Extract a TransitionRule from a single transition-relation entry.
  ## Looks for arithmetic delta patterns: `(+ N)` or `(- N)` where N is numeric.
  let s = stripParens(entry)
  if s.len == 0:
    return none(TransitionRule)

  # Scan right-to-left for the last arithmetic operator with a numeric operand.
  # This handles both SMT-LIB `(- x 1)` and algebraic `x - 1`.
  for i in countdown(s.len - 1, 1):
    let c = s[i]
    if c == '+' or c == '-':
      # Operator must be preceded by space or '(' to be an arithmetic op
      if s[i - 1] == ' ' or s[i - 1] == '(':
        let after = s[(i + 1)..^1]
        let (delta, ok) = extractLastNumber(after)
        if ok and delta != 0:
          if c == '+':
            return some(makeAddRule(delta))
          else:
            return some(makeSubtractRule(delta))

  none(TransitionRule)

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func extractRuleBundle*(
  translation: UniversalTranslation;
  nodeId: string;
  sourceCode: string
): SemanticRuleBundle {.raises: [].} =
  ## Derive TransitionRule / InvariantRule from UniversalTranslation fields.
  ##
  ## - If `transitionRelation` entries contain parseable arithmetic → some TransitionRule
  ## - If `stateInvariants` entries contain parseable bounds → some InvariantRule
  ## - For pure/functional nodes or unparseable entries → none with diagnosis
  ##
  ## `nodeId` and `sourceCode` are reserved for future AST-aware extraction
  ## and do not affect current extraction logic.

  result = SemanticRuleBundle(
    transition: none(TransitionRule),
    invariant: none(InvariantRule),
    diagnosis: ""
  )

  var hasTransition = false
  var hasInvariant = false

  # 1. Attempt transition-relation extraction
  if translation.transitionRelation.len > 0:
    for entry in translation.transitionRelation:
      let parsed = tryParseTransition(entry)
      if parsed.isSome:
        result.transition = parsed
        hasTransition = true
        break

  # 2. Attempt state-invariant extraction
  if translation.stateInvariants.len > 0:
    for entry in translation.stateInvariants:
      let parsed = tryParseInvariant(entry)
      if parsed.isSome:
        result.invariant = parsed
        hasInvariant = true
        break

  # 3. Diagnosis for non-extraction cases
  if not hasTransition and not hasInvariant:
    if translation.transitionRelation.len == 0 and
       translation.stateInvariants.len == 0:
      result.diagnosis = "empty_translation: no transition relation or state invariants provided"
    else:
      let trCount = translation.transitionRelation.len
      let siCount = translation.stateInvariants.len
      result.diagnosis = "parse_failure: " & $trCount & " transition entries, " &
        $siCount & " invariant entries — none produced a structured rule"

{.pop.}
