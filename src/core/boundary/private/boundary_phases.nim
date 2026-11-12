import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

import std/[options, strutils, math]
import core/boundary/private/boundary_context
import core/boundary/private/trivial_filter
import core/boundary/private/semantic_hint_factory
import core/boundary/boundary_extraction_types
import core/boundary/boundary_extraction_helpers
import core/boundary/boundary_extraction_main
import core/boundary/meta_extractor
import core/parsers/pnode_nav
import core/parser_utils    # for parseNimRes*
import compiler/ast
import core/types/results                # for isErr/get on custom Result
import core/types/hubs/semantic_hint_hub
import core/types/hubs/param_type_info_hub

# ── Function Definition Extraction (PNode-based) ──

type FuncDefInfo = tuple[name: string; returnType: string; params: seq[tuple[name, nimType: string]]]

proc extractFunctionDefsFromSource*(source: string): seq[FuncDefInfo] {.raises: [].} =
  ## Parse Nim source string and extract function/proc definitions via PNode traversal.
  let ast = parseStringAST(source)
  if ast.isNil: return

  var accum: seq[FuncDefInfo] = @[]
  proc walk(node: PNode; accum: var seq[FuncDefInfo]) {.raises: [], used.} =
    if node.isNil: return
    let nk = $node.kind
    case nk
    of "nkProcDef", "nkFuncDef":
      let nameNode = node[0]
      var funcName = ""
      let nnk = $nameNode.kind
      if nnk == "nkIdent":
        funcName = nameNode.repr
      elif nnk == "nkPostfix" and nameNode.len >= 2:
        funcName = nameNode[1].repr
      elif nnk == "nkPragmaExpr" and nameNode.len >= 2:
        funcName = nameNode[1].repr

      if funcName.len > 0:
        var paramsSeq: seq[tuple[name, nimType: string]] = @[]
        var paramsFound = false
        var bodyFound = false
        var retType = ""

        for i in 1 ..< node.len:
          let child = node[i]
          let ck = $child.kind
          case ck
          of "nkGenericParams", "nkEmpty", "nkPragma":
            discard
          else:
            if ck == "nkParams" and not paramsFound:
              for par in child:
                let pk = $par.kind
                if pk == "nkPar":
                  for p in par:
                    let ppk = $p.kind
                    case ppk
                    of "nkIdentDefs":
                      if p.len >= 2:
                        paramsSeq.add((name: p[0].repr, nimType: p[1].repr))
                    of "nkVarPar", "nkOutPar":
                      if p.len >= 1 and $p[0].kind == "nkIdentDefs" and p[0].len >= 2:
                        paramsSeq.add((name: p[0][0].repr, nimType: p[0][1].repr))
                    else: discard
              paramsFound = true
            elif not bodyFound:
              if ck == "nkStmtList" or ck == "nkBlock" or ck == "nkBlockStmt" or ck == "nkCommand" or ck == "nkIfStmt" or
                 ck == "nkWhenStmt" or ck == "nkForStmt" or ck == "nkWhileStmt" or ck == "nkLoop" or ck == "nkTryStmt" or
                 ck == "nkOfBranch" or ck == "nkCaseStmt":
                bodyFound = true
                walk(child, accum)
              else:
                retType = child.repr

        accum.add((name: funcName, returnType: retType, params: paramsSeq))

    of "nkStmtList", "nkBlock", "nkBlockStmt", "nkWhen", "nkIf", "nkElse", "nkDo", "nkFor",
       "nkWhile", "nkTry", "nkExcept", "nkCase", "nkOfBranch", "nkPragmaExpr":
      for child in node:
        walk(child, accum)
    else:
      discard

  walk(ast, accum)
  result = accum

# ── Local helpers (shadowing boundary_extraction_main exports) ──

func sequenceElementBinderName(base: string; params: seq[ParamBoundary]): string {.noSideEffect.} =
  var existing: seq[string] = @[]
  for p in params:
    existing.add(p.name)
  result = base & "Idx"
  var suffix = 2
  while result in existing:
    result = base & "Idx" & $suffix
    inc suffix

# ── Phase 1c: Function Discovery ──

proc discoverFunction*(ctx: var BoundaryContext) {.raises: [].} =
  ## Parse AST and find the target function. Sets ctx.parseFailed/foundFn/fnNode/ast.
  var parseResult: Result[PNode, string]
  ## [SEE: nim_effect_system_quirks.md]
  {.cast(noSideEffect).}:
    parseResult = parseNimRes(ctx.effectiveFileContext)
  if parseResult.isErr:
    ctx.parseFailed = true
    ctx.regexFallback = true
    return

  ctx.ast = parseResult.get
  let fnNodeOpt = findFunctionNodeP(ctx.ast, ctx.functionName)
  if fnNodeOpt.isNone:
    ctx.regexFallback = true
    return

  ctx.fnNode = fnNodeOpt.get
  # nil guard
  if ctx.fnNode.isNil:
    ctx.foundFn = false
    ctx.regexFallback = true
    return

  # Extract function params from source via PNode traversal
  for fnDef in extractFunctionDefsFromSource(ctx.effectiveFileContext):
    if fnDef.name == ctx.functionName:
      ctx.foundFn = true
      ctx.returnType = fnDef.returnType
      for p in fnDef.params:
        ctx.params.add(ParamBoundary(
          name: p.name, nimType: p.nimType,
          isVar: false, smtConstraint: "", leanProposition: ""
        ))
      break

  # Regex fallback
  if not ctx.foundFn:
    ctx.regexFallback = true
    let regexParams = extractParamsFromSourceRegex(ctx.effectiveFileContext, ctx.functionName)
    for rp in regexParams:
      ctx.params.add(ParamBoundary(
        name: rp.name, nimType: rp.nimType,
        isVar: false, smtConstraint: "", leanProposition: ""
      ))
    ctx.foundFn = ctx.params.len > 0

  # Guard: not found
  if not ctx.foundFn:
    ctx.completeness = bcPartialHavoc
    ctx.hint = buildSemanticHint(
      "ast_parse_failed_isolated", "(assert ast_parse_failed_isolated)",
      "BoundaryExtractor[bcPartialHavoc:fn-not-found] for " & ctx.nodeId,
      0.5, isIntervalAbstraction, @[])
    return

  # Guard: zero-param tautology
  if ctx.params.len == 0:
    ctx.completeness = bcComplete
    ctx.smtParts = @["(assert (>= depth 0))"]
    ctx.leanParts = @["depth >= 0"]
    ctx.hint = buildZeroParamHint(ctx.nodeId)
    return

# ── Phase 2: Effect Detection ──

func detectEffects*(ctx: var BoundaryContext) {.raises: [].} =
  ## Detect var params, external I/O, C FFI. Sets completeness accordingly.
  ## When fnNode is nil (parse failed / regex fallback), skips AST-based
  ## detection but still applies the parseFailed/regexFallback completeness.

  # Var parameter detection (requires valid AST)
  if not ctx.parseFailed and not ctx.fnNode.isNil:
    var paramIdx = 0
    for paramList in findNodes(ctx.fnNode, "parameter_declaration_list"):
      for paramDecl in findNodes(paramList, "parameter_declaration"):
        if paramIdx >= ctx.params.len:
          break
        for child in paramDecl:
          # PNode: check for var parameter (nkVarSection or specific pragma)
          if child.kind == nkPragma:
            let pragmaText = pNodeText(child).toLowerAscii()
            if "var" in pragmaText:
              ctx.params[paramIdx].isVar = true
              ctx.hasVarParam = true
        inc paramIdx

  # External I/O detection (requires valid AST)
  if not ctx.parseFailed and not ctx.fnNode.isNil:
    for callNode in findNodes(ctx.fnNode, "call"):
      for ident in findNodes(callNode, "identifier"):
        let name = nodeText(ident)
        if name in ["readFile", "writeFile", "execCmd", "execCmdEx",
                     "startProcess", "startProcessEx", "socket", "recv", "send", "connect"]:
          ctx.hasExternalIO = true
          break
      if ctx.hasExternalIO:
        break

  if ctx.hasExternalIO:
    ctx.completeness = bcPartialHavoc

  if ctx.hasVarParam and ctx.completeness != bcPartialHavoc:
    ctx.completeness = bcPartialHavoc

  # C FFI detection
  ctx.isFfi = detectFfiInSource(ctx.effectiveFileContext)
  if ctx.isFfi:
    ctx.completeness = bcPartialHavoc

  if ctx.parseFailed or ctx.regexFallback:
    ctx.completeness = bcPartialHavoc

# ── Phase 2b: Constraint Computation ──

proc computeConstraints*(ctx: var BoundaryContext) {.raises: [].} =
  ## Compute boundary constraints for each parameter.
  # Path conditions
  if not ctx.parseFailed and not ctx.fnNode.isNil:
    var pathConditions: seq[tuple[smt: string, lean: string]]
    for pc in pathConditions:
      ctx.smtParts.add(pc.smt)
      ctx.leanParts.add(pc.lean)

  # Per-parameter constraints
  for i in 0 ..< ctx.params.len:
    let pb = ctx.params[i]
    let constraints = typeToBoundaryConstraints(pb.name, pb.nimType)
    ctx.params[i].smtConstraint = constraints.smt
    ctx.params[i].leanProposition = constraints.lean
    if constraints.smt.len > 0:
      ctx.smtParts.add(constraints.smt)
    if constraints.lean.len > 0:
      ctx.leanParts.add(constraints.lean)

    # Object field boundary extraction (Wave U: skip if @axiom-hint exists)
    let hasSourceHint = "@axiom-hint:" in ctx.effectiveFileContext
    if not ctx.parseFailed and not hasSourceHint and
       constraints.smt.len == 0 and constraints.lean.len == 0:
       discard

     # seq[T] element boundary extraction
    if pb.nimType.strip().toLowerAscii().startsWith("seq["):
      let innerStart = pb.nimType.find('[')
      let innerEnd = pb.nimType.rfind(']')
      if innerStart >= 0 and innerEnd > innerStart:
        let elemType = pb.nimType[innerStart + 1 ..< innerEnd].strip()
        let elemBc = typeToBoundaryConstraints("elem", elemType)
        if elemBc.lean.len > 0:
          let binder = sequenceElementBinderName(pb.name, ctx.params)
          let elemPropLean = elemBc.lean.replace("elem", "(" & pb.name & ".get " & binder & ")")
          let forallLean = "(∀ (" & binder & " : Fin " & pb.name & ".size), " & elemPropLean & ")"
          ctx.leanParts.add(forallLean)
          let elemPropSmt = elemBc.smt.replace("elem", "(seq.nth " & pb.name & " " & binder & ")")
          let forallSmt = "(forall ((" & binder & " Int)) (=> (and (>= " & binder & " 0) (< " & binder & " (seq.len " & pb.name & "))) " & elemPropSmt & "))"
          ctx.smtParts.add(forallSmt)

# ── Phase 3: Isolation Injection ──

func injectIsolation*(ctx: var BoundaryContext) {.raises: [].} =
  ## Inject I/O/parse-failed isolation markers, Wave K tautology sentinel.
  if ctx.hasExternalIO:
    ctx.smtParts.add("external_io_isolated")
    ctx.leanParts.add("external_io_isolated")

  if ctx.parseFailed or ctx.regexFallback:
    ctx.smtParts.add("ast_parse_failed_isolated")
    ctx.leanParts.add("ast_parse_failed_isolated")

  # Wave K: opaque type tautology sentinel (only if not already downgraded)
  if ctx.smtParts.len == 0 or ctx.leanParts.len == 0:
    if ctx.completeness == bcComplete:
      ctx.hint = buildSemanticHint(
        "1 = 1", "(assert (= 1 1))",
        "BoundaryExtractor[tautology:opaque-type] for " & ctx.nodeId,
        0.99, isTautologyProof, @[], 0.0)
      ctx.completeness = bcComplete

# ── Phase 4: Triviality Filter ──

func filterTrivial*(ctx: var BoundaryContext) {.raises: [].} =
  ## Filter trivial constraints, generate tautology certs if all trivial.
  # Early exit if already set by injectIsolation
  if ctx.completeness != bcComplete:
    return

  # Wave R: Large Function Gate
  if ctx.smtParts.len > 30:
    ctx.completeness = bcIncompleteIO
    ctx.hint = buildGateHint(ctx.nodeId, "large_function_solid_gate",
      "(assert large_function_solid_gate)",
      "BoundaryExtractor[SOLID-Gate:fields=" & $ctx.smtParts.len & "] for " & ctx.nodeId, 0.0)
    return

  let nonTrivialCount = countNonTrivial(ctx.smtParts, ctx.leanParts)

  if nonTrivialCount == 0:
    # Tautology-proof certificate
    if ctx.smtParts.len > 0:
      let smt = "(assert (and " & ctx.smtParts.join(" ") & "))"
      let lean = ctx.leanParts.join(" ∧ ")
      var paramTypeSeq: seq[ParamTypeInfo] = @[]
      for pb in ctx.params:
        paramTypeSeq.add(ParamTypeInfo(name: pb.name, nimType: pb.nimType))
      for fp in ctx.fieldParamTypes:
        paramTypeSeq.add(ParamTypeInfo(name: fp.name, nimType: fp.nimType))
      if not ctx.parseFailed and not ctx.fnNode.isNil:
        discard
      ctx.hint = buildTautologyHint(ctx.nodeId, smt, lean, paramTypeSeq)
    else:
      ctx.hint = buildZeroParamHint(ctx.nodeId)
    ctx.completeness = bcTrivialDiscard

# ── Phase 5: Final Assembly ──

func assembleResult*(ctx: var BoundaryContext): BoundaryExtractionResult {.raises: [].} =
  ## Compute IG, build final SemanticHint, return BoundaryExtractionResult.
  let filtered = filterNonTrivialParts(ctx.smtParts, ctx.leanParts)
  let ig = computeInformationGain(ctx.params, filtered.nonTrivialSmt)

  if filtered.nonTrivialSmt.len > 0 and filtered.nonTrivialLean.len > 0:
    let smt = "(assert (and " & filtered.nonTrivialSmt.join(" ") & "))"
    let lean = filtered.nonTrivialLean.join(" ∧ ")
    var paramTypeSeq: seq[ParamTypeInfo] = @[]
    for pb in ctx.params:
      paramTypeSeq.add(ParamTypeInfo(name: pb.name, nimType: pb.nimType))
    for fp in ctx.fieldParamTypes:
      paramTypeSeq.add(ParamTypeInfo(name: fp.name, nimType: fp.nimType))
    if not ctx.parseFailed and not ctx.fnNode.isNil:
      discard
    ctx.smtParts = @[smt]
    ctx.leanParts = @[lean]
    ctx.hint = buildSemanticHint(lean, smt,
      "BoundaryExtractor[" & $ctx.completeness & "] for " & ctx.nodeId,
      0.85, isIntervalAbstraction, paramTypeSeq, ig)

  toResult(ctx)

{.pop.}
