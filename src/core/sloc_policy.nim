import core/trusted/layer_declaration
import core/trusted/axiom_pragmas_lite
import core/results
import std/[options, sets, strutils]
import compiler/[ast, idents]
axiomLayer "domain"
{.push raises: [].}

## SLOC Policy SSOT (WS-P2-B)
## Single source of truth for EffectiveSLOC algorithm and policy version strings.
## All engine, ratify, test, and CI consumers MUST import this module
## instead of re-declaring version strings.

const EffectiveSlocAlgorithmVersion* = "pnode-effective-source-span-v1"
const EffectiveSlocPolicyVersion*   = "effective-sloc-policy-v1"

func maxSourceLine*(n: PNode): int {.raises: [].} =
  if n.isNil:
    return 0
  result = n.info.line.int
  for i in 0 ..< n.safeLen:
    let c = maxSourceLine(n[i])
    if c > result:
      result = c

type
  DefineContext* = object
    knownDefined*:   HashSet[string]
    knownUndefined*: HashSet[string]

  WhenContext* = object
    defines*:         DefineContext
    targetOS*:        Option[string]
    targetCPU*:       Option[string]
    compileOptions*:  HashSet[string]

  WhenCondition* = enum
    whenTrue
    whenFalse
    whenUnknown

  UnknownReason* = enum
    urMissingSemanticContext
    urUnsupportedExpr
    urTypeDependent
    urMacroDependent

const nkHiddenKinds* = {nkHiddenCallConv, nkHiddenStdConv, nkHiddenSubConv,
                           nkHiddenAddr, nkHiddenDeref, nkHiddenTryStmt}

func evalWhenConditionAST*(n: PNode): Option[bool] {.raises: [], axiomDecision(
  id = "DECISION-0005",
  reason = "Tier1 pure constant-expression evaluation of when conditions without semantic context; policy version: " & EffectiveSlocPolicyVersion,
  adr = "docs/spec/effective_sloc.md",
  introduced = "v9"
).} =
  ## Tier1: pure constant expression evaluation without semantic context.
  ## Returns some(true/false) for decidable conditions, none() otherwise.
  if n.kind == nkIdent:
    if n.ident.s == "true":
      return some(true)
    if n.ident.s == "false":
      return some(false)
  if n.kind == nkInfix and n.safeLen >= 3:
    let op = n[0]
    if op.kind == nkIdent and (op.ident.s == "==" or op.ident.s == "!="):
      let left = n[1]
      let right = n[2]
      if left.kind in nkIntLit..nkUInt64Lit and right.kind in nkIntLit..nkUInt64Lit:
        let lv = left.intVal
        let rv = right.intVal
        if op.ident.s == "==":
          return some(lv == rv)
        else:
          return some(lv != rv)
  none(bool)

func evalWhenConditionCtx*(n: PNode; ctx: WhenContext): Option[bool] {.raises: [], axiomDecision(
  id = "DECISION-0006",
  reason = "Tier2 declarative WhenContext-based evaluation of defined() in when conditions; policy version: " & EffectiveSlocPolicyVersion,
  adr = "docs/spec/effective_sloc.md",
  introduced = "v9"
).} =
  ## Tier2: declarative WhenContext-based evaluation.
  ## Membership matching only — no compiler semantic modules.
  ## defined(X) in knownDefined → true, knownUndefined → false, else → none (Unknown).
  if n.kind == nkCall and n.safeLen >= 2:
    let funcNode = n[0]
    if funcNode.kind == nkIdent and funcNode.ident.s == "defined":
      let arg = n[1]
      if arg.kind == nkIdent:
        let name = arg.ident.s
        if name in ctx.defines.knownDefined:
          return some(true)
        if name in ctx.defines.knownUndefined:
          return some(false)
        return none(bool)
  none(bool)

func evalWhen*(n: PNode; ctx: WhenContext): WhenCondition {.raises: [].} =
  ## Combined Tier1 → Tier2 → Unknown evaluation for when-conditions.
  let tier1 = evalWhenConditionAST(n)
  if tier1.isSome:
    if tier1.get: return whenTrue
    else: return whenFalse
  let tier2 = evalWhenConditionCtx(n, ctx)
  if tier2.isSome:
    if tier2.get: return whenTrue
    else: return whenFalse
  whenUnknown

proc extractEffectiveSourceSpansCtx*(n: PNode; ctx: WhenContext): Result[seq[(int, int)], UnknownReason] {.raises: [], axiomDecision(
  id = "DECISION-0007",
  reason = "Source-oriented span extraction with WhenContext-aware branch selection for EffectiveSLOC; policy version: " & EffectiveSlocPolicyVersion,
  adr = "docs/spec/effective_sloc.md",
  introduced = "v9"
).} =
  ## Source-oriented span extraction with WhenContext-aware branch selection.
  ## nkWhenStmt: only active branches are included; unknown condition → err.
  ## All other nodes: same traversal as extractEffectiveSourceSpans.
  if n.isNil:
    return ok(newSeq[(int, int)]())
  if n.info.line == 0:
    var acc: seq[(int, int)]
    for i in 0 ..< n.safeLen:
      let r = extractEffectiveSourceSpansCtx(n[i], ctx)
      if r.isErr: return err(r.error)
      acc.add(r.get)
    return ok(acc)
  if n.kind == nkCommentStmt:
    return ok(newSeq[(int, int)]())
  if n.kind == nkEmpty:
    var acc: seq[(int, int)]
    for i in 0 ..< n.safeLen:
      let r = extractEffectiveSourceSpansCtx(n[i], ctx)
      if r.isErr: return err(r.error)
      acc.add(r.get)
    return ok(acc)
  case n.kind
  of nkHiddenKinds:
    var acc: seq[(int, int)]
    for i in 0 ..< n.safeLen:
      let r = extractEffectiveSourceSpansCtx(n[i], ctx)
      if r.isErr: return err(r.error)
      acc.add(r.get)
    return ok(acc)
  of nkStmtList, nkStmtListExpr, nkBlockStmt, nkBlockExpr,
     nkStmtListType, nkBlockType, nkProcDef, nkFuncDef,
     nkTemplateDef, nkMacroDef, nkMethodDef, nkConverterDef,
     nkIteratorDef:
    var acc: seq[(int, int)]
    for i in 0 ..< n.safeLen:
      let r = extractEffectiveSourceSpansCtx(n[i], ctx)
      if r.isErr: return err(r.error)
      acc.add(r.get)
    return ok(acc)
  of nkWhenStmt:
    var acc: seq[(int, int)]
    var activeBranchFound = false
    for i in 0 ..< n.safeLen:
      let branch = n[i]
      if branch.kind == nkElifBranch:
        if branch.safeLen < 2:
          continue
        let cond = branch[0]
        let body = branch[1]
        let evalResult = evalWhen(cond, ctx)
        case evalResult
        of whenTrue:
          activeBranchFound = true
          let rCond = extractEffectiveSourceSpansCtx(cond, ctx)
          if rCond.isErr: return err(rCond.error)
          acc.add(rCond.get)
          let rBody = extractEffectiveSourceSpansCtx(body, ctx)
          if rBody.isErr: return err(rBody.error)
          acc.add(rBody.get)
        of whenFalse:
          discard
        of whenUnknown:
          return err(urMissingSemanticContext)
      elif branch.kind == nkElse:
        if activeBranchFound:
          continue
        if branch.safeLen < 1:
          continue
        let body = branch[0]
        let r = extractEffectiveSourceSpansCtx(body, ctx)
        if r.isErr: return err(r.error)
        acc.add(r.get)
      else:
        let r = extractEffectiveSourceSpansCtx(branch, ctx)
        if r.isErr: return err(r.error)
        acc.add(r.get)
    return ok(acc)
  of nkIfStmt, nkCaseStmt, nkTryStmt:
    var acc: seq[(int, int)]
    for i in 0 ..< n.safeLen:
      let r = extractEffectiveSourceSpansCtx(n[i], ctx)
      if r.isErr: return err(r.error)
      acc.add(r.get)
    return ok(acc)
  else: discard
  let startLine = n.info.line.int
  let endLine = if n.kind in {nkStrLit, nkTripleStrLit}:
                  startLine + n.strVal.splitLines().len
                else:
                  maxSourceLine(n)
  var acc: seq[(int, int)]
  if endLine > 0:
    acc.add (startLine, endLine)
  for i in 0 ..< n.safeLen:
    let r = extractEffectiveSourceSpansCtx(n[i], ctx)
    if r.isErr: return err(r.error)
    acc.add(r.get)
  ok(acc)

{.pop.}