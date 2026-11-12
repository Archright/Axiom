import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

## Semantic Target Extractor — detects obligation candidates from IRFuncDef.
##
## Pure function: `extractObligationCandidates` mechanically inspects the
## IR tree and returns all obligation candidates. Reuses existing
## contract_synthesis.nim helpers (collectDivisionGuardSites,
## collectIndexGuardSites, collectPostconditions) to avoid duplicating
## tree-walking logic.
##
## Safety candidates carry the guard emitted by contract_synthesis as their
## proposition, so the divisor / index expression under test survives into the
## obligation, and its assumptions are the enclosing path condition.
##
## C6 closure: all predicate strings are canonicalized via
## `canonicalizePredicate` from obligation_types.nim.
##
## Detection order matches spec §3 priority:
## 1. Division safety (boDiv, boRem, boRemU)
## 2. Index safety (irCall "[]", charAt, substr)
## 3. Loop bound (loopCond)
## 4. Loop variant (loopVariant)
## 5. Preconditions (manual)
## 6. Postconditions (pragma + auto-synthesized)

import std/[sequtils, strutils, algorithm, sets]
import core/trusted/axiom_ir
import core/trusted/contract_synthesis
import verification/obligation/obligation_types

# ---------------------------------------------------------------------------
# ObligationCandidate — intermediate representation of a detected obligation
# ---------------------------------------------------------------------------

type
  ObligationCandidate* = object
    kind*: ObligationKind
    subject*: string
    assumptions*: seq[string]
    predicate*: string       ## canonical string form (via canonicalizePredicate)
    proposition*: IRExpr     ## typed semantic proposition (authoritative)
    derivationRule*: string

# ---------------------------------------------------------------------------
# Internal helpers — read operands back out of a guard expression
# ---------------------------------------------------------------------------
## Guards are built from the real operand sub-expressions, so every label below
## is read off the guard IRExpr.  Nothing is reconstructed from a name that
## could collapse to a placeholder, and nothing is invented when a guard has an
## unrecognized shape — the canonical predicate is used instead.

func describeOperand(e: IRExpr): string {.raises: [].} =
  ## Readable rendering of a guard operand, taken from the operand itself.
  if e == nil: return "nil"
  case e.kind
  of irVar: e.varName
  of irLit: $e.litVal
  else: canonicalizePredicate(e)

func guardDivisor(guard: IRExpr): IRExpr {.raises: [].} =
  ## The divisor sub-expression of a ¬(divisor == 0) guard.
  ## nil when `guard` is not that shape.
  if guard != nil and guard.kind == irUnaryOp and guard.unaryOp == uoNot:
    let inner = guard.unaryArg
    if inner != nil and inner.kind == irBinOp and inner.binOp == boEq:
      let rhs = inner.binRhs
      if rhs != nil and rhs.kind == irLit and rhs.litVal == 0:
        return inner.binLhs
  nil

func guardIndexOperands(guard: IRExpr): (IRExpr, IRExpr) {.raises: [].} =
  ## (bound, sequence) of a `0 ≤ idx ∧ idx < len(seq)` guard;
  ## (nil, nil) for any other shape (e.g. the substr bounds guard).
  if guard != nil and guard.kind == irBinOp and guard.binOp == boAnd:
    let ge = guard.binLhs
    let lt = guard.binRhs
    if ge != nil and ge.kind == irBinOp and ge.binOp == boGe and
       lt != nil and lt.kind == irBinOp and lt.binOp == boLt:
      let lenCall = lt.binRhs
      if lenCall != nil and lenCall.kind == irCall and
         lenCall.callName == "len" and lenCall.callArgs.len == 1:
        return (ge.binLhs, lenCall.callArgs[0])
  (nil, nil)

# ---------------------------------------------------------------------------
# Safety candidate construction
# ---------------------------------------------------------------------------
## The proposition IS the guard emitted by contract_synthesis, so the divisor /
# index expression the guard was built from is carried into the obligation
## verbatim.  The assumptions are the enclosing path condition — never a
## restatement of the predicate, and empty when the operation is unconditional
## (an unconditional division is a real obligation, not a discharged one).

func makeDivCandidate(site: GuardSite): ObligationCandidate {.raises: [].} =
  ## Division safety candidate for one guard site.
  let divisor = guardDivisor(site.guard)
  let subj = if divisor == nil: canonicalizePredicate(site.guard)
             else: describeOperand(divisor) & " ≠ 0"
  ObligationCandidate(
    kind: okSafetyDiv,
    subject: subj,
    assumptions: site.pathCondition.mapIt(canonicalizePredicate(it)),
    predicate: canonicalizePredicate(site.guard),
    proposition: site.guard,
    derivationRule: "obs:division"
  )

func makeIndexCandidate(site: GuardSite): ObligationCandidate {.raises: [].} =
  ## Index safety candidate for one guard site.
  let (bound, seqExpr) = guardIndexOperands(site.guard)
  let subj =
    if bound == nil: canonicalizePredicate(site.guard)
    else: "0 ≤ " & describeOperand(bound) & " ∧ " & describeOperand(bound) &
          " < length(" & describeOperand(seqExpr) & ")"
  ObligationCandidate(
    kind: okSafetyIndex,
    subject: subj,
    assumptions: site.pathCondition.mapIt(canonicalizePredicate(it)),
    predicate: canonicalizePredicate(site.guard),
    proposition: site.guard,
    derivationRule: "obs:index"
  )

# ---------------------------------------------------------------------------
# Loop detection — walk IR tree to find irLoop nodes
# ---------------------------------------------------------------------------

func collectLoops*(body: IRExpr): seq[IRExpr] {.raises: [].} =
  ## Collect all irLoop sub-expressions in the body.
  result = @[]
  func walk(e: IRExpr, acc: var seq[IRExpr]) {.raises: [].} =
    if e == nil: return
    case e.kind
    of irLoop:
      acc.add e
      walk(e.loopCond, acc)
      walk(e.loopStep, acc)
      walk(e.loopBody, acc)
      for inv in e.loopInvariants: walk(inv, acc)
      walk(e.loopVariant, acc)
      for init in e.loopInits: walk(init, acc)
    of irBinOp:
      walk(e.binLhs, acc)
      walk(e.binRhs, acc)
    of irLet:
      walk(e.letVal, acc)
      walk(e.letBody, acc)
    of irIf:
      walk(e.ifCond, acc)
      walk(e.ifThen, acc)
      walk(e.ifElse, acc)
    of irCall:
      for a in e.callArgs: walk(a, acc)
    of irCase:
      walk(e.caseScrutinee, acc)
      for b in e.caseBranches: walk(b.body, acc)
      walk(e.caseDefault, acc)
    of irUnaryOp:
      walk(e.unaryArg, acc)
    of irRecCall:
      for a in e.recArgs: walk(a, acc)
    of irCast:
      walk(e.castExpr, acc)
    else: discard
  walk(body, result)

# ---------------------------------------------------------------------------
# Main extraction function
# ---------------------------------------------------------------------------

func compareCandidates(a, b: ObligationCandidate): int {.raises: [].} =
  ## Total order used for determinism (C4): kind, then subject, then
  ## derivationRule, then the proposition itself. The trailing keys break the
  ## ties that two sites with the same subject under different path conditions
  ## would otherwise leave to an unstable sort.
  var c = cmp(a.kind.ord, b.kind.ord)
  if c != 0: return c
  c = cmp(a.subject, b.subject)
  if c != 0: return c
  c = cmp(a.derivationRule, b.derivationRule)
  if c != 0: return c
  c = cmp(a.predicate, b.predicate)
  if c != 0: return c
  cmp(a.assumptions.join("|"), b.assumptions.join("|"))

func contractCandidate(kind: ObligationKind; subject: string;
                       predExpr: IRExpr): ObligationCandidate {.raises: [].} =
  ## A manually stated contract target. Preconditions and postconditions share
  ## this shape; only the subject label and the obligation kind differ.
  ObligationCandidate(
    kind: kind,
    subject: subject,
    assumptions: @[],
    predicate: canonicalizePredicate(predExpr),
    proposition: predExpr,
    derivationRule: "obs:contract"
  )

func addLoopCandidates(candidates: var seq[ObligationCandidate];
                      loops: seq[IRExpr]) {.raises: [].} =
  ## Loop bound and loop variant targets. A loop may carry neither, one, or
  ## both; each present one becomes its own candidate, bound before variant.
  for loop in loops:
    if loop.loopCond != nil:
      candidates.add ObligationCandidate(
        kind: okSafetyLoopBound,
        subject: "loopCond",
        assumptions: @["bound ∈ ℕ", "bound decreases each iteration"],
        predicate: canonicalizePredicate(loop.loopCond),
        proposition: loop.loopCond,
        derivationRule: "obs:loopBound"
      )
    if loop.loopVariant != nil:
      candidates.add ObligationCandidate(
        kind: okSafetyLoopBound,
        subject: "variantFunction",
        assumptions: @["v ∈ ℕ", "v strictly decreases on each iteration"],
        predicate: canonicalizePredicate(loop.loopVariant),
        proposition: loop.loopVariant,
        derivationRule: "obs:loopVariant"
      )

func addPostCandidate(candidates: var seq[ObligationCandidate]; funcName: string;
                      post: IRExpr; seen: var seq[string]) {.raises: [].} =
  ## One postcondition, unless the same canonical predicate was already emitted.
  if post == nil: return
  let canonPred = canonicalizePredicate(post)
  if canonPred in seen: return
  seen.add canonPred
  candidates.add contractCandidate(okContractPost, funcName & " postcondition", post)

func addPostCandidates(candidates: var seq[ObligationCandidate]; funcDef: IRFuncDef;
                       seen: var seq[string]) {.raises: [].} =
  ## Explicit and auto-synthesized postconditions, merged and de-duplicated by
  ## canonical predicate — the same contract restated by both sources is one
  ## obligation, not two.
  for post in funcDef.postConditions:
    addPostCandidate(candidates, funcDef.name, post, seen)
  for post in collectPostconditions(funcDef):
    addPostCandidate(candidates, funcDef.name, post, seen)

func extractObligationCandidates*(funcDef: IRFuncDef): seq[ObligationCandidate] {.raises: [].} =
  ## Extract all obligation candidates from an IRFuncDef.
  ## Pure, deterministic, total.
  ##
  ## Detection order (matches spec §3 priority):
  ## 1. Division safety (boDiv, boRem, boRemU)
  ## 2. Index safety (irCall "[]", charAt, substr)
  ## 3. Loop bound (loopCond)
  ## 4. Loop variant (loopVariant)
  ## 5. Preconditions (manual)
  ## 6. Postconditions (pragma + auto-synthesized)
  if funcDef.body == nil:
    return @[]

  # 1./2. Safety guards — each carries the path condition that must hold for the
  #      operation to be reached (contract_synthesis.nim).
  for site in collectDivisionGuardSites(funcDef.body):
    result.add makeDivCandidate(site)
  for site in collectIndexGuardSites(funcDef.body):
    result.add makeIndexCandidate(site)

  # 3./4. Loop bounds and variants — walk IR to find irLoop nodes.
  addLoopCandidates(result, collectLoops(funcDef.body))

  # 5. Preconditions (manual).
  for pre in funcDef.preConditions:
    if pre != nil:
      result.add contractCandidate(okContractPre, funcDef.name & " precondition", pre)

  # 6. Postconditions (explicit + auto-synthesized).
  var seenPostPreds: seq[string]
  addPostCandidates(result, funcDef, seenPostPreds)

  result.sort(compareCandidates)

# ---------------------------------------------------------------------------
# Semantic dependency collection — walks the IR tree to find all irCall
# targets that this function depends on (excluding self-recursion).
# ---------------------------------------------------------------------------
## Collects the set of callee function names referenced in an IRFuncDef's
## body, preconditions, and postconditions via irCall nodes.
## Self-recursive calls (irRecCall) are excluded — they do not represent
## a dependency on a *different* symbol.
## The result is sorted and deduplicated for deterministic ordering.

func collectSemanticDependencies*(funcDef: IRFuncDef): seq[string] {.raises: [].} =
  var seen: HashSet[string]
  func walk(e: IRExpr, acc: var HashSet[string]) {.raises: [].} =
    if e == nil: return
    case e.kind
    of irCall:
      if e.callName != funcDef.name:
        acc.incl(e.callName)
      for a in e.callArgs: walk(a, acc)
    of irRecCall:
      # Self-recursive call — not a cross-symbol dependency.
      discard
    of irIf:
      walk(e.ifCond, acc); walk(e.ifThen, acc); walk(e.ifElse, acc)
    of irBinOp:
      walk(e.binLhs, acc); walk(e.binRhs, acc)
    of irLet:
      walk(e.letVal, acc); walk(e.letBody, acc)
    of irCase:
      walk(e.caseScrutinee, acc)
      for b in e.caseBranches: walk(b.body, acc)
      walk(e.caseDefault, acc)
    of irUnaryOp:
      walk(e.unaryArg, acc)
    of irLoop:
      for init in e.loopInits: walk(init, acc)
      walk(e.loopCond, acc); walk(e.loopStep, acc); walk(e.loopBody, acc)
      for inv in e.loopInvariants: walk(inv, acc)
      walk(e.loopVariant, acc)
    of irCast:
      walk(e.castExpr, acc)
    else: discard
  walk(funcDef.body, seen)
  for pre in funcDef.preConditions: walk(pre, seen)
  for post in funcDef.postConditions: walk(post, seen)
  result = seen.toSeq.sorted

{.pop.}
