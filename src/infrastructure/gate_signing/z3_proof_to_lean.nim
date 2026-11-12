## Proof-Carrying Code — Phase 3: Z3 Proof → Lean ADT Converter
##
## Parses Z3's SMT-LIB2 proof output into Nim data structures that mirror
## Lean 4 algebraic data types. The Lean kernel will then verify these
## proofs independently, removing Z3 from the trusted computing base (TCB).
##
## Z3 proof format reference:
##   - SMT-LIB2 proof format (resolution-based proof objects)
##   - Each step is an S-expression: (rule-id conclusion premises... args...)
##   - The proof is a directed acyclic graph (DAG) rooted at the final step
##
## Pipeline: Z3 raw proof text → tokenize (Phase 2) → parse (this module)
##           → validate → (Phase 4) Lean kernel verification

import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

import std/[strutils, sequtils, hashes]
# Token type comes from the SMT-LIB2 lexer (Phase 2).
# When smtlib2_parser.nim is available, switch to that import.
import ../../core/solver/smt2_lexer

# ---------------------------------------------------------------------------
# Safe integer parsing — does not raise, compatible with {.raises: [].}
# ---------------------------------------------------------------------------

func safeParseInt*(s: string; val: var int): bool =
  ## Parse an integer from string without raising exceptions.
  ## Returns true if the entire string was a valid integer.
  if s.len == 0:
    return false
  var start = 0
  var negative = false
  if s[0] == '-':
    negative = true
    start = 1
  if start >= s.len:
    return false
  val = 0
  for i in start ..< s.len:
    let c = s[i]
    if c < '0' or c > '9':
      return false
    val = val * 10 + (ord(c) - ord('0'))
  if negative:
    val = -val
  return true

# ---------------------------------------------------------------------------
# Z3 proof rule types — mirrors SMT-LIB2 proof rules
# ---------------------------------------------------------------------------

type
  Z3ProofRuleKind* = enum
    ## Z3 proof rules corresponding to SMT-LIB2 proof object productions.
    ## Each rule describes how a conclusion is derived from premises.
    prkAssertRef      ## Reference to an assertion by ID
    prkModusPonens    ## Modus ponens: from A and A→B, derive B
    prkResolution     ## Resolution: from (A∨B) and (¬B∨C), derive (A∨C)
    prkAndIntro       ## ∧-introduction: from A₁,...,Aₙ derive A₁∧...∧Aₙ
    prkAndElim        ## ∧-elimination: from A₁∧...∧Aₙ derive Aᵢ
    prkOrIntro        ## ∨-introduction: from Aᵢ derive A₁∨...∨Aₙ
    prkOrElim         ## ∨-elimination: case split
    prkImpliesIntro   ## →-introduction
    prkImpliesElim    ## →-elimination (same as modus ponens)
    prkNotElim        ## ¬-elimination: from ¬¬A derive A
    prkContra         ## Ex falso: from ⊥ derive anything
    prkTrueIntro      ## ⊤-introduction
    prkFalseElim      ## ⊥-elimination
    prkReflexivity    ## = reflexivity: a = a
    prkSymmetry       ## = symmetry: from a=b derive b=a
    prkTransitivity   ## = transitivity: from a=b and b=c derive a=c
    prkCongruence     ## = congruence: from a=b derive f(a)=f(b)

  Literal* = object
    ## A single literal in the proof: an atom with a polarity.
    polarity*: bool       ## true = positive, false = negated
    atomId*: int          ## assertion/atom identifier

  Z3ProofStep* = object
    ## A single step in a Z3 proof derivation.
    rule*: Z3ProofRuleKind
    conclusion*: Literal
    premises*: seq[int]   ## indices into the proof step array
    args*: seq[string]    ## rule-specific arguments (raw strings)

  Z3ProofObject* = object
    ## Complete Z3 proof object — a DAG of proof steps.
    steps*: seq[Z3ProofStep]
    rootIndex*: int       ## index of the root (final) proof step

# ---------------------------------------------------------------------------
# Rule name → enum mapping
# ---------------------------------------------------------------------------

const RuleNameMap* = [
  ("assert-ref",      prkAssertRef),
  ("modus-ponens",    prkModusPonens),
  ("resolution",      prkResolution),
  ("and-intro",       prkAndIntro),
  ("and-elim",        prkAndElim),
  ("or-intro",        prkOrIntro),
  ("or-elim",         prkOrElim),
  ("implies-intro",   prkImpliesIntro),
  ("implies-elim",    prkImpliesElim),
  ("not-elim",        prkNotElim),
  ("contra",          prkContra),
  ("true-intro",      prkTrueIntro),
  ("false-elim",      prkFalseElim),
  ("reflexivity",     prkReflexivity),
  ("symmetry",        prkSymmetry),
  ("transitivity",    prkTransitivity),
  ("congruence",      prkCongruence),
]

func lookupRule*(name: string): Z3ProofRuleKind =
  ## Map a rule name string to its enum variant.
  ## Returns prkAssertRef as fallback for unknown rules.
  result = prkAssertRef
  for (rname, rkind) in RuleNameMap:
    if rname == name:
      return rkind

# ---------------------------------------------------------------------------
# Literal parsing
# ---------------------------------------------------------------------------

func parseLiteral*(tokens: seq[Token]; start: int): tuple[lit: Literal, nextPos: int] =
  ## Parse a literal from the token stream at position `start`.
  ##
  ## Format: either a numeral (assertion ID, positive) or
  ##         (not <numeral>) for a negated assertion.
  ##
  ## Returns the parsed Literal and the next position after consumption.
  var pos = start

  if pos >= tokens.len:
    return (Literal(polarity: true, atomId: -1), pos)

  if tokens[pos].kind == tkLParen:
    # Expect (not <numeral>)
    pos += 1
    if pos < tokens.len and tokens[pos].kind == tkSymbol and
       tokens[pos].literal == "not":
      pos += 1
      if pos < tokens.len and tokens[pos].kind == tkNumeral:
        var atomId = 0
        discard safeParseInt(tokens[pos].literal, atomId)
        pos += 1
        if pos < tokens.len and tokens[pos].kind == tkRParen:
          pos += 1
          return (Literal(polarity: false, atomId: atomId), pos)
      # Malformed — consume tokens gracefully
      return (Literal(polarity: false, atomId: -1), pos)
    # Other parenthesized form — treat as positive atom
    return (Literal(polarity: true, atomId: -1), pos)

  if tokens[pos].kind == tkNumeral:
    var atomId = 0
    discard safeParseInt(tokens[pos].literal, atomId)
    pos += 1
    return (Literal(polarity: true, atomId: atomId), pos)

  # Symbol — treat as atom reference (e.g., named assertion)
  if tokens[pos].kind == tkSymbol:
    var atomId = 0
    let parsed = safeParseInt(tokens[pos].literal, atomId)
    if parsed:
      pos += 1
      return (Literal(polarity: true, atomId: atomId), pos)
    # Non-numeric symbol — use hash as ID
    atomId = hash(tokens[pos].literal) and 0x7FFFFFFF
    pos += 1
    return (Literal(polarity: true, atomId: atomId), pos)

  return (Literal(polarity: true, atomId: -1), pos)

# ---------------------------------------------------------------------------
# Single proof step parsing
# ---------------------------------------------------------------------------

func parseProofStep*(tokens: seq[Token]; listChildren: seq[Token];
                     stepIndex: int): Z3ProofStep =
  ## Parse a single proof step from an S-expression's children.
  ##
  ## Expected form:
  ##   (<rule-name> <conclusion> <premise-indices...> :args <arg-values...>)
  ##
  ## The `listChildren` are the tokens inside the outermost parentheses.
  var pos = 0

  # 1. Rule name
  var ruleName = ""
  if pos < listChildren.len and listChildren[pos].kind == tkSymbol:
    ruleName = listChildren[pos].literal
    pos += 1
  let rule = lookupRule(ruleName)

  # 2. Conclusion literal
  var conclusion = Literal(polarity: true, atomId: -1)
  if pos < listChildren.len:
    # Build a sub-sequence for literal parsing
    var subTokens: seq[Token] = @[]
    var parenDepth = 0
    var j = pos
    while j < listChildren.len:
      let t = listChildren[j]
      if t.kind == tkLParen:
        parenDepth += 1
        subTokens.add(t)
      elif t.kind == tkRParen:
        if parenDepth == 0:
          break
        parenDepth -= 1
        subTokens.add(t)
      else:
        subTokens.add(t)
        if parenDepth == 0 and t.kind in {tkNumeral, tkSymbol}:
          j += 1
          break
      j += 1
    let parsed = parseLiteral(subTokens, 0)
    conclusion = parsed.lit
    pos = j

  # 3. Premise indices — collect numerals until :args keyword or end
  var premises: seq[int] = @[]
  var argsStart = -1
  while pos < listChildren.len:
    let t = listChildren[pos]
    if t.kind == tkKeyword:
      argsStart = pos
      break
    if t.kind == tkNumeral:
      var idx = 0
      discard safeParseInt(t.literal, idx)
      premises.add(idx)
    elif t.kind == tkSymbol:
      # Could be a symbolic premise reference
      var idx = 0
      let parsed = safeParseInt(t.literal, idx)
      if parsed:
        premises.add(idx)
    pos += 1

  # 4. Args — after :args keyword
  var args: seq[string] = @[]
  if argsStart >= 0:
    pos = argsStart + 1  # skip :args keyword
    while pos < listChildren.len:
      args.add(listChildren[pos].literal)
      pos += 1

  Z3ProofStep(
    rule: rule,
    conclusion: conclusion,
    premises: premises,
    args: args
  )

# ---------------------------------------------------------------------------
# Main parser
# ---------------------------------------------------------------------------

func parseZ3Proof*(tokens: seq[Token]): Z3ProofObject {.raises: [CatchableError].} =
  ## Parse Z3 proof tokens into a Z3ProofObject.
  ##
  ## Expects tokens representing one or more parenthesized proof steps.
  ## Each step has the form:
  ##   (<rule> <conclusion> <premises...> [:args <args...>])
  ##
  ## The last step in the stream is the proof root.
  result.steps = @[]
  result.rootIndex = 0

  var i = 0
  while i < tokens.len:
    # Skip non-paren tokens at top level
    if tokens[i].kind != tkLParen:
      i += 1
      continue

    # Collect tokens inside this parenthesized group
    i += 1  # consume LParen
    var depth = 1
    var groupTokens: seq[Token] = @[]
    while i < tokens.len and depth > 0:
      if tokens[i].kind == tkLParen:
        depth += 1
        groupTokens.add(tokens[i])
      elif tokens[i].kind == tkRParen:
        depth -= 1
        if depth > 0:
          groupTokens.add(tokens[i])
      else:
        groupTokens.add(tokens[i])
      i += 1

    if groupTokens.len == 0:
      continue

    let step = parseProofStep(tokens, groupTokens, result.steps.len)
    result.steps.add(step)

  if result.steps.len > 0:
    result.rootIndex = result.steps.len - 1

# ---------------------------------------------------------------------------
# Proof validation
# ---------------------------------------------------------------------------

func validateZ3Proof*(proof: Z3ProofObject): bool =
  ## Validate structural integrity of a Z3 proof object.
  ##
  ## Checks:
  ##   1. At least one step exists
  ##   2. Root index is within bounds
  ##   3. All premise indices reference steps that appear earlier (DAG order)
  ##   4. No self-referencing steps
  ##   5. No cycles via reachability (BFS from root)
  if proof.steps.len == 0:
    return false
  if proof.rootIndex < 0 or proof.rootIndex >= proof.steps.len:
    return false

  let n = proof.steps.len

  # Check 1: premise indices in bounds and in strict reverse-topological order
  for idx in 0 ..< n:
    let step = proof.steps[idx]
    for prem in step.premises:
      if prem < 0 or prem >= n:
        return false
      if prem >= idx:
        # Premise must reference an earlier step (topological order)
        return false
      if prem == idx:
        # Self-reference
        return false

  # Check 2: cycle detection via BFS from root
  # Build reverse adjacency: for each step, which steps depend on it?
  var visited = newSeq[bool](n)
  var queue: seq[int] = @[proof.rootIndex]
  visited[proof.rootIndex] = true

  while queue.len > 0:
    let current = queue[^1]
    queue.setLen(queue.len - 1)
    for prem in proof.steps[current].premises:
      if prem >= 0 and prem < n and not visited[prem]:
        visited[prem] = true
        queue.add(prem)

  # Check 3: all steps must be reachable from root
  for idx in 0 ..< n:
    if not visited[idx]:
      return false

  return true

# ---------------------------------------------------------------------------
# Utility
# ---------------------------------------------------------------------------

func proofStepCount*(proof: Z3ProofObject): int =
  ## Return the total number of steps in the proof.
  proof.steps.len

# ---------------------------------------------------------------------------
{.pop.}
