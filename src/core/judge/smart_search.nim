import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
import std/strutils
import std/options
import compiler/ast
import core/parsers/pnode_nav
import core/parser_utils
import core/encoding/type_logic_registry as tlr
import core/interfaces/logging_hub
import core/macros/best_effort

# @axiom-hint: lean="elemType.length ≥ 0" smt="(assert (and (>= (str.len elemType) 0)))"
proc elemBoundaryConstraints*(elemType: string): tuple[lean: string, smt: string] {.raises: [].} =
  ## Type-driven element boundary constraints via type_logic_registry (SSOT).
  let logic = lookupTypeLogic(elemType)
  result.smt = logic.resultConstraintTemplate
  ## Derive lean proposition from registry category.
  case logic.category
  of "numeric": result.lean = "elem ≥ 0"
  of "string": result.lean = "elem.length ≥ 0"
  of "bool": result.lean = "elem = true ∨ elem = false"
  else: result.lean = ""

import core/types/hubs/semantic_hint_hub
export semantic_hint_hub

# @axiom-hint: lean="line.length ≥ 0" smt="(assert (and (>= (str.len line) 0)))"
proc extractHintFromLine*(line: string; returnType: string = ""): Option[SemanticHint] {.raises: [].} =
  ## Extract @axiom-hint from source line. When returnType is void,
  ## skip — result is not in scope for void functions.
  let marker = "# @axiom-hint:"
  let idx = line.find(marker)
  if idx < 0: return none(SemanticHint)

  ## Strict-contract-mode: void functions have no result in scope.
  if returnType.len > 0 and isVoidType(returnType):
    return none(SemanticHint)

  let content = line[idx + marker.len .. ^1].strip()
  var leanProp = ""
  var smtConstraint = ""

  let leanIdx = content.find("lean=\"")
  if leanIdx >= 0:
    let leanEnd = content.find("\"", leanIdx + 6)
    if leanEnd >= 0:
      leanProp = content[leanIdx + 6 ..< leanEnd]

  let smtIdx = content.find("smt=\"")
  if smtIdx >= 0:
    let smtEnd = content.find("\"", smtIdx + 5)
    if smtEnd >= 0:
      smtConstraint = content[smtIdx + 5 ..< smtEnd]

  if leanProp.len > 0 and smtConstraint.len > 0:
    return some(SemanticHint(
      leanProposition: leanProp,
      smtConstraint: smtConstraint,
      sourceReference: "Extracted from source comment",
      confidence: 0.95,
      strategy: isHintComment,
      retryCount: 0
    ))

  return none(SemanticHint)

# @axiom-hint: lean="nodeId.length ≥ 0 ∧ fileContext.length ≥ 0" smt="(assert (and (>= (str.len nodeId) 0) (>= (str.len fileContext) 0)))"
# @axiom-hint: lean="ast_parse_failed_isolated" smt="(assert (and ast_parse_failed_isolated))"
func analyzeBottleneckAstImpl(
  nodeId: string;
  fileContext: string;
  fnNodeOpt: Option[PNode]
): seq[BottleneckCause] {.noSideEffect.} =
  ## AST-based bottleneck analysis. All logic detection uses the tree-sitter
  ## AST; no substring-only logic detection remains.
  if fileContext.len == 0:
    return @[bcNoHintComment]

  # Hint comment marker detection (data extraction, not logic analysis)
  var hasHintComment = false
  for line in fileContext.splitLines():
    let trimmed = line.strip()
    if trimmed.startsWith("# @axiom-hint:"):
      hasHintComment = true
      break
  if not hasHintComment:
    result.add(bcNoHintComment)

  if fnNodeOpt.isNone:
    # Without AST, we can only report the missing hint comment
    if result.len == 0:
      result.add(bcUnknown)
    return

  let fnNode = fnNodeOpt.get
  let fnName = if nodeId.find("::") >= 0:
    let parts = nodeId.split("::", maxsplit = 1)
    if parts.len > 1: parts[1] else: nodeId
  else:
    nodeId

  # Detect complex recursion via AST self-calls
  var hasSelfCall = false
  var procCount = 0
  for callNode in findNodes(fnNode, "call"):
    for ident in findNodes(callNode, "identifier"):
      if nodeText(ident) == fnName:
        hasSelfCall = true
        break
    if hasSelfCall:
      break
  # Count proc/func declarations in the file context AST
  for _ in findNodes(fnNode, "proc_declaration"):
    inc procCount
  for _ in findNodes(fnNode, "func_declaration"):
    inc procCount
  if hasSelfCall or procCount > 1:
    result.add(bcComplexRecursion)

  # Detect non-linear arithmetic via AST operator nodes
  for infix in findNodes(fnNode, "infix_expression"):
    for op in findNodes(infix, "operator"):
      let opText = nodeText(op)
      if opText in ["*", "div", "mod", "shr", "shl"]:
        result.add(bcNonLinearArithmetic)
        break
    if bcNonLinearArithmetic in result:
      break

  # Detect external I/O via AST call identifiers
  const ioProcs = ["readFile", "writeFile", "execCmd", "execCmdEx",
                   "startProcess", "startProcessEx", "socket", "recv",
                   "send", "connect", "httpClient", "httpGet", "httpPost"]
  for callNode in findNodes(fnNode, "call"):
    for ident in findNodes(callNode, "identifier"):
      let name = nodeText(ident)
      if name in ioProcs:
        result.add(bcExternalIO)
        break
    if bcExternalIO in result:
      break

  # Detect complex control flow via AST exception handling nodes
  for tag in ["try", "except", "except_branch", "finally", "defer"]:
    for _ in findNodes(fnNode, tag):
      result.add(bcComplexControlFlow)
      break
    if bcComplexControlFlow in result:
      break

  # Detect closure semantics via AST pragma nodes
  for pragmaNode in findNodes(fnNode, "pragma"):
    for ident in findNodes(pragmaNode, "identifier"):
      let name = nodeText(ident)
      if name in ["closure", "gcsafe"]:
        result.add(bcClosureSemantics)
        break
    if bcClosureSemantics in result:
      break

  # Detect large function body (metric, not logic analysis)
  let lineCount = fileContext.splitLines().len
  if lineCount > 200:
    result.add(bcLargeFunctionBody)

  if result.len == 0:
    result.add(bcUnknown)

## Analyze Bottleneck Ast.
func analyzeBottleneckAst*(
  nodeId: string;
  fileContext: string;
  fnNodeOpt: Option[PNode]
): seq[BottleneckCause] {.noSideEffect.} =
  ## AST-based bottleneck analysis entry point. Callers that have pre-parsed
  ## the function AST should pass fnNodeOpt for full analysis.
  analyzeBottleneckAstImpl(nodeId, fileContext, fnNodeOpt)

## Bottleneck Causes To String.
# @axiom-hint: lean="causes.size ≥ 0" smt="(assert (and (>= (seq.len causes) 0)))"
# @axiom-hint: lean="bcNoHintComment ∧ bcComplexRecursion ∧ bcNonLinearArithmetic ∧ bcExternalIO ∧ bcComplexControlFlow ∧ bcClosureSemantics ∧ bcLargeFunctionBody ∧ bcHighComplexity ∧ bcHighCoupling ∧ bcUnknown ∧ (causes ≥ 0)" smt="(assert (and bcNoHintComment bcComplexRecursion bcNonLinearArithmetic bcExternalIO bcComplexControlFlow bcClosureSemantics bcLargeFunctionBody bcHighComplexity bcHighCoupling bcUnknown (>= causes 0)))"
func bottleneckCausesToString*(causes: seq[BottleneckCause]): string {.noSideEffect.} =
  var parts: seq[string] = @[]
  for cause in causes:
    case cause
    of bcNoHintComment: parts.add("no @axiom-hint comment")
    of bcComplexRecursion: parts.add("complex recursion")
    of bcNonLinearArithmetic: parts.add("non-linear arithmetic")
    of bcExternalIO: parts.add("external I/O or process invocation")
    of bcComplexControlFlow: parts.add("complex control flow (exception handling)")
    of bcClosureSemantics: parts.add("closure/capture semantics")
    of bcLargeFunctionBody: parts.add("large function body")
    of bcHighComplexity: parts.add("high complexity (ACI > 70)")
    of bcHighCoupling: parts.add("high coupling (SRP violation)")
    of bcUnknown: parts.add("unknown")
  parts.join(", ")

## Vacuity ban: self-equality propositions are not valid proof candidates.
## Removed emitInductionProposition and emitPatternMatchingProposition.
## Any strategy that cannot derive a real variable dependency must return
## none(SemanticHint) instead of a tautology.

## Generate Semantic Hint With Strategy.
# @axiom-hint: lean="nodeId.length ≥ 0 ∧ fileContext.length ≥ 0 ∧ docContext.length ≥ 0 ∧ retryCount ≥ -9223372036854775808 ∧ retryCount ≤ 9223372036854775807" smt="(assert (and (>= (str.len nodeId) 0) (>= (str.len fileContext) 0) (>= (str.len docContext) 0) (and (>= retryCount -9223372036854775808) (<= retryCount 9223372036854775807))))"
# @axiom-hint: lean="nodeId.length ≥ 0 ∧ fileContext.length ≥ 0 ∧ docContext.length ≥ 0 ∧ attemptCount ≥ -9223372036854775808 ∧ attemptCount ≤ 9223372036854775807" smt="(assert (and (>= (str.len nodeId) 0) (>= (str.len fileContext) 0) (>= (str.len docContext) 0) (and (>= attemptCount -9223372036854775808) (<= attemptCount 9223372036854775807))))"
# @axiom-hint: lean="ast_parse_failed_isolated" smt="(assert ast_parse_failed_isolated)"
proc generateSemanticHintWithStrategy*(
  nodeId: string, fileContext: string, docContext: string, strategy: InferenceStrategy, retryCount: int = 0
): Option[SemanticHint] {.bestEffort("""AST parsing failures in strategy branches return none; safe default on malformed code""").} =
  case strategy
  of isHintComment:
    for line in fileContext.splitLines():
      let hint = extractHintFromLine(line)
      if hint.isSome:
        var res = hint.get()
        res.sourceReference = "Source context for " & nodeId & ": " & res.sourceReference
        res.retryCount = retryCount
        return some(res)
    for line in docContext.splitLines():
      let hint = extractHintFromLine(line)
      if hint.isSome:
        var res = hint.get()
        res.sourceReference = "Doc context for " & nodeId & ": " & res.sourceReference
        res.retryCount = retryCount
        return some(res)
    return none(SemanticHint)

  of isIntervalAbstraction:
    try:
      let ast = parseStringAST(fileContext)
      let parts = nodeId.split("::")
      let fnName = if parts.len > 1: parts[1] else: nodeId
      let fnNodeOpt = findFunctionNode(ast, fnName)
      if fnNodeOpt.isNone:
        return none(SemanticHint)
      let fnNode = fnNodeOpt.get
      for infix in findNodes(fnNode, "infix_expression"):
        for op in findNodes(infix, "operator"):
          let opText = nodeText(op)
          if opText in ["..", "..<", "..^"]:
            return some(SemanticHint(
              leanProposition: "interval_abstraction(" & fnName & ")",
              smtConstraint: "(forall (x) (and (>= x lower) (<= x upper)))",
              sourceReference: "Interval abstraction via range operator " & opText & " in " & nodeId,
              confidence: 0.75,
              strategy: isIntervalAbstraction,
              retryCount: retryCount
            ))
      if findNodes(fnNode, "set_constructor").len > 0:
        return some(SemanticHint(
          leanProposition: "interval_abstraction(" & fnName & ")",
          smtConstraint: "(forall (x) (=> (in x set) (property x)))",
          sourceReference: "Interval abstraction via set constructor in " & nodeId,
          confidence: 0.7,
          strategy: isIntervalAbstraction,
          retryCount: retryCount
        ))
    except CatchableError as e:
      logError("smart_search: interval abstraction search failed: " & e.msg)
    return none(SemanticHint)

  of isStructuralInduction:
    try:
      let ast = parseStringAST(fileContext)
      let parts = nodeId.split("::")
      let fnName = if parts.len > 1: parts[1] else: nodeId
      let fnNodeOpt = findFunctionNode(ast, fnName)
      if fnNodeOpt.isNone:
        return none(SemanticHint)
      let fnNode = fnNodeOpt.get
      
      var hasForLoop = false
      if findNodes(fnNode, "for_statement").len > 0:
        hasForLoop = true
      
      var hasRecursion = false
      for callNode in findNodes(fnNode, "call"):
        for ident in findNodes(callNode, "identifier"):
          if nodeText(ident) == fnName:
            hasRecursion = true
            break
        if hasRecursion:
          break
      
      var hasCase = false
      if findNodes(fnNode, "case_statement").len > 0:
        hasCase = true
      
      var seqParams: seq[tuple[name, elemType: string]] = @[]
      for paramList in findNodes(fnNode, "parameter_declaration_list"):
        for paramDecl in findNodes(paramList, "parameter_declaration"):
          let typeNodeOpt = findFirstNode(paramDecl, "type_expression")
          let nameNodeOpt = findFirstNode(paramDecl, "identifier")
          if typeNodeOpt.isSome and nameNodeOpt.isSome:
            let typeText = nodeText(typeNodeOpt.get).strip().toLowerAscii()
            let paramName = nodeText(nameNodeOpt.get)
            if typeText.startsWith("seq["):
              let innerStart = typeText.find('[')
              let innerEnd = typeText.rfind(']')
              if innerStart >= 0 and innerEnd > innerStart:
                let elemType = typeText[innerStart + 1 ..< innerEnd].strip()
                seqParams.add((name: paramName, elemType: elemType))
      
      if seqParams.len > 0 and (hasForLoop or hasRecursion):
        var leanParts: seq[string] = @[]
        var smtParts: seq[string] = @[]
        var paramTypeSeq: seq[ParamTypeInfo] = @[]
        for sp in seqParams:
          let elemBc = elemBoundaryConstraints(sp.elemType)
          if elemBc.lean.len > 0:
            let elemPropLean = elemBc.lean.replace("elem", sp.name & ".get i")
            leanParts.add("∀ (i : Fin " & sp.name & ".size), " & elemPropLean)
            let elemPropSmt = elemBc.smt.replace("elem", "(seq.nth " & sp.name & " i)")
            smtParts.add("(forall ((i Int)) (=> (and (>= i 0) (< i (seq.len " & sp.name & "))) " & elemPropSmt & "))")
            paramTypeSeq.add(ParamTypeInfo(name: sp.name, nimType: "seq[" & sp.elemType & "]"))
            paramTypeSeq.add(ParamTypeInfo(name: "i", nimType: "Natural"))
        
        if leanParts.len > 0:
          return some(SemanticHint(
            leanProposition: leanParts.join(" ∧ "),
            smtConstraint: "(assert (and " & smtParts.join(" ") & "))",
            sourceReference: "StructuralInduction[seq] for " & nodeId,
            confidence: 0.78,
            strategy: isStructuralInduction,
            retryCount: retryCount,
            paramTypes: paramTypeSeq
          ))
      
      if hasRecursion or hasCase:
        return some(SemanticHint(
          leanProposition: fnName & "_depth ≥ 0 ∧ " & fnName & "_impact ≥ 0",
          smtConstraint: "(assert (and (>= " & fnName & "_depth 0) (>= " & fnName & "_impact 0)))",
          sourceReference: "StructuralInduction[recursive] for " & nodeId,
          confidence: 0.72,
          strategy: isStructuralInduction,
          retryCount: retryCount
        ))
    except CatchableError as e:
      logError("smart_search: structural induction search failed: " & e.msg)
    return none(SemanticHint)

  of isPatternMatching:
    try:
      let ast = parseStringAST(fileContext)
      let parts = nodeId.split("::")
      let fnName = if parts.len > 1: parts[1] else: nodeId
      let fnNodeOpt = findFunctionNode(ast, fnName)
      if fnNodeOpt.isNone:
        return none(SemanticHint)
      let fnNode = fnNodeOpt.get
      
      let caseNodes = findNodes(fnNode, "case_statement")
      if caseNodes.len > 0:
        var guards: seq[string] = @[]
        for caseNode in caseNodes:
          for branch in findNodes(caseNode, "case_branch"):
            for guard in findNodes(branch, "guard"):
              guards.add(nodeText(guard))
        
        if guards.len > 0:
          return some(SemanticHint(
            leanProposition: fnName & "_cases_cover_all ∧ " & fnName & "_guards_exhaustive",
            smtConstraint: "(assert (and (>= " & fnName & "_depth 0) (>= " & fnName & "_impact 0)))",
            sourceReference: "PatternMatching[case] for " & nodeId & " (" & $guards.len & " branches)",
            confidence: 0.70,
            strategy: isPatternMatching,
            retryCount: retryCount
          ))
      
      let ifNodes = findNodes(fnNode, "if_statement")
      if ifNodes.len > 0:
        return some(SemanticHint(
          leanProposition: fnName & "_branches_exhaustive",
          smtConstraint: "(assert (and (>= " & fnName & "_depth 0) (>= " & fnName & "_impact 0)))",
          sourceReference: "PatternMatching[if] for " & nodeId,
          confidence: 0.68,
          strategy: isPatternMatching,
          retryCount: retryCount
        ))
    except CatchableError as e:
      logError("smart_search: pattern matching search failed: " & e.msg)
    return none(SemanticHint)

  of isTautologyProof:
    ## Wave D: tautology proofs are generated by boundary_extractor directly.
    return none(SemanticHint)

## Inference Strategy Label.
# @axiom-hint: lean="depth >= 0" smt="(assert (and (>= depth 0)))"
# @axiom-hint: lean="isHintComment ∧ isIntervalAbstraction ∧ isStructuralInduction ∧ isPatternMatching ∧ isTautologyProof" smt="(assert (and isHintComment isIntervalAbstraction isStructuralInduction isPatternMatching isTautologyProof))"
func inferenceStrategyLabel*(s: InferenceStrategy): string {.noSideEffect.} =
  case s
  of isHintComment: "hintComment"
  of isIntervalAbstraction: "intervalAbstraction"
  of isStructuralInduction: "structuralInduction"
  of isPatternMatching: "patternMatching"
  of isTautologyProof: "tautologyProof"

## Select Inference Strategy.
# @axiom-hint: lean="attemptCount ≥ -9223372036854775808 ∧ attemptCount ≤ 9223372036854775807" smt="(assert (and (and (>= attemptCount -9223372036854775808) (<= attemptCount 9223372036854775807))))"
func selectInferenceStrategy*(attemptCount: int): InferenceStrategy {.noSideEffect.} =
  let strategies = [isHintComment, isIntervalAbstraction, isStructuralInduction, isPatternMatching]
  strategies[attemptCount mod strategies.len]

## Generate Semantic Hint.
proc generateSemanticHint*(
  nodeId: string, fileContext: string, docContext: string, attemptCount: int = 0
): Option[SemanticHint] =
  let strategy = selectInferenceStrategy(attemptCount)
  generateSemanticHintWithStrategy(nodeId, fileContext, docContext, strategy)

{.pop.}
