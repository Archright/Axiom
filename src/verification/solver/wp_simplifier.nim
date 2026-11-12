## wp_simplifier.nim — WP Clause Simplification
##
## Normalize and simplify wp (weakest precondition) clauses before
## re-injection into the verification pipeline. Removes redundant
## tautologies, duplicates, and unsimplified expressions that bloat
## Z3 queries.
##
## Simplification rules:
##   1. Identity:    True∧P→P, P∧True→P, False∨P→P, P∨False→P
##   2. Annihilation: False∧P→False, P∧False→False, True∨P→True, P∨True→True
##   3. Idempotence:  P∧P→P, P∨P→P
##   4. Double neg:   ¬(¬P)→P
##   5. Const fold:   evaluate True/False where possible
##
## All functions are pure (func, {.raises: []}) and deterministic.
## Per AGENTS.md §0.6: Static First Enforcement.

import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}
import core/symbolic_types_expr

# ─── Structural Equality ──────────────────────────────────────────────────────

proc symExprEqual*(a, b: SymSExpr): bool {.raises: [].} =
  ## Deep structural equality for SymSExpr trees.
  ## Returns true iff both trees have identical structure and values.
  if a.isNil and b.isNil:
    return true
  if a.isNil or b.isNil:
    return false
  if a.kind != b.kind:
    return false
  if a.name != b.name:
    return false
  if a.intValue != b.intValue:
    return false
  result = symExprEqual(a.lhs, b.lhs) and symExprEqual(a.rhs, b.rhs)

# ─── Variable Collection ──────────────────────────────────────────────────────

proc collectVarNames(expr: SymSExpr; names: var seq[string]) {.raises: [].} =
  ## Collect all variable names from an expression tree.
  if expr.isNil:
    return
  case expr.kind
  of seVar:
    if expr.name notin names:
      names.add(expr.name)
  of seAdd, seSub, seMul, seDiv, seMod,
     seEq, seNe, seLt, seLe, seGt, seGe,
     seAnd, seOr:
    collectVarNames(expr.lhs, names)
    collectVarNames(expr.rhs, names)
  of seNot, seSome, seIsSome, seVal, seOk, seErr, seIsOk, seErrMsg,
     seHead, seTail, seLength:
    collectVarNames(expr.lhs, names)
  of seUninterpretedApp:
    collectVarNames(expr.lhs, names)
  else:
    discard

proc extractVarNames*(clauses: seq[SymSExpr]): seq[string] {.raises: [].} =
  ## Extract all unique variable names from a set of clauses.
  result = @[]
  for clause in clauses:
    collectVarNames(clause, result)

# ─── Conjunction Decomposition ────────────────────────────────────────────────

proc decomposeAnd*(expr: SymSExpr): seq[SymSExpr] {.raises: [].} =
  ## Decompose a conjunction into its conjuncts.
  ## (and A (and B C)) → @[A, B, C]
  if expr.isNil:
    return @[]
  if expr.kind == seAnd:
    result = decomposeAnd(expr.lhs)
    result.add(decomposeAnd(expr.rhs))
  else:
    result = @[expr]

# ─── Helper Functions ────────────────────────────────────────────────────────

proc containsClause*(target: SymSExpr, clauses: seq[SymSExpr]): bool {.raises: [].} =
  ## Check if target exists in clauses using structural equality.
  for existing in clauses:
    if symExprEqual(target, existing):
      return true
  result = false

proc isConjunctSubsetOf*(aConjuncts, bConjuncts: seq[SymSExpr]): bool {.raises: [].} =
  ## Check if all conjuncts of A appear in B's conjuncts.
  if aConjuncts.len > bConjuncts.len:
    return false
  for ac in aConjuncts:
    if not containsClause(ac, bConjuncts):
      return false
  result = true

proc isDominated*(a: SymSExpr, clauses: seq[SymSExpr], skipIdx: int): bool {.raises: [].} =
  ## Check if clause a is dominated (subsumed) by any other clause.
  for j, b in clauses:
    if j == skipIdx:
      continue
    if isConjunctSubsetOf(decomposeAnd(a), decomposeAnd(b)):
      return true
  result = false

proc foldEqConst*(lhs, rhs: SymSExpr): SymSExpr {.raises: [].} =
  ## Fold (= lhs rhs). Returns folded result or nil if not foldable.
  if lhs.isNil or rhs.isNil:
    return nil
  if lhs.kind == seConst and rhs.kind == seConst:
    return if lhs.intValue == rhs.intValue: sTrue() else: sFalse()
  if lhs.kind == seTrue and rhs.kind == seTrue:
    return sTrue()
  if lhs.kind == seFalse and rhs.kind == seFalse:
    return sTrue()
  if lhs.kind == seTrue and rhs.kind == seFalse:
    return sFalse()
  if lhs.kind == seFalse and rhs.kind == seTrue:
    return sFalse()
  result = nil

proc foldNeConst*(lhs, rhs: SymSExpr): SymSExpr {.raises: [].} =
  ## Fold (not (= lhs rhs)). Returns folded result or nil if not foldable.
  if lhs.isNil or rhs.isNil:
    return nil
  if lhs.kind == seConst and rhs.kind == seConst:
    return if lhs.intValue != rhs.intValue: sTrue() else: sFalse()
  result = nil

proc foldRelConst*(kind: SymSymSExprKind, lv, rv: int): SymSExpr {.raises: [].} =
  ## Fold relational comparison of two integer constants.
  let folded = case kind
    of seLt: lv < rv
    of seLe: lv <= rv
    of seGt: lv > rv
    of seGe: lv >= rv
    else: false
  return if folded: sTrue() else: sFalse()

proc foldArithConst*(kind: SymSymSExprKind, lv, rv: int): SymSExpr {.raises: [].} =
  ## Fold arithmetic operation of two integer constants.
  let folded = case kind
    of seAdd: lv + rv
    of seSub: lv - rv
    of seMul: lv * rv
    else: 0
  return sConst(folded)

# ─── Constant Folding ────────────────────────────────────────────────────────

proc createOr*(a, b: SymSExpr): SymSExpr {.inline, raises: [].} =
  ## Create an OR expression (no sOr constructor in symbolic_types_expr).
  new(result)
  result.kind = seOr
  result.lhs = a
  result.rhs = b

proc constantFold*(expr: SymSExpr): SymSExpr {.raises: [].} =
  ## Constant folding: evaluate True/False where possible.
  ## Recursively simplifies children, then applies rules.
  if expr.isNil:
    return expr

  # Recursively simplify children first
  let lhs = constantFold(expr.lhs)
  let rhs = constantFold(expr.rhs)

  case expr.kind
  of seAnd:
    # sAnd already handles identity + annihilation on simplified children
    result = sAnd(lhs, rhs)
  of seOr:
    # Identity: False∨P→P, P∨False→P
    if not lhs.isNil and lhs.kind == seFalse:
      return rhs
    if not rhs.isNil and rhs.kind == seFalse:
      return lhs
    # Annihilation: True∨P→True, P∨True→True
    if not lhs.isNil and lhs.kind == seTrue:
      return sTrue()
    if not rhs.isNil and rhs.kind == seTrue:
      return sTrue()
    # Rebuild with simplified children
    result = createOr(lhs, rhs)
  of seNot:
    # sNot already handles True/False inversion
    let simplified = sNot(lhs)
    # Double negation: ¬(¬P)→P
    if not simplified.isNil and simplified.kind == seNot:
      return simplified.lhs
    return simplified
  of seEq:
    # Constant fold: (= c1 c2) where both are constants
    let folded = foldEqConst(lhs, rhs)
    if not folded.isNil:
      return folded
    new(result)
    result.kind = seEq
    result.lhs = lhs
    result.rhs = rhs
  of seNe:
    # Constant fold: (not (= c1 c2))
    let folded = foldNeConst(lhs, rhs)
    if not folded.isNil:
      return folded
    new(result)
    result.kind = seNe
    result.lhs = lhs
    result.rhs = rhs
  of seLt, seLe, seGt, seGe:
    # Constant fold comparison of two constants
    if not lhs.isNil and not rhs.isNil and
       lhs.kind == seConst and rhs.kind == seConst:
      return foldRelConst(expr.kind, lhs.intValue, rhs.intValue)
    new(result)
    result.kind = expr.kind
    result.lhs = lhs
    result.rhs = rhs
  of seAdd, seSub, seMul:
    # Constant fold arithmetic of two constants
    if not lhs.isNil and not rhs.isNil and
       lhs.kind == seConst and rhs.kind == seConst:
      return foldArithConst(expr.kind, lhs.intValue, rhs.intValue)
    new(result)
    result.kind = expr.kind
    result.lhs = lhs
    result.rhs = rhs
  else:
    # Leaf nodes or unhandled — rebuild with simplified children
    new(result)
    result.kind = expr.kind
    result.name = expr.name
    result.intValue = expr.intValue
    result.lhs = lhs
    result.rhs = rhs

# ─── Idempotence ──────────────────────────────────────────────────────────────

proc applyIdempotence*(expr: SymSExpr): SymSExpr {.raises: [].} =
  ## P∧P→P, P∨P→P
  if expr.isNil:
    return expr
  case expr.kind
  of seAnd:
    if not expr.lhs.isNil and not expr.rhs.isNil and
       symExprEqual(expr.lhs, expr.rhs):
      return applyIdempotence(expr.lhs)
    result = sAnd(applyIdempotence(expr.lhs), applyIdempotence(expr.rhs))
  of seOr:
    if not expr.lhs.isNil and not expr.rhs.isNil and
       symExprEqual(expr.lhs, expr.rhs):
      return applyIdempotence(expr.lhs)
    result = createOr(applyIdempotence(expr.lhs), applyIdempotence(expr.rhs))
  else:
    result = expr

# ─── Public API ───────────────────────────────────────────────────────────────

proc simplifyWpClause*(clause: SymSExpr): SymSExpr {.raises: [].} =
  ## Simplify a single wp clause:
  ## constant fold → idempotence → double negation
  if clause.isNil:
    return clause
  let folded = constantFold(clause)
  result = applyIdempotence(folded)

proc simplifyWpClauses*(clauses: seq[SymSExpr]): seq[SymSExpr] {.raises: [].} =
  ## Batch simplification of wp clauses.
  result = @[]
  for clause in clauses:
    result.add(simplifyWpClause(clause))

proc removeTautologies*(clauses: seq[SymSExpr]): seq[SymSExpr] {.raises: [].} =
  ## Remove clauses that simplify to True (tautologies).
  result = @[]
  for clause in clauses:
    let simplified = simplifyWpClause(clause)
    if not simplified.isNil and simplified.kind != seTrue:
      result.add(simplified)

proc eliminateDuplicates*(clauses: seq[SymSExpr]): seq[SymSExpr] {.raises: [].} =
  ## Eliminate exact duplicate clauses using structural equality.
  result = @[]
  for clause in clauses:
    if not containsClause(clause, result):
      result.add(clause)

proc checkSubsumption*(clauses: seq[SymSExpr]): seq[SymSExpr] {.raises: [].} =
  ## If clause A implies clause B (syntactically), remove B.
  ## Uses conjunct decomposition: if all conjuncts of A appear in B, A⊆B → A→B.
  result = @[]
  for i, a in clauses:
    if not isDominated(a, clauses, i):
      result.add(a)

{.pop.}

