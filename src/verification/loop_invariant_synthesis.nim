import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

import core/orchestrator/cfg_builder
import compiler/ast
import core/results
import core/symbolic/symbolic_types_exec
import core/symbolic/symbolic_types_parse
import core/symbolic_types_expr
import std/options
import std/strutils
import std/tables
import ../core/trusted/axiom_pragmas_lite
func substituteVars(e: SymSExpr, subst: Table[string, string]): SymSExpr {.raises: [].} =
  if e.isNil:
    return nil
  case e.kind
  of seVar:
    return sVar(subst.getOrDefault(e.name, e.name))
  of seConst, seTrue, seFalse:
    return e
  of seAdd, seSub, seMul, seDiv, seMod,
     seEq, seNe, seLt, seLe, seGt, seGe,
     seAnd, seOr, seNot:
    # seNot is unary (rhs is nil); binary operators use both lhs and rhs.
    let newLhs = substituteVars(e.lhs, subst)
    let newRhs = if e.rhs.isNil: nil else: substituteVars(e.rhs, subst)
    new(result)
    result.kind = e.kind
    result.lhs = newLhs
    result.rhs = newRhs
  else:
    # Generic deep-copy for new ADT/collection/abstract variants.
    new(result)
    result.kind = e.kind
    result.name = e.name
    result.intValue = e.intValue
    if e.lhs != nil:
      result.lhs = substituteVars(e.lhs, subst)
    if e.rhs != nil:
      result.rhs = substituteVars(e.rhs, subst)

## Declare SMT variables for both unprimed and primed sets.
proc declareSmtVarsWithPrimes(
  vars: seq[string], primeSuffix: string
): string {.raises: [].} =
  var seen = initTable[string, bool]()
  var lines: seq[string] = @[]
  for v in vars:
    if not seen.hasKey(v):
      seen[v] = true
      lines.add("(declare-const " & v & " Int)")
      lines.add("(declare-const " & v & primeSuffix & " Int)")
  lines.join("\n")

## Extract loop body transitions from successor blocks of the loop header.
## Scans for "assignment" nodes in CFG successor blocks and extracts
## (lhs_name, rhs_SymSExpr) pairs using tree-sitter field access.
proc extractLoopBodyTransitions(
  cfg: ControlFlowGraph;
  headerId: int
): seq[(string, SymSExpr)] {.raises: [].} =
  let headerBlock = cfg.blockById.getOrDefault(headerId)
  for succId in headerBlock.successors:
    if succId >= 0 and succId < cfg.blocks.len:
      for stmt in cfg.blocks[succId].statements:
        if stmt.isNil or stmt.kind != nkAsgn:
          continue
        var leftNode: PNode = nil
        var rightNode: PNode = nil
        if stmt.len > 0 and not stmt[0].isNil: leftNode = stmt[0]
        if stmt.len > 1 and not stmt[1].isNil: rightNode = stmt[1]
        if leftNode.isNil or rightNode.isNil:
          continue
        let lhsName = extractIdentifierNameP(leftNode)
        if lhsName.len == 0:
          continue
        let rhsRes = nimExprToSymSExprP(rightNode)
        if rhsRes.isOk:
          result.add((lhsName, rhsRes.get))

## Build preservation SMT query: I(s) ∧ T(s,s') ∧ ¬I(s')
## This checks whether the candidate invariant is preserved across one
## iteration of the loop body. For each variable, the transition relation
## encodes either the detected loop body assignment or identity (no change).
proc buildPreservationSmtQuery(
  candidate: SymSExpr;
  transitions: seq[(string, SymSExpr)];
  extraAsserts: seq[string];
  primeSuffix: string = "'"
): string {.raises: [].} =
  let candidateVars = sExprVariables(candidate)

  # Build primed substitution map
  var primeMap = initTable[string, string]()
  for v in candidateVars:
    primeMap[v] = v & primeSuffix

  # I(s') — candidate with primed variables
  let candidatePrime = substituteVars(candidate, primeMap)

  # Build transition relation: for each variable, either detected assignment or identity
  var transitionParts: seq[string] = @[]
  for v in candidateVars:
    let vPrime = v & primeSuffix
    var found = false
    for (lhs, rhs) in transitions:
      if lhs == v:
        # v' = rhs (where rhs uses unprimed current-state variables)
        transitionParts.add(
          "(= " & vPrime & " " & sExprToString(rhs) & ")"
        )
        found = true
        break
    if not found:
      # No assignment detected: v' = v (unchanged)
      transitionParts.add("(= " & vPrime & " " & v & ")")

  var parts: seq[string] = @[]
  # Declare all variables (both unprimed and primed)
  parts.add(declareSmtVarsWithPrimes(candidateVars, primeSuffix))
  # I(s)
  parts.add("(assert " & sExprToString(candidate) & ")")
  # T(s,s')
  if transitionParts.len > 0:
    if transitionParts.len == 1:
      parts.add("(assert " & transitionParts[0] & ")")
    else:
      parts.add("(assert (and " & transitionParts.join(" ") & "))")
  # ¬I(s')
  parts.add("(assert (not " & sExprToString(candidatePrime) & "))")
  # Extra assertions (initiation context)
  for ea in extraAsserts:
    if ea.len > 0:
      parts.add(ea)
  parts.add("(check-sat)")
  result = parts.join("\n")

## Synthesize Loop Invariant.
proc synthesizeLoopInvariant*(
  cfg: ControlFlowGraph;
  headerId: int;
  z3Check: proc(query: string): bool {.closure, gcsafe, raises: [CatchableError].};
  layer1Candidates: seq[SymSExpr] = @[];
  initAsserts: seq[string] = @[]
): Option[SymSExpr] {.raises: [CatchableError], axiom: ["(assert (and presOk (= (str.len varNames) 0) (not (= v w)) (>= candidates 0) (>= varNames 0) (>= presOk 0) (>= layer1Candidates 0) (>= initOk 0) (forall ((initAssertsIdx Int)) (=> (and (>= initAssertsIdx 0) (< initAssertsIdx (seq.len initAsserts))) (>= (str.len (seq.nth initAsserts initAssertsIdx)) 0)))))", "presOk ∧ varNames.length = 0 ∧ v ≠ w ∧ (candidates ≥ 0) ∧ (varNames ≥ 0) ∧ (presOk ≥ 0) ∧ (layer1Candidates ≥ 0) ∧ (initOk ≥ 0) ∧ (∀ (initAssertsIdx : Fin initAsserts.size), (initAsserts.get initAssertsIdx).length ≥ 0)"].} =
  ## Phase 5: Context-aware loop invariant synthesis.
  ## Layer 1 candidates (from abstract interpretation) are checked first.
  ## Initiation assertions from abstract context are injected into Z3 queries.
  ## Uses an ordered template candidate set if Layer 1 proves insufficient.
  ##
  ## Preservation check encodes I(s) ∧ T(s,s') ⊨ I(s') using primed
  ## variables and transition relations extracted from the loop body.

  # Extract loop body transitions once for reuse
  let transitions = extractLoopBodyTransitions(cfg, headerId)

  # Phase 5: Check Layer 1 candidates first (abstract interpretation confirmed)
  for candidate in layer1Candidates:
    var initOk = false
    var presOk = false
    try:
      let initQuery = buildSmtQueryForCheck(sTrue(), candidate, initAsserts)
      initOk = z3Check(initQuery)
    except CatchableError:
      continue
    if not initOk:
      continue
    try:
      # Preservation: I(s) ∧ T(s,s') ∧ ¬I(s')
      let presQuery = buildPreservationSmtQuery(candidate, transitions, initAsserts)
      presOk = z3Check(presQuery)
    except CatchableError:
      continue
    if presOk:
      return some(candidate)

  # Layer 2: Template-based synthesis with context injection
  let headerBlock = cfg.blockById.getOrDefault(headerId)
  var varNames: seq[string] = @[]
  for stmt in headerBlock.statements:
    let name = extractIdentifierNameP(stmt)
    if name.len > 0 and name notin varNames:
      varNames.add(name)

  for predId in headerBlock.predecessors:
    if predId >= 0 and predId < cfg.blocks.len:
      for stmt in cfg.blocks[predId].statements:
        let name = extractIdentifierNameP(stmt)
        if name.len > 0 and name notin varNames:
          varNames.add(name)

  for succId in headerBlock.successors:
    if succId >= 0 and succId < cfg.blocks.len:
      for stmt in cfg.blocks[succId].statements:
        let name = extractIdentifierNameP(stmt)
        if name.len > 0 and name notin varNames:
          varNames.add(name)

  if varNames.len == 0:
    return none(SymSExpr)

  var candidates: seq[SymSExpr] = @[]
  for v in varNames:
    candidates.add(sGe(sVar(v), sConst(0)))
    candidates.add(sLe(sVar(v), sConst(0)))
    candidates.add(sGt(sVar(v), sConst(0)))
    candidates.add(sLt(sVar(v), sConst(0)))
    candidates.add(sLe(sVar(v), sConst(1000000)))
    for w in varNames:
      if v != w:
        candidates.add(sLe(sVar(v), sVar(w)))
        candidates.add(sGe(sVar(v), sVar(w)))
        candidates.add(sLt(sVar(v), sVar(w)))

  for candidate in candidates:
    var initOk = false
    var presOk = false
    try:
      let initQuery = buildSmtQueryForCheck(sTrue(), candidate, initAsserts)
      initOk = z3Check(initQuery)
    except CatchableError:
      continue
    if not initOk:
      continue

    try:
      # Preservation: I(s) ∧ T(s,s') ∧ ¬I(s')
      let presQuery = buildPreservationSmtQuery(candidate, transitions, initAsserts)
      presOk = z3Check(presQuery)
    except CatchableError:
      continue
    if not presOk:
      continue

    return some(candidate)

  none(SymSExpr)
{.pop.}

