import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
import ../../core/trusted/axiom_pragmas
import core/diagnostics/diagnostics_engine_helpers
import core/diagnostics/refactoring_engine
import core/parser_utils
import core/parsers/pnode_nav
import core/sorter/sorter_core
import compiler/ast
import std/options
import std/strutils
func structuralRemediationHint(
  childNodeCount: int;
  logicalDepth: int;
  couplingScore: int;
  interfaceDistance: int;
  labels: seq[string]
): string {.axiom, axiomImpl.} =
  ## axiom-smt: (assert (and (and (>= childNodeCount -9223372036854775808) (<= childNodeCount 9223372036854775807)) (and (>= logicalDepth -9223372036854775808) (<= logicalDepth 9223372036854775807)) (and (>= couplingScore -9223372036854775808) (<= couplingScore 9223372036854775807)) (and (>= interfaceDistance -9223372036854775808) (<= interfaceDistance 9223372036854775807)) (>= (seq.len labels) 0) (forall ((labelsIdx Int)) (=> (and (>= labelsIdx 0) (< labelsIdx (seq.len labels))) (>= (str.len (seq.nth labels labelsIdx)) 0))) (and (<= interfaceDistance 1) (> logicalDepth 0)) (forall ((labelsIdx Int)) (=> (and (>= labelsIdx 0) (< labelsIdx (seq.len labels))) (>= (str.len (seq.nth labels labelsIdx)) 0)))))
  ## axiom-lean: childNodeCount ≥ -9223372036854775808 ∧ childNodeCount ≤ 9223372036854775807 ∧ logicalDepth ≥ -9223372036854775808 ∧ logicalDepth ≤ 9223372036854775807 ∧ couplingScore ≥ -9223372036854775808 ∧ couplingScore ≤ 9223372036854775807 ∧ interfaceDistance ≥ -9223372036854775808 ∧ interfaceDistance ≤ 9223372036854775807 ∧ labels.size ≥ 0 ∧ (∀ (labelsIdx : Fin labels.size), (labels.get labelsIdx).length ≥ 0) ∧ interfaceDistance ≤ 1 ∧ logicalDepth > 0 ∧ (∀ (labelsIdx : Fin labels.size), (labels.get labelsIdx).length ≥ 0)
  if "module decomposition required" in labels:
    return "Child node count and logical depth simultaneously exceeded threshold. Decompose module with intermediate theorem functions and boundary-exclusive wrappers to reduce search cross-section."
  if "coupling threshold exceeded" in labels:
    return "High-coupling bottleneck node. Separate caller-specific contracts and reduce fan-in to shrink upper proof dependencies."
  if "state transition invariant missing" in labels:
    return "No invariant visible for branching or iteration structure. Add assertion/lemma summarizing state transitions to limit structural search width."
  if interfaceDistance <= 1 and logicalDepth > 0:
    return "Node close to external interface. Isolate boundary contract first to reduce defect propagation radius."
  "Structural signals are dispersed. Reassign responsibilities based on call graph fan-out and branching depth."
func structuralRationale(
  childNodeCount: int;
  logicalDepth: int;
  couplingScore: int;
  interfaceDistance: int;
  labels: seq[string]
): string {.axiom, axiomImpl.} =
  ## axiom-smt: (assert (and (and (>= childNodeCount -9223372036854775808) (<= childNodeCount 9223372036854775807)) (and (>= logicalDepth -9223372036854775808) (<= logicalDepth 9223372036854775807)) (and (>= couplingScore -9223372036854775808) (<= couplingScore 9223372036854775807)) (and (>= interfaceDistance -9223372036854775808) (<= interfaceDistance 9223372036854775807)) (>= (seq.len labels) 0) (forall ((labelsIdx Int)) (=> (and (>= labelsIdx 0) (< labelsIdx (seq.len labels))) (>= (str.len (seq.nth labels labelsIdx)) 0))) (<= interfaceDistance 1) (= (str.len fragments) 0) (forall ((labelsIdx Int)) (=> (and (>= labelsIdx 0) (< labelsIdx (seq.len labels))) (>= (str.len (seq.nth labels labelsIdx)) 0)))))
  ## axiom-lean: childNodeCount ≥ -9223372036854775808 ∧ childNodeCount ≤ 9223372036854775807 ∧ logicalDepth ≥ -9223372036854775808 ∧ logicalDepth ≤ 9223372036854775807 ∧ couplingScore ≥ -9223372036854775808 ∧ couplingScore ≤ 9223372036854775807 ∧ interfaceDistance ≥ -9223372036854775808 ∧ interfaceDistance ≤ 9223372036854775807 ∧ labels.size ≥ 0 ∧ (∀ (labelsIdx : Fin labels.size), (labels.get labelsIdx).length ≥ 0) ∧ interfaceDistance ≤ 1 ∧ fragments.length = 0 ∧ (∀ (labelsIdx : Fin labels.size), (labels.get labelsIdx).length ≥ 0)
  var fragments: seq[string] = @[]
  if "coupling threshold exceeded" in labels:
    fragments.add("fan-in/fan-out sum exceeded coupling threshold raising bottleneck centrality")
  if "logical search range excessive" in labels:
    fragments.add("child node count and control flow depth multiply causing exploration state space explosion")
  if "state transition invariant missing" in labels:
    fragments.add("preservation conditions for branching or iteration structures not exposed making inductive reduction impossible")
  if "module decomposition required" in labels:
    fragments.add("high fan-out and deep nesting suggest decomposition proof is lower cost than composition proof")
  if interfaceDistance <= 1:
    fragments.add("proximity to external boundary means defects can immediately propagate to system surface")
  if fragments.len == 0:
    return "Topological structural signals are stable but continue monitoring for additional decomposition opportunities."
  fragments.join("; ")

func hasLoopStructureAstP(ast: PNode): bool {.raises: [].} =
  for node in findNodesP(ast, {nkWhileStmt, nkForStmt}):
    return true
  false
func extractProcNameAstP(ast: PNode): string {.raises: [].} =
  for node in findNodesP(ast, ProcDefKinds):
    if node.len > 0 and not node[0].isNil:
      let nameNodeOpt = findFirstNodeP(node[0], {nkIdent})
      if nameNodeOpt.isSome():
        let nmNode = get(nameNodeOpt)
        result = if nmNode.kind == nkIdent:
                    nmNode.ident.s
                  elif nmNode.kind == nkSym:
                    nmNode.sym.name.s
                  else:
                    ""
        if result.len > 0:
          return result
  result = ""
func hasRecursiveShapeAstP(ast: PNode): bool {.raises: [].} =
  var procName = ""
  var body: PNode = nil
  for node in findNodesP(ast, ProcDefKinds):
    if node.len > 0 and not node[0].isNil:
      let nameNodeOpt = findFirstNodeP(node[0], {nkIdent})
      if nameNodeOpt.isSome():
        let nmNode = get(nameNodeOpt)
        procName = if nmNode.kind == nkIdent:
                      nmNode.ident.s
                    elif nmNode.kind == nkSym:
                      nmNode.sym.name.s
                    else:
                      ""
    if procName.len > 0:
      for child in node:
        if not child.isNil and child.kind in {nkStmtList, nkBlockStmt, nkBlockExpr}:
          body = child
          break
    if procName.len > 0 and body != nil:
      for callNode in findNodesP(body, {nkCall}):
        if callNode.len > 0 and not callNode[0].isNil:
          let calleeNameOpt = findFirstNodeP(callNode[0], {nkIdent})
          if calleeNameOpt.isSome():
            let calleeNode = get(calleeNameOpt)
            let calleeName = if calleeNode.kind == nkIdent:
                              calleeNode.ident.s
                            elif calleeNode.kind == nkSym:
                              calleeNode.sym.name.s
                            else:
                              ""
            if calleeName == procName:
              return true
  false
## AST-routing public wrappers (I/O boundary: proc)
proc hasLoopStructure*(sourceCode: string): bool =
  let ast = parseStringAST(sourceCode)
  if not ast.isNil:
    hasLoopStructureAstP(ast)
  else:
    hasLoopStructureString(sourceCode)
proc extractProcName*(sourceCode: string): string =
  let ast = parseStringAST(sourceCode)
  if not ast.isNil:
    extractProcNameAstP(ast)
  else:
    extractProcNameString(sourceCode)
proc hasRecursiveShape*(sourceCode: string): bool =
  let ast = parseStringAST(sourceCode)
  if not ast.isNil:
    hasRecursiveShapeAstP(ast)
  else:
    hasRecursiveShapeString(sourceCode)

func buildStructuralDiagnosisFromAstP*(
  ast: PNode;
  nodeId: SorterNodeId;
  sourceCode: string;
  childNodeCount: int;
  logicalDepth: int;
  interfaceDistance: int;
  couplingScore: int;
  branchCount: int;
  nestingDepth: int
): StructuralDiagnosis {.raises: [].} =
  var labels: seq[string] = @[]
  let invariantMissing =
    (hasLoopStructureString(sourceCode) or branchCount > 0 or nestingDepth > 1) and
    not hasInvariantMarker(sourceCode)
  if couplingScore >= 16:
    labels.add("coupling threshold exceeded")
  if logicalDepth >= 5 or childNodeCount >= 4 or (branchCount >= 3 and nestingDepth >= 2):
    labels.add("logical search range excessive")
  if invariantMissing:
    labels.add("state transition invariant missing")
  if childNodeCount >= 4 or (logicalDepth >= 6 and couplingScore >= 12):
    labels.add("module decomposition required")
  labels = deduplicateStrings(labels)

  var astNodeId = ""
  var parentNodeType = ""
  var childIndices: seq[int] = @[]

  for node in findNodesP(ast, ProcDefKinds):
    if node.len > 0 and not node[0].isNil:
      let nameNodeOpt = findFirstNodeP(node[0], {nkIdent})
      if nameNodeOpt.isSome():
        let nmNode = get(nameNodeOpt)
        astNodeId = if nmNode.kind == nkIdent:
                      nmNode.ident.s
                    elif nmNode.kind == nkSym:
                      nmNode.sym.name.s
                    else:
                      ""
      for i, child in node:
        if not child.isNil and child.kind in {nkStmtList, nkBlockStmt, nkBlockExpr}:
          childIndices.add(i)
      break

  StructuralDiagnosis(
    nodeId: nodeId,
    diagnosticLabels: labels,
    remediationHint: structuralRemediationHint(
      childNodeCount,
      logicalDepth,
      couplingScore,
      interfaceDistance,
      labels
    ),
    mathematicalRationale: structuralRationale(
      childNodeCount,
      logicalDepth,
      couplingScore,
      interfaceDistance,
      labels
    ),
    childNodeCount: childNodeCount,
    logicalDepth: logicalDepth,
    interfaceDistance: interfaceDistance,
    couplingScore: couplingScore,
    astNodeId: astNodeId,
    parentNodeType: parentNodeType,
    childIndices: childIndices
  )
## Build Structural Diagnosis (I/O boundary: proc).
proc buildStructuralDiagnosis*(
  nodeId: SorterNodeId;
  sourceCode: string;
  childNodeCount: int;
  logicalDepth: int;
  interfaceDistance: int;
  couplingScore: int;
  branchCount: int;
  nestingDepth: int
): StructuralDiagnosis =
  let ast = parseStringAST(sourceCode)
  if not ast.isNil:
    return buildStructuralDiagnosisFromAstP(
      ast, nodeId, sourceCode,
      childNodeCount, logicalDepth, interfaceDistance,
      couplingScore, branchCount, nestingDepth
    )

  var labels: seq[string] = @[]
  let invariantMissing =
    (hasLoopStructureString(sourceCode) or branchCount > 0 or nestingDepth > 1) and
    not hasInvariantMarker(sourceCode)
  if couplingScore >= 16:
    labels.add("coupling threshold exceeded")
  if logicalDepth >= 5 or childNodeCount >= 4 or (branchCount >= 3 and nestingDepth >= 2):
    labels.add("logical search range excessive")
  if invariantMissing:
    labels.add("state transition invariant missing")
  if childNodeCount >= 4 or (logicalDepth >= 6 and couplingScore >= 12):
    labels.add("module decomposition required")
  labels = deduplicateStrings(labels)

  StructuralDiagnosis(
    nodeId: nodeId,
    diagnosticLabels: labels,
    remediationHint: structuralRemediationHint(
      childNodeCount,
      logicalDepth,
      couplingScore,
      interfaceDistance,
      labels
    ),
    mathematicalRationale: structuralRationale(
      childNodeCount,
      logicalDepth,
      couplingScore,
      interfaceDistance,
      labels
    ),
    childNodeCount: childNodeCount,
    logicalDepth: logicalDepth,
    interfaceDistance: interfaceDistance,
    couplingScore: couplingScore,
    astNodeId: "",
    parentNodeType: "",
    childIndices: @[]
  )


# Phase 3: Refactoring engine integration
func generateRefactoringTemplates*(diagnosis: TimeoutDiagnosis): seq[RefactoringTemplate] {.raises: [].} =
  ## Convert a TimeoutDiagnosis into machine-actionable refactoring templates.
  let signals = classifySignals(
    quantifierCount = diagnosis.quantifierCount,
    nonLinearArithmeticCount = diagnosis.nonLinearArithmeticCount,
    dependencyDepth = diagnosis.dependencyDepth,
    couplingScore = 0,  # not available in TimeoutDiagnosis
    hasLoop = "loop" in diagnosis.remediationHint.toLowerAscii(),
    hasRecursion = "recursion" in diagnosis.remediationHint.toLowerAscii() or "recursive" in diagnosis.remediationHint.toLowerAscii()
  )
  generateTemplates(signals)
# Phase 3.5: AST + Unsat Core correlation
type
  UnsatCoreCorrelation* = object
    isNonLinear*: bool
    isRecursive*: bool
    hasMissingInvariant*: bool
    correlatedVars*: seq[string]
    astNodePaths*: seq[string]
func correlateUnsatCoreToAst*(
    unsatVars: seq[string];
    sourceCode: string
): UnsatCoreCorrelation {.raises: [].} =
  ## Correlates Z3 unsat core variables with AST structural properties.
  ## Uses string-based heuristics as initial implementation.
  ## Tree-sitter AST queries are active via core/parsers/tree_sitter_parse.
  result = UnsatCoreCorrelation()
  for varName in unsatVars:
    if varName.len == 0: continue
    # Check if variable appears in non-linear expression context
    let patterns = [varName & " * ", varName & " / ", " * " & varName, " / " & varName]
    for pat in patterns:
      if pat in sourceCode:
        result.isNonLinear = true
        result.correlatedVars.add(varName)
        break
    # Check if variable appears in while/for loop context
    if ("while " & varName) in sourceCode or ("for " & varName) in sourceCode:
      result.hasMissingInvariant = true
      if varName notin result.correlatedVars:
        result.correlatedVars.add(varName)
{.pop.}

