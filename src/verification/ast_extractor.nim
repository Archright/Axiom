import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

import std/locks
import std/sequtils
import std/sets
import std/tables
import compiler/ast
import core/parser_utils
import core/parsers/pnode_nav
import core/results as res
import ../core/trusted/axiom_pragmas
# axiomIoBoundary

type
  AstCacheManager = object
    ast: Table[string, PNode]
    index: Table[string, Table[string, PNode]]
    gate: Lock
    gateReady: bool

var astCacheImpl: AstCacheManager

## axiom-smt: (assert (>= depth 0))
## axiom-lean: depth >= 0
proc ensureAstCacheInit() {.axiom, axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if not astCacheImpl.gateReady:
    try:
      initLock(astCacheImpl.gate)
      astCacheImpl.gateReady = true
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)

proc getOrParseAstUnlocked(source: string): Result[PNode, string] {.raises: [], axiom: ["(assert (and (>= (str.len source) 0) ast_parse_failed_isolated (>= (str.len source) 0)))", "source.length ≥ 0 ∧ ast_parse_failed_isolated ∧ source.length ≥ 0"], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if astCacheImpl.ast.hasKey(source):
    return ok(astCacheImpl.ast.getOrDefault(source))
  try:
    result = ok(parseStringAST(source))
  except CatchableError as e:
    result = err(e.msg)
  if result.isOk:
    discard astCacheImpl.ast.hasKeyOrPut(source, res.get(result))

## Get Cached Nim Ast.
proc getCachedNimAst*(source: string): Result[PNode, string] {.raises: [], axiom: ["(assert ast_parse_failed_isolated)", "ast_parse_failed_isolated"], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ensureAstCacheInit()
  acquire(astCacheImpl.gate)
  defer:
    release(astCacheImpl.gate)
  getOrParseAstUnlocked(source)

## Get Cached Function Node Index.
proc getCachedFunctionNodeIndex*(source: string): Result[Table[string, PNode], string] {.raises: [], axiom: ["(assert ast_parse_failed_isolated)", "ast_parse_failed_isolated"], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ensureAstCacheInit()
  acquire(astCacheImpl.gate)
  defer:
    release(astCacheImpl.gate)
  if astCacheImpl.index.hasKey(source):
    return ok(astCacheImpl.index.getOrDefault(source))
  let astRes = getOrParseAstUnlocked(source)
  if not astRes.isOk:
    return err(astRes.error)
  let ast = res.get(astRes)
  try:
    result = ok(indexFunctionNodesP(ast))
  except CatchableError as e:
    result = err(e.msg)
  if result.isOk:
    discard astCacheImpl.index.hasKeyOrPut(source, res.get(result))

## Collect Module Functions.
proc collectModuleFunctions*(source: string): Result[HashSet[string], string] {.raises: [], axiom: ["(assert (and (>= (str.len source) 0) (>= result 0)))", "source.length ≥ 0 ∧ (result ≥ 0)"], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  result = ok(initHashSet[string]())
  let indexRes = getCachedFunctionNodeIndex(source)
  if not indexRes.isOk:
    return err(indexRes.error)
  let index = res.get(indexRes)
  for name in index.keys:
    result.value.incl(name)

## Collect Global Symbols.
proc collectGlobalSymbols*(source: string): Result[HashSet[string], string] {.raises: [], axiom: ["(assert (and (>= (str.len source) 0) (= (option.isSome nameNodeOpt) true) (> (str.len name) 0) (>= result 0)))", "source.length ≥ 0 ∧ nameNodeOpt.isSome = true ∧ name.length > 0 ∧ (result ≥ 0)"], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  result = ok(initHashSet[string]())
  let astRes = getCachedNimAst(source)
  if not astRes.isOk:
    return err(astRes.error)
  let ast = res.get(astRes)
  for section in findNodesP(ast, DeclarationSectionKinds):
    for id in findNodesP(section, {nkIdent, nkSym}):
      let nm = pNodeText(id)
      if nm.len > 0:
        result.value.incl(nm)

## Extract Function Body.
proc extractFunctionBody*(source: string; functionName: string): Result[tuple[found: bool; body: string], string] {.raises: [], axiom: ["(assert (and (>= (str.len source) 0) (>= (str.len functionName) 0) (or (< row 0) (>= row (str.len lines))) (>= result 0)))", "source.length ≥ 0 ∧ functionName.length ≥ 0 ∧ row < 0 ∨ row ≥ lines.length ∧ (result ≥ 0)"], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  result = ok((false, ""))
  let indexRes = getCachedFunctionNodeIndex(source)
  if not indexRes.isOk:
    return err(indexRes.error)
  let index = res.get(indexRes)
  if not index.hasKey(functionName):
    return
  let fnNode = index.getOrDefault(functionName)
  ## Find body node via statement block child (Nim AST: proc def → first nkStmtList/nkBlockStmt).
  for child in fnNode:
    if not child.isNil and child.kind in {nkStmtList, nkBlockStmt, nkBlockExpr}:
      result = ok((true, pNodeText(child)))
      return
  result = ok((true, ""))

## Infer Calls From Body.
## axiom-smt: (assert (and (>= callNames 0)))
## axiom-lean: (callNames ≥ 0)
func inferCallsFromBody*(fnNode: PNode; knownFunctions: HashSet[string]; selfName: string): seq[string] {.axiomTryImpl.} =
  let callNames = collectCallIdentifiersP(fnNode)
  for name in callNames:
    if name != selfName and name in knownFunctions:
      result.add(name)
  result.deduplicate()

## Infer Accessed Resources From Body.
## axiom-smt: (assert (and (>= dotNames 0)))
## axiom-lean: (dotNames ≥ 0)
func inferAccessedResourcesFromBody*(fnNode: PNode; moduleGlobals: HashSet[string]; selfName: string): seq[string] {.axiomTryImpl.} =
  let dotNames = collectDotExpressionsP(fnNode)
  for name in dotNames:
    if name != selfName and name in moduleGlobals:
      result.add(name)
  result.deduplicate()
{.pop.}
