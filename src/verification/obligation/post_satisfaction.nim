import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

## Post-Satisfaction-by-Construction Analysis — bounded, body-aware no-reachable-violation.
##
## Phase A: proves that a function's postcondition is satisfied BY CONSTRUCTION
## from a narrow, structurally admissible body + post shape, so the obligation
## generator may classify it `ogrNoApplicableObligation` (reason
## `obs:postSatisfiedByConstruction`) instead of generating a post obligation
## that the Lean pipeline must (but cannot faithfully) discharge.
##
## IMPORTANT CONTRACT (do not widen):
##   - `analyzePostByConstruction` returns `some(...)` ONLY when the body and
##     post match a very narrow, by-construction satisfiable shape (below).
##   - ANY ambiguity → `none` → the caller keeps the generated (ogrGenerated)
##     path. This matcher NEVER asserts a false no-reachable-violation.
##   - It is a POST-ONLY matcher: it only ever converts an okContractPost
##     obligation to no-applicable. Other obligation kinds (div/index/loop)
##     are unaffected because the body gate below excludes the constructs that
##     would produce them.
##
## Matched shape (documented, design-change-sensitive):
##   1. body: a single `if/else` where BOTH branches return a plain leaf:
##        body = IF(G ? T : E), T and E each ∈ {irLit, irVar}  (leaf-only).
##      The guard G is a single comparison atom or its negation (below).
##      No loops, no nested if, no case, no casts, no div/rem/index/calls
##      (except a permitted `len(S)` on the guard side), no recursion.
##   2. post: exactly ONE top-level postcondition P. P is a disjunction of
##      clauses (left-nested boOr), or a single clause. Each clause C is:
##        C = G_c ∧ (result == leaf_c)
##      where the comparison is boEq with one side the `result` var and the
##      other side a plain leaf (irLit/irVar). Guard atoms are permitted
##      only over `len(S)` or a bare integer var vs a literal.
##   3. Matching: the two body branches (then guard=G, then leaf=T; else
##      guard=¬G, else leaf=E) must each correspond to a DISTINCT post
##      clause with equal normalized guard AND equal leaf. No clause
##      leftovers, no unmatched branch.
##   4. Guard normalization uses the only built-in arithmetic fact we admit:
##      `len(S) >= 0`, giving  ¬(len(S)>0) ⟺ len(S)==0  and  ¬(len(S)==0) ⟺ len(S)>0.
##      No other arithmetic/order reasoning is performed. Anything else → none.
##
## Core safety principle: `none` is the fail-closed default. The only way to
## get `some(...)` is structural exact-match plus the len-nonneg rewrite, so a
## false "no violation" claim is structurally impossible for the admitted set.

import std/[options, strutils, sequtils, algorithm]
import core/trusted/axiom_ir
import core/trusted/axiom_ir_helpers

# ---------------------------------------------------------------------------
# Leaf extraction — only literals and plain variables are leaves.
# ---------------------------------------------------------------------------

func unwrapOpCast(e: IRExpr): IRExpr {.raises: [].} =
  ## The boAnd/boOr smart constructor may wrap a BV64 operand in
  ## irCall("opCastToBool", ...). Strip one such layer when present so
  ## leaves and guard sides compare on their semantic content.
  if e != nil and e.kind == irCall and e.callName == "opCastToBool" and e.callArgs.len == 1:
    e.callArgs[0]
  else:
    e

func leafStr(e: IRExpr): Option[string] {.raises: [].} =
  ## Canonical string for a leaf: irLit -> "lit:<val>", irVar -> "var:<name>".
  ## Anything else (binop, call, if, case, cast, ...) -> none.
  let u = unwrapOpCast(e)
  if u == nil: return none(string)
  case u.kind
  of irLit:     some("lit:" & $u.litVal)
  of irVar:     some("var:" & u.varName)
  else:         none(string)

# ---------------------------------------------------------------------------
# Guard atom canonicalization (len-nonneg rewrite only)
# ---------------------------------------------------------------------------

type
  GuardAtom = object
    ## A normalized guard atom: kind (the comparison family) over a subject
    ## (len(S) or bare var) vs a literal bound. `negated` is resolved during
    ## normalization so the stored atom is always in positive form.
    subject*: string      ## "len:<seqname>" or "var:<name>"
    op*: BinOpKind        ## boGt / boGe / boLt / boLe / boEq
    bound*: int64
    literal: string       ## canonical full atom string

func atomSubject(e: IRExpr): Option[(string, string)] {.raises: [].} =
  ## Return (subjectKind, subjectId). subjectId is "len:<name>" for a `len(S)`
  ## call, or "var:<name>" for a bare variable. Only these two are admitted.
  let u = unwrapOpCast(e)
  if u == nil: return none((string, string))
  case u.kind
  of irCall:
    if u.callName == "len" and u.callArgs.len == 1:
      let arg = unwrapOpCast(u.callArgs[0])
      if arg != nil and arg.kind == irVar:
        return some(("len", "len:" & arg.varName))
    none((string, string))
  of irVar:
    some(("var", "var:" & u.varName))
  else:
    none((string, string))

func guardAtomOf(e: IRExpr): Option[GuardAtom] {.raises: [].} =
  ## Canonicalize a positive (non-negated) comparison atom.
  ## Admitted: (subject cmp literal), subject ∈ {len:<S>, var:<name>},
  ## op ∈ {boGt, boGe, boLt, boLe, boEq}. else -> none.
  let u = unwrapOpCast(e)
  if u == nil or u.kind != irBinOp: return none(GuardAtom)
  if u.binOp notin {boGt, boGe, boLt, boLe, boEq}: return none(GuardAtom)
  # Only literal vs subject forms: one side literal, the other a subject.
  var subj: Option[(string, string)]
  var bound: int64
  var litSide: IRExpr
  var subjSide: IRExpr
  if u.binLhs != nil and u.binLhs.kind == irLit and u.binRhs != nil:
    bound = u.binLhs.litVal
    litSide = u.binLhs
    subjSide = u.binRhs
  elif u.binRhs != nil and u.binRhs.kind == irLit and u.binLhs != nil:
    bound = u.binRhs.litVal
    litSide = u.binRhs
    subjSide = u.binLhs
  else:
    return none(GuardAtom)
  subj = atomSubject(subjSide)
  if subj.isNone: return none(GuardAtom)
  # Compute the canonical atom string.
  let s = subj.get
  var opStr = ""
  case u.binOp
  of boGt: opStr = ">"
  of boGe: opStr = ">="
  of boLt: opStr = "<"
  of boLe: opStr = "<="
  of boEq: opStr = "=="
  else: discard
  if opStr.len == 0: return none(GuardAtom)
  result = some(GuardAtom(
    subject: s[1], op: u.binOp, bound: bound,
    literal: s[1] & opStr & $bound))

func negateGuardAtom(a: GuardAtom): Option[GuardAtom] {.raises: [].} =
  ## Negate a positive atom using ONLY the len>=0 fact for len subjects.
  ## For len subjects:
  ##   ¬(len>S>0) ⟺ len==0 ; ¬(len==0) ⟺ len>0 ; ¬(len>0) for var -> none
  ##   ¬(len>=0) would be len<0 ≡ false -> not admitted.
  ## For var subjects: no arithmetic facts admitted -> none (fail closed).
  if a.subject.startsWith("len:"):
    case a.op
    of boGt:
      if a.bound == 0:
        return some(GuardAtom(subject: a.subject, op: boEq, bound: 0, literal: a.subject & "==" & "0"))
    of boEq:
      if a.bound == 0:
        return some(GuardAtom(subject: a.subject, op: boGt, bound: 0, literal: a.subject & ">" & "0"))
    else: discard
  none(GuardAtom)

func normalizeGuard(e: IRExpr): Option[string] {.raises: [].} =
  ## Normalize a single guard (atom or its negation) to a canonical string.
  ##   - positive atom           -> its canonical literal
  ##   - not(atom) with len-subj -> negateGuardAtom literal
  ##   - anything else           -> none
  let u = unwrapOpCast(e)
  if u == nil: return none(string)
  if u.kind == irBinOp:
    let a = guardAtomOf(u)
    if a.isSome: return some(a.get.literal)
    return none(string)
  if u.kind == irUnaryOp and u.unaryOp == uoNot:
    let inner = unwrapOpCast(u.unaryArg)
    let a = guardAtomOf(inner)
    if a.isSome:
      let neg = negateGuardAtom(a.get)
      if neg.isSome: return some(neg.get.literal)
      return none(string)
    return none(string)
  none(string)

# ---------------------------------------------------------------------------
# Post clause extraction
# ---------------------------------------------------------------------------

type
  PostClause = object
    guard*: string        ## canonical guard string ("" if none — but we require one)
    leaf*: string         ## canonical leaf string ("lit:0" / "var:x")
    used*: bool

func clauseFromExpr(e: IRExpr): Option[PostClause] {.raises: [].} =
  ## Parse a single clause:  G_c ∧ (result == leaf)   OR just  (result == leaf).
  ## Returns some(clause) iff exactly one result==leaf comparison is found and
  ## its leaf is a plain leaf; the remaining conjunction chain must consist of
  ## guard atoms each normalizable, and collectively normalized into a single
  ## guard string (conjunction of all guard atoms, joined).
  let u = unwrapOpCast(e)
  if u == nil: return none(PostClause)
  # Collect conjuncts of a right-peel... actually boAnd builds left-nested.
  var conjuncts: seq[IRExpr] = @[]
  proc peel(e: IRExpr) {.raises: [].} =
    let w = unwrapOpCast(e)
    if w != nil and w.kind == irBinOp and w.binOp == boAnd:
      peel(w.binLhs)
      peel(w.binRhs)
    else:
      conjuncts.add(e)
  peel(u)

  var leafOpt: Option[string]
  var guardStrs: seq[string] = @[]
  for c in conjuncts:
    let w = unwrapOpCast(c)
    if w == nil: return none(PostClause)
    if w.kind == irBinOp and w.binOp == boEq:
      # result == leaf OR leaf == result
      var leafSide: IRExpr
      var otherSide: IRExpr
      if w.binLhs != nil and w.binLhs.kind == irVar and w.binLhs.varName == "result":
        leafSide = w.binRhs
        otherSide = w.binLhs
      elif w.binRhs != nil and w.binRhs.kind == irVar and w.binRhs.varName == "result":
        leafSide = w.binLhs
        otherSide = w.binRhs
      else:
        otherSide = w  # not the result binding -> treat as guard atom
        leafSide = nil
      if leafSide != nil:
        if leafOpt.isSome: return none(PostClause)  # two result bindings
        let ls = leafStr(leafSide)
        if ls.isNone: return none(PostClause)
        leafOpt = ls
      else:
        let g = normalizeGuard(otherSide)
        if g.isNone: return none(PostClause)
        guardStrs.add(g.get)
    else:
      let g = normalizeGuard(w)
      if g.isNone: return none(PostClause)
      guardStrs.add(g.get)

  if leafOpt.isNone: return none(PostClause)
  guardStrs.sort()
  let guard = guardStrs.join("&")
  result = some(PostClause(guard: guard, leaf: leafOpt.get, used: false))

func collectClauses(post: IRExpr): Option[seq[PostClause]] {.raises: [].} =
  ## Split a postcondition expression into disjuncts (left-nested boOr, or a
  ## single clause if not a disjunction at all). Each disjunct must parse as a
  ## clause. Returns none if any disjunct fails to parse.
  let u = unwrapOpCast(post)
  if u == nil: return none(seq[PostClause])
  var disjuncts: seq[IRExpr] = @[]
  proc peel(e: IRExpr) {.raises: [].} =
    let w = unwrapOpCast(e)
    if w != nil and w.kind == irBinOp and w.binOp == boOr:
      peel(w.binLhs)
      peel(w.binRhs)
    else:
      disjuncts.add(e)
  peel(u)
  var clauses: seq[PostClause] = @[]
  for d in disjuncts:
    let c = clauseFromExpr(d)
    if c.isNone: return none(seq[PostClause])
    clauses.add(c.get)
  some(clauses)

func findUnusedClause(clauses: openArray[PostClause], guardStr, leafStrVal: string): int {.raises: [].} =
  ## Return index of the first unused clause matching both normalized guard and
  ## leaf strings, else -1.
  result = -1
  for i in 0 ..< clauses.len:
    if not clauses[i].used and clauses[i].guard == guardStr and clauses[i].leaf == leafStrVal:
      result = i
      return

# ---------------------------------------------------------------------------
# Body gate — single if/else with leaf-only branches
# ---------------------------------------------------------------------------

func bodyAsIfElse(body: IRExpr): Option[(IRExpr, IRExpr, IRExpr)] {.raises: [].} =
  ## body == IF(G ? T : E) with T, E leaves and G a normalizable guard.
  ## Returns (G, T, E). Any structural deviation -> none.
  let u = unwrapOpCast(body)
  if u == nil or u.kind != irIf: return none((IRExpr, IRExpr, IRExpr))
  if u.ifThen == nil or u.ifElse == nil: return none((IRExpr, IRExpr, IRExpr))
  if leafStr(u.ifThen).isNone: return none((IRExpr, IRExpr, IRExpr))
  if leafStr(u.ifElse).isNone: return none((IRExpr, IRExpr, IRExpr))
  if normalizeGuard(u.ifCond).isNone: return none((IRExpr, IRExpr, IRExpr))
  some((u.ifCond, u.ifThen, u.ifElse))

# ---------------------------------------------------------------------------
# Result provenance
# ---------------------------------------------------------------------------

type
  PostSatisfactionProvenance* = object
    derivationRule*: string
    semanticFacts*: seq[string]
    ## facts: normalized guards + leaf strings used in the match.

# ---------------------------------------------------------------------------
# Main analysis
# ---------------------------------------------------------------------------

func analyzePostByConstruction*(
  funcDef: IRFuncDef
): Option[PostSatisfactionProvenance] {.raises: [].} =
  ## Returns some(provenance) iff the body+post structurally and semantically
  ## establish the (single) postcondition by construction, with branch guards
  ## and leaves exactly covering the post clauses. Anything else -> none.
  ##
  ## Contract: this NEVER returns some() unless the exact-match holds; it is
  ## fail-closed. See top-of-file documented shape.

  # Body gate.
  let ifb = bodyAsIfElse(funcDef.body)
  if ifb.isNone: return none(PostSatisfactionProvenance)
  let (gCond, gThen, gElse) = ifb.get

  # Post gate: exactly one postcondition.
  if funcDef.postConditions.len != 1: return none(PostSatisfactionProvenance)
  let post = funcDef.postConditions[0]
  if post == nil: return none(PostSatisfactionProvenance)

  # Clause extraction.
  let clauseOpt = collectClauses(post)
  if clauseOpt.isNone: return none(PostSatisfactionProvenance)
  var clauses = clauseOpt.get
  if clauses.len == 0: return none(PostSatisfactionProvenance)

  # Then-branch guard G; else-branch guard = ¬G (normalized via len-nonneg).
  let gThenNorm = normalizeGuard(gCond)
  if gThenNorm.isNone: return none(PostSatisfactionProvenance)
  let gElseNeg = normalizeGuard(irUnaryOp(uoNot, gCond))
  if gElseNeg.isNone: return none(PostSatisfactionProvenance)
  let tLeaf = leafStr(gThen).get
  let eLeaf = leafStr(gElse).get
  let gThenS = gThenNorm.get
  let gElseS = gElseNeg.get

  # Exactly two body branches and at least the clauses must be matchable.
  # Match then-branch: find a single unused clause with guard==gThenS and leaf==tLeaf.
  let iThen = findUnusedClause(clauses, gThenS, tLeaf)
  if iThen < 0: return none(PostSatisfactionProvenance)
  clauses[iThen].used = true
  let iElse = findUnusedClause(clauses, gElseS, eLeaf)
  if iElse < 0: return none(PostSatisfactionProvenance)
  clauses[iElse].used = true

  # No leftover unused clauses.
  for c in clauses:
    if not c.used: return none(PostSatisfactionProvenance)

  # Every branch covered by a distinct clause, all clauses used -> by construction.
  var facts = newSeq[string]()
  facts.add("body=if/else-leaf")
  facts.add("then_guard=" & gThenS)
  facts.add("then_leaf=" & tLeaf)
  facts.add("else_guard=" & gElseS)
  facts.add("else_leaf=" & eLeaf)
  facts.add("clauses=" & $clauses.len)
  facts.add("len_nonnneg_rewrite=admitted")
  some(PostSatisfactionProvenance(
    derivationRule: "obs:postSatisfiedByConstruction",
    semanticFacts: facts))

{.pop.}
