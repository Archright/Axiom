import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## Boundary Extraction Main
## Path condition extraction, information gain computation, and refactoring hints.
##
## Extracted from boundary_extraction_core_part2.nim (include-based) into a proper module.

import std/strutils
import std/sets
import std/times
import std/json
import std/options
import std/math

import compiler/ast
import core/interfaces/logging_hub
import core/parsers/pnode_nav
import core/parsers/safe_parsers
import core/types/results

import core/type_system/liquid_inference
import core/symbolic/symbolic_types_expr
import core/types/symbolic_types_lean
import core/boundary/complexity_index

import core/boundary/boundary_extraction_types
import core/boundary/boundary_extraction_helpers
import core/axiom_pragmas

# ── Path Condition Extraction ──

type PathCondition = tuple[smt: string, lean: string]

func addUniquePathCondition(
  outConditions: var seq[PathCondition];
  seen: var HashSet[string];
  condition: PathCondition
) {.raises: [], noSideEffect.} =
  if condition.smt.len == 0 or seen.contains(condition.smt):
    return
  seen.incl(condition.smt)
  outConditions.add(condition)

proc addConvertedPathCondition(
  outConditions: var seq[PathCondition];
  seen: var HashSet[string];
  node: PNode
) {.raises: [].} =
  addUniquePathCondition(outConditions, seen, convertExpressionToSmtLean(node))

proc collectControlFlowConditions(
  fnNode: PNode;
  outConditions: var seq[PathCondition];
  seen: var HashSet[string]
) {.raises: [].} =
  for ifNode in findNodesP(fnNode, {nkIfStmt}):
    let condOpt = nodeFieldP(ifNode, "left")
    if condOpt.isSome:
      addConvertedPathCondition(outConditions, seen, condOpt.get())
    for elifNode in findNodesP(fnNode, {nkOfBranch}):
      let elifCondOpt = nodeFieldP(elifNode, "left")
      if elifCondOpt.isSome:
        addConvertedPathCondition(outConditions, seen, elifCondOpt.get())

  for whileNode in findNodesP(fnNode, {nkWhileStmt}):
    let condOpt = nodeFieldP(whileNode, "left")
    if condOpt.isSome:
      addConvertedPathCondition(outConditions, seen, condOpt.get())

  for caseNode in findNodesP(fnNode, {nkCaseStmt}):
    for ofBranch in findNodesP(caseNode, {nkOfBranch}):
      let valuesOpt = nodeFieldP(ofBranch, "right")
      if valuesOpt.isNone:
        continue
      for value in childElements(valuesOpt.get()):
        addConvertedPathCondition(outConditions, seen, value)

  for forNode in findNodesP(fnNode, {nkForStmt}):
    for rn in findNodesP(forNode, {nkInfix}):
      let lhs = findNodesP(rn, {nkIntLit, nkInt8Lit, nkInt16Lit, nkInt32Lit, nkInt64Lit})
      if lhs.len == 0:
        continue
      let lower = pNodeText(lhs[0])
      addUniquePathCondition(
        outConditions,
        seen,
        (smt: "(>= i " & lower & ")", lean: "i >= " & lower)
      )

proc collectAssignmentConditions(
  fnNode: PNode;
  outConditions: var seq[PathCondition];
  seen: var HashSet[string]
) {.raises: [].} =
  for assignNode in findNodesMultiTag(fnNode, ["assignment", "asgn"]):
    let leftOpt = nodeFieldP(assignNode, "left")
    let rightOpt = nodeFieldP(assignNode, "right")
    if leftOpt.isNone or rightOpt.isNone:
      continue
    let left = convertExpressionToSmtLean(leftOpt.get())
    let right = convertExpressionToSmtLean(rightOpt.get())
    if left.smt.len == 0 or right.smt.len == 0:
      continue
    addUniquePathCondition(
      outConditions,
      seen,
      (smt: "(= " & left.smt & " " & right.smt & ")",
       lean: left.lean & " = " & right.lean)
    )

proc collectAssertConditions(
  fnNode: PNode;
  outConditions: var seq[PathCondition];
  seen: var HashSet[string]
) {.raises: [].} =
  for callNode in findNodesMultiTag(fnNode, ["call", "call_expression"]):
    let funcOpt = nodeFieldP(callNode, "function")
    if funcOpt.isNone:
      continue
    if pNodeText(funcOpt.get()) notin ["assert", "doAssert"]:
      continue
    var argsOpt = nodeFieldP(callNode, "arguments")
    if argsOpt.isNone:
      for child in childElements(callNode):
        if isPNodeElement(child) and child.kind == nkPar:
          argsOpt = some(child)
          break
    if argsOpt.isNone:
      continue
    for arg in childElements(argsOpt.get()):
      addConvertedPathCondition(outConditions, seen, arg)

proc collectReturnConditions(
  fnNode: PNode;
  outConditions: var seq[PathCondition];
  seen: var HashSet[string]
) {.raises: [].} =
  for retNode in findNodesMultiTag(fnNode, ["return_statement", "return"]):
    for child in childElements(retNode):
      if not isPNodeElement(child):
        continue
      addConvertedPathCondition(outConditions, seen, child)

proc collectConditionalReturnConditions(
  fnNode: PNode;
  outConditions: var seq[PathCondition];
  seen: var HashSet[string]
) {.raises: [].} =
  for ifNode in findNodesP(fnNode, {nkIfStmt}):
    let condOpt = nodeFieldP(ifNode, "left")
    if condOpt.isNone:
      continue
    let cond = convertExpressionToSmtLean(condOpt.get())
    if cond.smt.len == 0:
      continue

    let thenOpt = nodeFieldP(ifNode, "consequence")
    if thenOpt.isSome:
      for retNode in findNodesP(thenOpt.get(), {nkReturnStmt}):
        for child in childElements(retNode):
          if not isPNodeElement(child):
            continue
          let val = convertExpressionToSmtLean(child)
          if val.smt.len == 0:
            continue
          addUniquePathCondition(
            outConditions,
            seen,
            (smt: "(=> " & cond.smt & " (= result " & val.smt & "))",
             lean: cond.lean & " → result = " & val.lean)
          )

    let elseOpt = nodeFieldP(ifNode, "alternative")
    if elseOpt.isSome:
      for retNode in findNodesP(elseOpt.get(), {nkReturnStmt}):
        for child in childElements(retNode):
          if not isPNodeElement(child):
            continue
          let val = convertExpressionToSmtLean(child)
          if val.smt.len == 0:
            continue
          let negCondSmt = "(not " & cond.smt & ")"
          let negCondLean = "¬" & cond.lean
          addUniquePathCondition(
            outConditions,
            seen,
            (smt: "(=> " & negCondSmt & " (= result " & val.smt & "))",
             lean: negCondLean & " → result = " & val.lean)
          )

func collectLiquidInvariantConditions(
  fnNode: PNode;
  outConditions: var seq[PathCondition];
  seen: var HashSet[string]
) {.raises: [], noSideEffect.} =
  let liquidState = inferLiquidTypeEnvP(fnNode)
  for inv in envToInvariantCandidates(liquidState):
    if inv.isNil or inv.kind == seTrue:
      continue
    let smt = sExprToString(inv)
    if smt.len == 0 or seen.contains(smt):
      continue
    let lean = sExprToLean(inv)
    if lean.len == 0:
      continue
    seen.incl(smt)
    outConditions.add((smt: smt, lean: lean))

func isSelfEqualityConstraint(smt: string; lean: string): bool {.noSideEffect.} =
  ## Algebraic Significance Guard: detect self-equality with zero information gain.
  ## Filters patterns like "(= x x)" or "i = i" where no state transition occurs.
  let l = lean.strip()
  if l.contains(" = "):
    let parts = l.split(" = ")
    if parts.len >= 2:
      let left = parts[0].strip()
      let right = parts[1].strip()
      if left == right:
        return true
  let s = smt.strip()
  if s.contains("(= "):
    let startIdx = s.find("(= ")
    let endIdx = s.find(")", startIdx)
    if startIdx >= 0 and endIdx > startIdx:
      let inner = s[startIdx + 3 ..< endIdx].strip()
      let parts = inner.splitWhitespace()
      if parts.len >= 2 and parts[0] == parts[1]:
        return true
  false

func sanitizeLeanIdentifier*(ident: string): string {.raises: [].} =
  ## Replace dot (.) with underscore (_) to prevent Lean 4 namespace confusion.
  result = ident.replace(".", "_")

func sanitizePathCondition(cond: tuple[smt: string, lean: string]): tuple[smt: string, lean: string] {.raises: [].} =
  ## Namespace sanitization + Nat/Prop type mismatch guard.
  result.smt = cond.smt.replace(".", "_")
  result.lean = cond.lean.replace(".", "_")
  ## Remove trailing " ∧ 0" or " ∧ (0)" which creates Nat/Prop type mismatch in Lean.
  if result.lean.endsWith(" ∧ 0"):
    result.lean = result.lean[0 ..< result.lean.len - 4].strip()
  if result.lean.endsWith(" ∧ (0)"):
    result.lean = result.lean[0 ..< result.lean.len - 6].strip()
  if result.smt.endsWith(" (and 0)"):
    result.smt = result.smt[0 ..< result.smt.len - 8].strip()

proc extractPathConditions*(fnNode: PNode): seq[tuple[smt: string, lean: string]] {.raises: [].} =
  ## Extract symbolic path conditions from control-flow nodes in the AST.
  ## Phase 1 enhancement: SSA-style extraction covering assignments,
  ## assertions, return values, and control-flow conditions.
  if fnNode.isNil:
    return
  var seen: HashSet[string]
  collectControlFlowConditions(fnNode, result, seen)
  collectAssignmentConditions(fnNode, result, seen)
  collectAssertConditions(fnNode, result, seen)
  collectReturnConditions(fnNode, result, seen)
  collectConditionalReturnConditions(fnNode, result, seen)
  collectLiquidInvariantConditions(fnNode, result, seen)
  ## Algebraic Significance Guard: purge self-equality constraints with zero IG
  var filtered: seq[tuple[smt: string, lean: string]]
  for cond in result:
    if not isSelfEqualityConstraint(cond.smt, cond.lean):
      filtered.add(cond)
  result = filtered
  ## Namespace sanitization + type mismatch guard
  var sanitized: seq[tuple[smt: string, lean: string]]
  for cond in result:
    sanitized.add(sanitizePathCondition(cond))
  result = sanitized

# ── Information Gain ──

func computeInformationGain*(params: seq[ParamBoundary]; smtParts: seq[string]): float {.raises: [].} =
  ## Approximate information gain of boundary constraints.
  ## IG = H(D) - H(D | P), where H is estimated from parameter types.
  var domainEntropy = 0.0
  for p in params:
    let t = p.nimType.strip().toLowerAscii()
    if t == "bool":
      domainEntropy += 1.0
    elif t.startsWith("range["):
      let innerStart = t.find('[')
      let innerEnd = t.rfind(']')
      if innerStart >= 0 and innerEnd > innerStart:
        let inner = t[innerStart + 1 ..< innerEnd]
        let dots = inner.find("..")
        if dots >= 0:
          let lowerStr = inner[0 ..< dots].strip()
          let upperStr = inner[dots + 2 .. ^1].strip()
          let lower = safeParseFloat(lowerStr).getOrDefault(0.0)
          let upper = safeParseFloat(upperStr).getOrDefault(0.0)
          let size = upper - lower + 1
          if size > 0:
            domainEntropy += log2(size)
    elif t == "int" or t == "int64" or t == "int32" or t == "int16" or t == "int8":
      domainEntropy += 32.0
    elif t == "string" or t == "cstring" or t == "seq":
      domainEntropy += 64.0
    elif t == "float" or t == "float64" or t == "float32":
      domainEntropy += 64.0
    else:
      domainEntropy += 16.0

  var constraintStrength = 0.0
  for smt in smtParts:
    let s = smt.toLowerAscii()
    if s.contains("(= ") and not s.contains("(!=") and not s.contains("(and"):
      constraintStrength += 32.0
    elif s.contains("(and"):
      constraintStrength += 6.0
    elif s.contains("(>=" ) or s.contains("(<= "):
      constraintStrength += 1.0
    elif s.contains("(>") or s.contains("(<"):
      constraintStrength += 2.0

  let conditionalEntropy = max(0.0, domainEntropy - constraintStrength)
  result = max(0.0, domainEntropy - conditionalEntropy)

# ── Internal Helpers ──

# @axiom-hint: lean="base.length ≥ 0 ∧ params.size ≥ 0" smt="(assert (and (>= (str.len base) 0) (>= (seq.len params) 0)))"
# @axiom-hint: lean="ast_parse_failed_isolated" smt="(assert (and ast_parse_failed_isolated))"
func sequenceElementBinderName*(base: string; params: seq[ParamBoundary]): string {.noSideEffect.} =
  var existing: seq[string] = @[]
  for p in params:
    existing.add(p.name)
  result = base & "Idx"
  var suffix = 2
  while result in existing:
    result = base & "Idx" & $suffix
    inc suffix

proc logRefactorHint*(nodeId: string; aci: AxiomComplexity) {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Log a refactoring hint when SOLID hard gate blocks a function.
  try:
    let logFile = open("logs/solid_gate_rejected.jsonl", fmAppend)
    logFile.writeLine($(%*{
      "timestamp": now().utc.format("yyyy-MM-dd'T'HH:mm:ss'Z'"),
      "nodeId": nodeId,
      "aci": aci.total,
      "cyclomatic": aci.cyclomatic,
      "cognitive": aci.cognitive,
      "coupling": aci.coupling,
      "hint": "@axiom-refactor-hint: ACI=" & $aci.total & " M=" &
        $aci.cyclomatic & " C=" & $aci.cognitive & " S=" & $aci.coupling &
        ". Consider splitting into smaller functions."
    }))
    logFile.close()
  except CatchableError as e:
    logError("[boundary_extraction] Audit log write failure: " & e.msg) # axiom:best-effort(audit logging; zero correctness impact)

{.pop.}
