import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
import ../../core/trusted/axiom_pragmas
import core/integrity/refinement_types
import core/parsers/safe_parsers
import core/parsers/pnode_nav
import core/types/results
import core/symbolic/symbolic_types_expr
import std/options
import std/strutils
import std/tables
# ---------------------------------------------------------------------------
# Inference State
# ---------------------------------------------------------------------------

type
  InferenceState* = object
    env*: LiquidTypeEnv
    loopVars*: seq[string]      ## Variables involved in loops
    mutatedVars*: seq[string]   ## Variables mutated anywhere in the function

# ---------------------------------------------------------------------------
# Environment Query Utilities
# ---------------------------------------------------------------------------

## Get Refinement Type.
func getRefinementType*(state: InferenceState; varName: string): RefinementType {.raises: [], axiom: ["(assert (and (>= (seq.len state_loopVars) 0) (>= (seq.len state_mutatedVars) 0) (>= (str.len varName) 0)))", "state_loopVars.size ≥ 0 ∧ state_mutatedVars.size ≥ 0 ∧ varName.length ≥ 0"].} =
  if state.env.hasKey(varName):
    return state.env.getOrDefault(varName, rtUnknown())
  rtUnknown()

## Ha Refinement Type.
func hasRefinementType*(state: InferenceState; varName: string): bool {.raises: [], axiom: ["(assert (and (>= (seq.len state_loopVars) 0) (>= (seq.len state_mutatedVars) 0) (>= (str.len varName) 0)))", "state_loopVars.size ≥ 0 ∧ state_mutatedVars.size ≥ 0 ∧ varName.length ≥ 0"].} =
  state.env.hasKey(varName)

## Env To Json.
func envToJson*(state: InferenceState): string {.raises: [].} =
  var parts: seq[string] = @[]
  for k, v in state.env:
    parts.add("\"" & k & "\": \"" & refinementTypeToString(v) & "\"")
  result = "{" & parts.join(", ") & "}"

## Env To Invariant Candidates.
func envToInvariantCandidates*(state: InferenceState): seq[SymSExpr] {.raises: [], axiom: ["(assert (and (>= (seq.len state_loopVars) 0) (>= (seq.len state_mutatedVars) 0)))", "state_loopVars.size ≥ 0 ∧ state_mutatedVars.size ≥ 0"].} =
  ## Converts inferred liquid predicates into concrete loop invariant candidates.
  var seen: seq[string] = @[]
  for varName, rt in state.env:
    if rt.predicate.isNil or rt.predicate.kind == seTrue:
      continue
    let candidate = substituteVarInPredicate(rt.predicate, varName)
    if candidate.isNil or candidate.kind == seTrue:
      continue
    let key = sExprToString(candidate)
    if key.len > 0 and key notin seen:
      seen.add(key)
      result.add(candidate)

## Env To Liquid Smt Asserts.
func envToLiquidSmtAsserts*(state: InferenceState): seq[string] {.raises: [], axiom: ["(assert (and (>= (seq.len state_loopVars) 0) (>= (seq.len state_mutatedVars) 0)))", "state_loopVars.size ≥ 0 ∧ state_mutatedVars.size ≥ 0"].} =
  ## Converts inferred liquid predicates into SMT context assertions.
  envToSmtAsserts(state.env)


# ── PNode Liquid Type Inference (post-XmlNode era; legacy equivalent) ──

import compiler/[ast, idents]

func extractIntValueP(node: PNode): Option[int] {.raises: [].} =
  if node.isNil: return none(int)
  case node.kind
  of nkIntLit, nkInt8Lit, nkInt16Lit, nkInt32Lit, nkInt64Lit, nkUIntLit, nkUInt8Lit, nkUInt16Lit, nkUInt32Lit, nkUInt64Lit:
    let parsed = safeParseInt($node.intVal)
    if parsed.isOk: return some(parsed.get)
  else:
    for child in node:
      if child.isNil: continue
      case child.kind
      of nkIntLit, nkInt8Lit, nkInt16Lit, nkInt32Lit, nkInt64Lit, nkUIntLit, nkUInt8Lit, nkUInt16Lit, nkUInt32Lit, nkUInt64Lit:
        let parsed = safeParseInt($child.intVal)
        if parsed.isOk: return some(parsed.get)
      else: discard
  none(int)

func extractVarNameP(node: PNode): string {.raises: [].} =
  if node.isNil: return ""
  case node.kind
  of nkIdent:
    return node.ident.s
  else:
    for child in node:
      if child.isNil: continue
      if child.kind == nkIdent:
        let t = child.ident.s
        if t.len > 0: return t
  ""

func inferLiquidTypeEnvP*(fnNode: PNode): InferenceState {.raises: [], axiom: ["(assert ast_parse_failed_isolated)", "ast_parse_failed_isolated"].} =
  ## Scans a function AST (PNode) and infers refinement types for all variables.
  ## PNode equivalent of legacy XmlNode-based inferLiquidTypeEnv.
  result.env = initTable[string, RefinementType]()
  result.loopVars = @[]
  result.mutatedVars = @[]

  if fnNode.isNil:
    return result

  # Determine the body node from proc/func definition
  var bodyNode: PNode = nil
  case fnNode.kind
  of nkProcDef, nkFuncDef, nkMethodDef, nkIteratorDef, nkConverterDef, nkMacroDef, nkTemplateDef:
    for child in fnNode:
      if child.isNil: continue
      if child.kind in {nkStmtList, nkBlockStmt, nkBlockExpr}:
        bodyNode = child
        break
  else:
    bodyNode = fnNode

  if bodyNode.isNil:
    return result

  # Pass 1: Collect all variable declarations and initial values
  func collectDeclarationsP(node: PNode; state: var InferenceState) {.raises: [], axiom: ["(assert (and (>= (seq.len state_loopVars) 0) (>= (seq.len state_mutatedVars) 0) (= (str.len name) 0) (= (option.isSome valOpt) true) (>= valueNode 0) (>= node 0) (>= child 0)))", "state_loopVars.size ≥ 0 ∧ state_mutatedVars.size ≥ 0 ∧ name.length = 0 ∧ valOpt.isSome = true ∧ (valueNode ≥ 0) ∧ (node ≥ 0) ∧ (child ≥ 0)"].} =
    if node.isNil: return

    case node.kind
    of nkVarSection, nkLetSection:
      for child in node:
        if child.isNil or child.kind != nkIdentDefs: continue
        var nameNode: PNode = nil
        var valueNode: PNode = nil
        # nkIdentDefs: [idents..., type?, expr?]
        var hasType = false
        for c in child:
          if c.isNil: continue
          if not hasType and c.kind == nkSym:
            # Symbol reference (type)
            hasType = true
            continue
          if not hasType:
            # First non-type child is identifier list start
            nameNode = c
          elif valueNode.isNil:
            # After identifiers and type, next is the expression
            valueNode = c
        if nameNode.isNil: continue
        let name = extractVarNameP(nameNode)
        if name.len == 0: continue
        if valueNode.isNil:
          state.env[name] = rtInt(sEq(sVar("v"), sConst(0)))
        else:
          let valOpt = extractIntValueP(valueNode)
          if valOpt.isSome:
            state.env[name] = rtInt(sEq(sVar("v"), sConst(valOpt.get)))
          else:
            state.env[name] = rtNat()

    of nkAsgn:
      if node.len > 0 and not node[0].isNil:
        let name = extractVarNameP(node[0])
        if name.len > 0 and name notin state.mutatedVars:
          state.mutatedVars.add(name)

    of nkForStmt, nkWhileStmt:
      var varName = ""
      case node.kind
      of nkForStmt:
        # nkForStmt: [varNames..., expr, body]
        if node.len > 0 and not node[0].isNil and node[0].kind == nkIdent:
          varName = node[0].ident.s
      of nkWhileStmt:
        # nkWhileStmt: [condition, body] — no iterator var
        discard
      else: discard
      if varName.len > 0 and varName notin state.loopVars:
        state.loopVars.add(varName)

    else:
      discard

    # Recurse into children
    for child in node:
      if child.isNil: continue
      collectDeclarationsP(child, state)

  collectDeclarationsP(bodyNode, result)

  # Pass 2: Widen exact constants to bounds for loop variables
  for v in result.loopVars:
    if not result.env.hasKey(v):
      result.env[v] = rtNat()
      continue
    let rt = result.env.getOrDefault(v, rtNat())
    if rt.predicate.kind == seEq:
      if rt.predicate.lhs != nil and rt.predicate.lhs.kind == seVar and rt.predicate.lhs.name == "v":
        if rt.predicate.rhs != nil and rt.predicate.rhs.kind == seConst and rt.predicate.rhs.intValue == 0:
          result.env[v] = rtNat()

  # Pass 3: Add upper bounds from loop conditions
  func addLoopBoundsP(node: PNode; state: var InferenceState) {.raises: [], axiom: ["(assert (and (>= (seq.len state_loopVars) 0) (>= (seq.len state_mutatedVars) 0) (>= node 0) (>= upperBound 0)))", "state_loopVars.size ≥ 0 ∧ state_mutatedVars.size ≥ 0 ∧ (node ≥ 0) ∧ (upperBound ≥ 0)"].} =
    if node.isNil: return

    if node.kind in {nkForStmt, nkWhileStmt}:
      var varName = ""
      var opText = ""
      var boundExpr = ""

      case node.kind
      of nkForStmt:
        # nkForStmt: [varNames..., expr, body]
        if node.len > 0 and not node[0].isNil and node[0].kind == nkIdent:
          varName = node[0].ident.s
        # Extract range from expr (second-to-last meaningful child before body)
        if node.len >= 3:
          for i in countdown(node.len - 2, 1):
            if not node[i].isNil and node[i].kind != nkStmtList and node[i].kind != nkBlockStmt:
              let expr = node[i]
              if expr.kind == nkInfix and expr.len >= 3:
                opText = pNodeText(expr[1]).strip().toLowerAscii()
                let right = expr[2]
                if right.isNil: discard
                elif right.kind == nkIdent:
                  boundExpr = right.ident.s
                else:
                  boundExpr = pNodeText(right)
              break

      of nkWhileStmt:
        # nkWhileStmt: [condition, body]
        if node.len > 0 and not node[0].isNil:
          let cond = node[0]
          if cond.kind == nkInfix and cond.len >= 3:
            opText = pNodeText(cond[1]).strip().toLowerAscii()
            let right = cond[2]
            if right.isNil: discard
            elif right.kind == nkIdent:
              boundExpr = right.ident.s
            else:
              boundExpr = pNodeText(right)

      else: discard

      if varName.len > 0 and opText.len > 0:
        if not state.env.hasKey(varName):
          state.env[varName] = rtNat()
        let currentRt = state.env.getOrDefault(varName, rtNat())
        var upperBound: SymSExpr = nil
        case opText
        of "<":
          if boundExpr.len > 0:
            upperBound = sLt(sVar("v"), sVar(boundExpr))
          else:
            upperBound = sLt(sVar("v"), sConst(1000000))
        of "<=":
          if boundExpr.len > 0:
            upperBound = sLe(sVar("v"), sVar(boundExpr))
          else:
            upperBound = sLe(sVar("v"), sConst(1000000))
        else:
          discard

        if not upperBound.isNil:
          if currentRt.predicate.kind == seTrue:
            state.env[varName] = rtInt(upperBound)
          elif currentRt.predicate.kind == seGe:
            state.env[varName] = rtInt(sAnd(currentRt.predicate, upperBound))
          else:
            state.env[varName] = rtInt(sAnd(currentRt.predicate, upperBound))

    for child in node:
      if child.isNil: continue
      addLoopBoundsP(child, state)

  addLoopBoundsP(bodyNode, result)

  # Pass 4: Any mutated variable that isn't a loop var gets non-negative if int
  for v in result.mutatedVars:
    if not result.env.hasKey(v):
      result.env[v] = rtNat()

{.pop.}
