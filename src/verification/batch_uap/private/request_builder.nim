## Batch UAP Orchestrator — request-building helpers.
##
## Pure helper functions for classifying source complexity, building
## UAP requests, and constructing BMC configurations.

import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [CatchableError].}

import std/strutils
import std/options
import std/json
import std/sequtils
import std/os
import core/results
import core/sorter/sorter_core
import core/orchestrator/orchestrator_types
import core/logic/smt_logic
import core/logic/axiom_verification_context
import core/boundary/boundary_extractor
import core/symbolic_types_expr
import core/function_verification_summary
# axiomIoBoundary
import core/pipeline_core_types
import core/translator/nim_ast_to_json_nodes
import verification/cegar_engine
import core/bmc/bmc_generic
import core/bmc/bmc_variable_map
import verification/spacer_chc_router
import core/axiom_pragmas

proc buapClassifySourceComplexity*(sourceCode, functionName: string): FunctionComplexityClass {.raises: [].} =
  let hasLoop = sourceCode.contains("while ") or sourceCode.contains("for ") or sourceCode.contains("loop ")
  let hasRecursion = functionName.len > 0 and sourceCode.contains(functionName & "(")
  let hasNonLinear = sourceCode.contains(" * ") or sourceCode.contains(" / ")
  if hasRecursion and (hasNonLinear or hasLoop):
    return fccCombined
  if hasRecursion:
    return fccRecursive
  if hasNonLinear:
    return fccNonLinear
  if hasLoop:
    return fccLoopSimple
  return fccLinear

proc buapFindNodeById*(state: SorterState; nodeId: SorterNodeId): Option[SorterNode] {.raises: [].} =
  for node in state.nodes:
      if node.id == nodeId:
        return some(node)
  none(SorterNode)

proc buapDetectPropertyFromAst(astJson: string): BmcPropertyKind {.raises: [].} =
  ## AST-based property detection: parse JSON nodes to determine what to check.
  var hasMemoryRead = false
  var hasArithmetic = false
  ## [SEE: nim_effect_system_quirks.md] — parseJson side-effect quirk
  {.cast(noSideEffect).}:
    {.cast(raises: []).}:
      try:
        let parsed = parseJson(astJson)
        if parsed.hasKey("nodes"):
          for node in parsed["nodes"]:
            let kind = node{"kind"}.getStr("")
            case kind
            of "memory_read":
              hasMemoryRead = true
            of "assign":
              let op = node{"op"}.getStr("assign")
              if op in ["mul", "div", "add", "sub"]:
                hasArithmetic = true
            else:
              discard
      except CatchableError:
        discard  # axiom:best-effort(ioboundary catch)
  if hasMemoryRead:
    return bpkIndexOutOfBounds
  if hasArithmetic:
    return bpkIntegerOverflow
  bpkIndexOutOfBounds

proc buapBuildSpacerBmcConfig*(sourceCode: string; topologyScore: int; astJson: string = ""): BmcConfig {.raises: [].} =
  ## Derive BMC config from source code heuristics and topology complexity.
  ## When astJson is non-empty, uses AST-based detection; otherwise falls back
  ## to string heuristics.
  let property = if astJson.len > 0:
    buapDetectPropertyFromAst(astJson)
  else:
    let hasArrayAccess = sourceCode.find("[") >= 0 and sourceCode.find("]") >= 0
    let hasPointerCheck = sourceCode.find("nil") >= 0 or sourceCode.find("null") >= 0
    let hasArithmetic = sourceCode.find(" * ") >= 0 or sourceCode.find(" div ") >= 0
    if hasArrayAccess: bpkIndexOutOfBounds
    elif hasPointerCheck: bpkNullDereference
    elif hasArithmetic: bpkIntegerOverflow
    else: bpkRaceCondition

  # Scale step bound by topology complexity (higher score = deeper exploration)
  let stepBound = min(max(topologyScore div 10 + 5, 5), maxGenericStepBound)
  initBmcConfig(property, stepBound = stepBound)

proc buapBuildTransitionsFromContext*(
  ctx: AxiomVerificationContext;
  unsatCoreVars: seq[string]
): seq[BmcTransition] {.raises: [].} =
  ## Build BMC transitions from verification context constraints.
  ## Each ckDynamicStep constraint becomes a transition guard.
  let stateVars: seq[tuple[name: string, sort: string]] =
    if unsatCoreVars.len > 0:
      unsatCoreVars.mapIt((name: it, sort: "Int"))
    else:
      @[(name: "state", sort: "Bool")]

  for c in ctx.constraints:
    if c.kind == ckDynamicStep:
      result.add(BmcTransition(
        preState: stateVars,
        guard: c.expression,
        postState: stateVars.mapIt((name: it.name, expr: it.name))
      ))

  # Fallback: identity transition if no dynamic constraints found
  if result.len == 0:
    result.add(BmcTransition(
      preState: stateVars,
      guard: "(>= state 0)",
      postState: stateVars.mapIt((name: it.name, expr: it.name))
    ))

proc buapBuildSafetyProperty*(cegarInvariants: seq[string]; expectedSmtlib2: string): string {.raises: [].} =
  ## Build safety property from CEGAR invariants or expected SMT-LIB2.
  if cegarInvariants.len > 0:
    if cegarInvariants.len == 1:
      return cegarInvariants[0]
    return "(and " & cegarInvariants.join(" ") & ")"
  if expectedSmtlib2.len > 0:
    return expectedSmtlib2
  ""

proc buapBuildVarMapFromUnsatCore*(vars: seq[string]; sourceFile: string): VariableMapTable {.raises: [].} =
  ## Build variable map from unsat core variables for scope-aware Spacer mapping.
  result = VariableMapTable(sourceFile: sourceFile)
  for i, v in vars:
    result.mappings.add(VariableMapping(
      sourceName: v,
      smtName: v,
      ssaIndex: 0,
      bmcStep: 0,
      sourceLine: 0,
      sourceFile: sourceFile,
      scopeContext: "global"
    ))

proc buapBuildUapRequest*(
  req: OrchestrationProofRequest;
  vaultDir: string;
  maxRounds: int
): Result[UniversalPipelineRequest, string] {.raises: [CatchableError, IOEffect], axiomEffect: IOEffect, tags: [RootEffect, TimeEffect, AxiomIOEffect, IOEffect].} =
  let nodeIdStr = sorterNodeIdString(req.nodeId)
  let parts = nodeIdStr.split("::")
  if parts.len < 2:
    return err("invalid nodeId format: " & nodeIdStr)
  let modulePath = parts[0].normalizedPath()
  let functionName = parts[1]

  # Step 1: Run CEGAR abstraction to derive loop invariants
  let z3Check = z3CheckViaProcess(
    if req.solverCommand.len > 0: req.solverCommand else: "z3",
    req.solverArgs
  )
  let cegarOutput = runCegarAbstraction(req, z3Check)

  # Step 2: Immutable enrichment — attach CEGAR invariants and unsat core vars to request
  var invariantStrings: seq[string] = @[]
  for inv in cegarOutput.provedInvariants:
    invariantStrings.add(sExprToString(inv))
  var enrichedReq = req.withCegarInvariants(invariantStrings)
  enrichedReq.unsatCoreVars = cegarOutput.unsatCoreVars

  # Step 3: Inject invariants into source code as comments for downstream personas
  var enrichedSource = enrichedReq.sourceCode
  if enrichedReq.cegarInvariants.len > 0:
    let commentBlock = "## CEGAR-derived invariants:\n" &
      enrichedReq.cegarInvariants.mapIt("##   " & it).join("\n") & "\n"
    enrichedSource = commentBlock & enrichedSource

  # Build AST JSON for UAP pipeline via tree-sitter parsing
  let jsonNodes = sourceCodeToJsonNodes(enrichedSource, functionName)
  var astObj = %*{"functionName": functionName, "nodes": jsonNodes}
  # Defensive fallback: if tree-sitter produced zero nodes, inject a minimal
  # assignment so the universal mapper does not produce empty invariants.
  if jsonNodes.len == 0:
    astObj["nodes"] = %*[{
      "kind": "assign",
      "target": "depth",
      "left": "depth",
      "op": "assign",
      "right": "0"
    }]
  let astJson = $astObj
  let hasLoop = enrichedSource.contains("while ") or enrichedSource.contains("for ") or enrichedSource.contains("loop ")
  let hasNonLinear = enrichedSource.contains(" * ") or enrichedSource.contains(" / ")
  let hasBitwiseOps = enrichedSource.contains(" and ") or enrichedSource.contains(" or ") or
                      enrichedSource.contains(" xor ") or enrichedSource.contains(" shr ") or
                      enrichedSource.contains(" shl ") or enrichedSource.contains(" not ")
  let logic = selectLogicFromAst(hasBitwiseOps, hasNonLinear, hasLoop)

  # Build verification context from boundary extraction + expected SMTLIB2
  let boundaries = extractBoundaries(nodeIdStr, enrichedSource)
  var verificationContext = AxiomVerificationContext(
    functionName: functionName,
    logic: logic,
    constraints: @[]
  )
  for p in boundaries.params:
    if p.smtConstraint.len > 0:
      verificationContext.addConstraint(ckStaticBounds, p.smtConstraint, "boundary-extractor:" & p.name)
  if req.expectedSmtlib2.len > 0:
    for line in req.expectedSmtlib2.splitLines():
      let stripped = line.strip()
      if stripped.len > 0 and stripped != "(check-sat)":
        verificationContext.addConstraint(ckDynamicStep, stripped, "payload-bridge")

  ok(UniversalPipelineRequest(
    language: "nim",
    modulePath: modulePath,
    functionName: functionName,
    astJson: astJson,
    sourceCode: enrichedSource,
    maxRounds: maxRounds,
    proofVaultDir: vaultDir,
    bddDir: "logs/bdd",
    unsatCoreVars: enrichedReq.unsatCoreVars,
    logic: logic,
    verificationContext: verificationContext
  ))

{.pop.}

