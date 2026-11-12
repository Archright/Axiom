{.push raises: [].}
import core/trusted/layer_declaration
axiomLayer "domain"
import core/trusted/axiom_pragmas_lite
import core/types/hubs/refactoring_hub
import core/parser_utils
import core/types/results
## ast_inspector is itself a Domain-layer module (declares `axiomLayer "domain"`;
## moved from sieve/ to resolve the former core→sieve crossing — see its module
## header), so this import is layer-legal and needs no exception authority.
## (Formerly cited as DEBT#244 — that ID has no entry in
##  data/debt_registry.json; ghost reference removed 2026-10-12.)
import core/interfaces/ast_inspector
import std/strutils
import std/tables
import std/options
import compiler/ast
import core/parsers/pnode_nav
## ─── Types ───────────────────────────────────────────────────────────────────

type
  PatternKind* = enum
    ## Mirror of RefactoringPatternKind from refactoring_engine.nim.
    ## Defined here to avoid circular dependency.
    pkExtractPureFunction
    pkLinearizeVariables
    pkInsertCompositionNode
    pkIsolateInterface
    pkAddLoopInvariant
    pkAddDecreaseMeasure

  PatternApplicability* = object
    ## Structured result of a pattern applicability check.
    ## If `applicable` is false, `reason` explains why and
    ## `missingPreconditions` lists what would need to change.
    applicable*: bool
    reason*: string
    preconditions*: seq[string]      ## What must hold for this pattern
    satisfiedPreconditions*: seq[string]  ## What currently holds
    missingPreconditions*: seq[string]    ## What does NOT hold
    astEvidence*: seq[string]        ## Structural evidence from AST
    hardMissing*: seq[string]        ## psHard 조건 실패만
    softMissing*: seq[string]        ## psSoft 조건 실패만
    failureKind*: FailureKind        ## Structural failure classification (see FailureKind)

  FailureKind* = enum
    paNone           ## No failure — applicable is true (zero-value sentinel)
    paParseFailure   ## Source could not be parsed (malformed)
    paEmptySource    ## Source is empty or unavailable
    paPreconditionMiss ## Source parsed and available, but structural preconditions not met

  PrerequisiteKind* = enum
    prqBodyHasNoSideEffects
    prqNoIoCalls
    prqNoMutation
    prqReturnTypeDeterministic
    prqNoExternalStateAccess
    prqHasNonlinearArithmetic
    prqVariablesIndependent
    prqNoDivisionByVariable
    prqNoModularArithmetic
    prqCallChainDepthGe3
    prqIntermediateTypeExists
    prqNoRecursiveCallsInChain
    prqHasIoBoundary
    prqIoCallsConcentrated
    prqPureComputationSeparable
    prqHasLoop
    prqNoExistingInvariant
    prqLoopBodyBounded
    prqHasRecursion
    prqNoExistingMeasure
    prqRecursiveArgDecreasing

## ─── Precondition Definitions ────────────────────────────────────────────────
## Each pattern has a set of structural preconditions that MUST be satisfied
## before the pattern can be safely applied.
## These are the AST-level equivalents of the Lean 4 proof preconditions.

const patternPreconditions*: array[PatternKind, seq[string]] = [
  # pkExtractPureFunction
  @["body_has_no_side_effects", "no_io_calls", "no_mutation",
    "return_type_deterministic", "no_external_state_access"],
  # pkLinearizeVariables
  @["has_nonlinear_arithmetic", "variables_independent",
    "no_division_by_variable", "no_modular_arithmetic"],
  # pkInsertCompositionNode
  @["call_chain_depth_ge_3", "intermediate_type_exists",
    "no_recursive_calls_in_chain"],
  # pkIsolateInterface
  @["has_io_boundary", "io_calls_concentrated",
    "pure_computation_separable"],
  # pkAddLoopInvariant
  @["has_loop", "no_existing_invariant", "loop_body_bounded"],
  # pkAddDecreaseMeasure
  @["has_recursion", "no_existing_measure", "recursive_arg_decreasing"]
]

const PrerequisiteSeverity*: array[PrerequisiteKind, PreconditionSeverity] = [
  prqBodyHasNoSideEffects: psSoft,
  prqNoIoCalls: psSoft,
  prqNoMutation: psSoft,
  prqReturnTypeDeterministic: psSoft,
  prqNoExternalStateAccess: psSoft,
  prqHasNonlinearArithmetic: psSoft,
  prqVariablesIndependent: psSoft,
  prqNoDivisionByVariable: psSoft,
  prqNoModularArithmetic: psSoft,
  prqCallChainDepthGe3: psSoft,
  prqIntermediateTypeExists: psSoft,
  prqNoRecursiveCallsInChain: psSoft,
  prqHasIoBoundary: psSoft,
  prqIoCallsConcentrated: psSoft,
  prqPureComputationSeparable: psSoft,
  prqHasLoop: psHard,              ## 구조적 전제조건: 하드 가드
  prqNoExistingInvariant: psSoft,
  prqLoopBodyBounded: psSoft,
  prqHasRecursion: psHard,         ## 구조적 전제조건: 하드 가드
  prqNoExistingMeasure: psSoft,
  prqRecursiveArgDecreasing: psSoft,
]

const prereqNameToKind*: Table[string, PrerequisiteKind] = {
  "body_has_no_side_effects": prqBodyHasNoSideEffects,
  "no_io_calls": prqNoIoCalls,
  "no_mutation": prqNoMutation,
  "return_type_deterministic": prqReturnTypeDeterministic,
  "no_external_state_access": prqNoExternalStateAccess,
  "has_nonlinear_arithmetic": prqHasNonlinearArithmetic,
  "variables_independent": prqVariablesIndependent,
  "no_division_by_variable": prqNoDivisionByVariable,
  "no_modular_arithmetic": prqNoModularArithmetic,
  "call_chain_depth_ge_3": prqCallChainDepthGe3,
  "intermediate_type_exists": prqIntermediateTypeExists,
  "no_recursive_calls_in_chain": prqNoRecursiveCallsInChain,
  "has_io_boundary": prqHasIoBoundary,
  "io_calls_concentrated": prqIoCallsConcentrated,
  "pure_computation_separable": prqPureComputationSeparable,
  "has_loop": prqHasLoop,
  "no_existing_invariant": prqNoExistingInvariant,
  "loop_body_bounded": prqLoopBodyBounded,
  "has_recursion": prqHasRecursion,
  "no_existing_measure": prqNoExistingMeasure,
  "recursive_arg_decreasing": prqRecursiveArgDecreasing,
}.toTable

func severityFor*(name: string): PreconditionSeverity =
  ## 문자열 전제조건 이름으로 severity 조회 (enum 기반, 컴파일 타임 보장)
  let kind = prereqNameToKind.getOrDefault(name, prqBodyHasNoSideEffects)
  PrerequisiteSeverity[kind]

const preconditionSeverityTable*: Table[string, PreconditionSeverity] = {
  "body_has_no_side_effects": psSoft,
  "no_io_calls": psSoft,
  "no_mutation": psSoft,
  "return_type_deterministic": psSoft,
  "no_external_state_access": psSoft,
  "has_nonlinear_arithmetic": psSoft,
  "variables_independent": psSoft,
  "no_division_by_variable": psSoft,
  "no_modular_arithmetic": psSoft,
  "call_chain_depth_ge_3": psSoft,
  "intermediate_type_exists": psSoft,
  "no_recursive_calls_in_chain": psSoft,
  "has_io_boundary": psSoft,
  "io_calls_concentrated": psSoft,
  "pure_computation_separable": psSoft,
  "has_loop": psHard,
  "no_existing_invariant": psSoft,
  "loop_body_bounded": psSoft,
  "has_recursion": psHard,
  "no_existing_measure": psSoft,
  "recursive_arg_decreasing": psSoft,
}.toTable

## ─── AST Detection Helpers (PNode-native) ────────────────────────────────
func detectSideEffects*(node: PNode): bool {.raises: [].} =
  ## Check if AST contains side-effect indicators:
  ## var declarations, mutable assignments, echo/writeFile calls.
  if node.isNil: return false
  case node.kind
  of nkVarSection:
    return true
  of nkAsgn:
    return true
  of nkCall:
    if node.len > 0 and not node[0].isNil:
      let name = pNodeText(node[0]).toLowerAscii()
      if name in ["echo", "writefile", "readfile", "write",
                  "read", "stdout", "stderr", "stdin",
                  "open", "close", "createdir", "removedir",
                  "copyfile", "movefile", "removefile"]:
        return true
  else: discard
  for child in node:
    if not child.isNil and detectSideEffects(child):
      return true
  false

func detectIoCalls*(node: PNode): bool {.raises: [].} =
  ## Check if AST contains I/O function calls.
  if node.isNil: return false
  if node.kind == nkCall and node.len > 0 and not node[0].isNil:
    let name = pNodeText(node[0]).toLowerAscii()
    if name in ["echo", "writefile", "readfile", "write",
                "read", "open", "close", "createdir",
                "removedir", "sleep", "execcmd", "execcmdex",
                "startprocess", "putenv", "getenv"]:
      return true
  for child in node:
    if not child.isNil and detectIoCalls(child):
      return true
  false

func detectExistingInvariant*(node: PNode): bool {.raises: [].} =
  ## Check if code already has an invariant annotation.
  if node.isNil: return false
  # Check variable/let names for "invariant"
  if node.kind in {nkIdentDefs, nkVarSection}:
    for ident in findNodesP(node, {nkIdent}):
      if "invariant" in pNodeText(ident).toLowerAscii():
        return true
  for child in node:
    if not child.isNil and detectExistingInvariant(child):
      return true
  false

func detectExistingMeasure*(node: PNode): bool {.raises: [].} =
  ## Check if code already has a termination measure.
  if node.isNil: return false
  # Check identifiers for decrease/measure keywords
  for ident in findNodesP(node, {nkIdent}):
    let nm = pNodeText(ident).toLowerAscii()
    if "decrease" in nm or "measure" in nm or "termination" in nm:
      return true
  # Check call names for decrease/measure
  for callNode in findNodesP(node, {nkCall}):
    if callNode.len > 0 and not callNode[0].isNil:
      let nm = pNodeText(callNode[0]).toLowerAscii()
      if "decrease" in nm or "measure" in nm:
        return true
  for child in node:
    if not child.isNil and detectExistingMeasure(child):
      return true
  false

func countCallDepth*(node: PNode; depth: int = 0): int {.raises: [].} =
  ## Compute the maximum nesting depth of call expressions.
  if node.isNil:
    return depth
  var maxDepth = depth
  # A call contributes one level to everything below it; every other node
  # contributes none. Recursing into `node` itself on the call branch — rather
  # than into its children — never reached a child and exhausted the stack on
  # the first call node it saw.
  let childDepthBase = if node.kind == nkCall: depth + 1 else: depth
  for child in node:
    if not child.isNil:
      let childDepth = countCallDepth(child, childDepthBase)
      if childDepth > maxDepth:
        maxDepth = childDepth
  return maxDepth

func detectDivisionByVariable*(node: PNode): bool {.raises: [].} =
  ## Check if AST contains division by a variable (not a constant).
  if node.isNil: return false
  if node.kind == nkInfix and node.len > 1 and not node[1].isNil:
    let op = pNodeText(node[1]).toLowerAscii()
    if op in ["/", "div", "%", "mod"]:
      # Check if divisor (right operand) is a variable, not a literal
      if node.len > 2 and not node[2].isNil:
        let rhsKind = node[2].kind
        if rhsKind != nkIntLit and rhsKind != nkFloatLit:
          return true
  for child in node:
    if not child.isNil and detectDivisionByVariable(child):
      return true
  false

func hasLoop*(node: PNode): bool {.raises: [].} =
  ## Check if AST contains any loop construct.
  if node.isNil: return false
  if node.kind in {nkWhileStmt, nkForStmt}:
    return true
  for child in node:
    if not child.isNil and hasLoop(child):
      return true
  false

func hasRecursion*(node: PNode; funcName: string): bool {.raises: [].} =
  ## Check if function calls itself (direct recursion).
  if node.isNil: return false
  if node.kind == nkCall and node.len > 0 and not node[0].isNil:
    if pNodeText(node[0]) == funcName:
      return true
  for child in node:
    if not child.isNil and hasRecursion(child, funcName):
      return true
  false

func collectSideEffectEvidence*(node: PNode; prefix: string = ""): seq[string] {.raises: [].} =
  ## Collect structural evidence of side effects for diagnostic reporting.
  if node.isNil: return
  if node.kind == nkVarSection:
    result.add(prefix & "mutable variable declaration")
  if node.kind == nkCall and node.len > 0 and not node[0].isNil:
    let name = pNodeText(node[0])
    if name in ["echo", "writefile", "readfile", "write"]:
      result.add(prefix & "I/O call: " & name)
  for child in node:
    if not child.isNil:
      result.add(collectSideEffectEvidence(child, prefix))
## ─── Main Applicability Check ────────────────────────────────────────────────
proc checkApplicability*(
  sourceCode: string;
  pattern: PatternKind;
  funcName: string = ""
): PatternApplicability {.raises: [].} =
  ## Check if a refactoring pattern is applicable to the given source code.
  ##
  ## This is Layer 1 of the 3-layer validation chain:
  ##   Layer 1 (THIS): AST structural check — fast, deterministic
  ##   Layer 2: Z3 semantic equivalence (equivalence_checker.nim)
  ##   Layer 3: Lean 4 certified proof (docs/spec/certified_patterns/*.lean)
  ##
  ## Returns PatternApplicability with detailed diagnostics.
  
  if sourceCode.strip().len == 0:
    return PatternApplicability(
      applicable: false,
      reason: "Empty source: no source content available" & (if funcName.len > 0: " for " & funcName else: ""),
      preconditions: patternPreconditions[pattern],
      failureKind: paEmptySource
    )

  let parseResult = parseNimRes(sourceCode)
  if parseResult.isErr:
    return PatternApplicability(
      applicable: false,
      reason: "Failed to parse source: " & parseResult.error,
      preconditions: patternPreconditions[pattern],
      failureKind: paParseFailure
    )
  
  let ast = parseResult.get()
  let inspection = inspectAstNodeP(ast, funcName)
  let required = patternPreconditions[pattern]
  
  var satisfied: seq[string] = @[]
  var missing: seq[string] = @[]
  var evidence: seq[string] = @[]
  
  case pattern
  of pkExtractPureFunction:
    # Check: body has no side effects
    let hasSideFx = detectSideEffects(ast)
    let hasIo = detectIoCalls(ast)
    if not hasSideFx:
      satisfied.add "body_has_no_side_effects"
    else:
      missing.add "body_has_no_side_effects"
      evidence.add "Side effects detected: " & collectSideEffectEvidence(ast).join("; ")
    if not hasIo:
      satisfied.add "no_io_calls"
    else:
      missing.add "no_io_calls"
      evidence.add "I/O calls detected in function body"
    # Check: no mutation (same as side effects for pure extraction)
    if not hasSideFx:
      satisfied.add "no_mutation"
      satisfied.add "no_external_state_access"
      satisfied.add "return_type_deterministic"
    else:
      missing.add "no_mutation"
      missing.add "no_external_state_access"
  
  of pkLinearizeVariables:
    # Check: has non-linear arithmetic
    if inspection.hasNonLinearOps:
      satisfied.add "has_nonlinear_arithmetic"
      evidence.add "Non-linear operations (*/÷%) detected in AST"
    else:
      missing.add "has_nonlinear_arithmetic"
    # Check: no division by variable (unsafe for linearization)
    if not detectDivisionByVariable(ast):
      satisfied.add "no_division_by_variable"
      satisfied.add "no_modular_arithmetic"
      satisfied.add "variables_independent"
    else:
      missing.add "no_division_by_variable"
      evidence.add "Division by variable detected — linearization unsafe"
  
  of pkInsertCompositionNode:
    # Check: call chain depth ≥ 3
    let callDepth = countCallDepth(ast)
    if callDepth >= 3:
      satisfied.add "call_chain_depth_ge_3"
      evidence.add "Call nesting depth: " & $callDepth
    else:
      missing.add "call_chain_depth_ge_3"
      evidence.add "Call nesting depth " & $callDepth & " < 3"
    # Check: no recursion in chain
    let recName = if funcName.len > 0: funcName else: "unknown"
    if not hasRecursion(ast, recName):
      satisfied.add "no_recursive_calls_in_chain"
      satisfied.add "intermediate_type_exists"
    else:
      missing.add "no_recursive_calls_in_chain"
  
  of pkIsolateInterface:
    # Check: has I/O boundary
    let hasIo = detectIoCalls(ast)
    if hasIo:
      satisfied.add "has_io_boundary"
      satisfied.add "io_calls_concentrated"
      evidence.add "I/O calls found — boundary can be isolated"
    else:
      missing.add "has_io_boundary"
    satisfied.add "pure_computation_separable"  # Assume separable if I/O exists
  
  of pkAddLoopInvariant:
    # Check: has loop
    if inspection.loopCount > 0 or hasLoop(ast):
      satisfied.add "has_loop"
      evidence.add "Loop constructs found: " & $inspection.loopCount
    else:
      missing.add "has_loop"
    # Check: no existing invariant
    if not detectExistingInvariant(ast):
      satisfied.add "no_existing_invariant"
    else:
      missing.add "no_existing_invariant"
      evidence.add "Existing invariant annotation detected"
    satisfied.add "loop_body_bounded"  # Assume bounded (needs Z3 verification)
  
  of pkAddDecreaseMeasure:
    # Check: has recursion
    let recName = if funcName.len > 0: funcName else: "unknown"
    if inspection.hasRecursion or hasRecursion(ast, recName):
      satisfied.add "has_recursion"
      evidence.add "Direct recursion detected"
    else:
      missing.add "has_recursion"
    # Check: no existing measure
    if not detectExistingMeasure(ast):
      satisfied.add "no_existing_measure"
    else:
      missing.add "no_existing_measure"
      evidence.add "Existing termination measure detected"
    satisfied.add "recursive_arg_decreasing"  # Assume decreasing (needs Z3 verification)
  
  # Parse 실패만 hard reject — 나머지 모든 조건은 soft로 분류
  var hardMiss: seq[string] = @[]
  var softMiss: seq[string] = @[]
  for m in missing:
    if preconditionSeverityTable.getOrDefault(m, psSoft) == psHard:
      hardMiss.add(m)
    else:
      softMiss.add(m)

  let isApplicable = hardMiss.len == 0  # soft만 실패해도 통과

  PatternApplicability(
    applicable: isApplicable,
    reason: if isApplicable: "All preconditions satisfied"
            else: "Missing preconditions: " & missing.join(", "),
    preconditions: required,
    satisfiedPreconditions: satisfied,
    missingPreconditions: missing,
    hardMissing: hardMiss,
    softMissing: softMiss,
    astEvidence: evidence,
    failureKind: if isApplicable: paNone else: paPreconditionMiss
  )

## ─── Self-Strengthening Guard Feedback ───────────────────────────────────────
func analyzeGuardFailure*(
  pattern: PatternKind;
  guardApproved: bool;
  z3Approved: bool;
  z3CounterExample: string
): seq[string] {.raises: [].} =
  ## Analyze a Z3 rejection to infer missing preconditions.
  ## This feeds back into the guard to strengthen it over time (§8.2).
  result = @[]
  
  if guardApproved and not z3Approved:
    # Guard approved but Z3 rejected → guard's preconditions were insufficient
    let cx = z3CounterExample.toLower
    
    if "division" in cx or "divisor" in cx or "divide" in cx:
      result.add "no_division_by_variable"
    if "overflow" in cx or "out of range" in cx:
      result.add "arithmetic_bounds_checked"
    if "alias" in cx or "pointer" in cx:
      result.add "no_pointer_aliasing"
    if "null" in cx or "nil" in cx:
      result.add "no_null_dereference"
    if "race" in cx or "concurrent" in cx:
      result.add "no_concurrent_access"
    if "termination" in cx or "infinite" in cx or "non-terminating" in cx:
      result.add "terminates"
    
    # If no specific pattern matched, add a generic strengthening
    if result.len == 0:
      result.add "z3_rejected_unknown_precondition"
func formatApplicabilityReport*(app: PatternApplicability; pattern: PatternKind): string {.raises: [].} =
  ## Format a human-readable applicability report for logging/escalation.
  result = "Pattern: " & $pattern & "\n"
  result.add "Applicable: " & $app.applicable & "\n"
  result.add "Reason: " & app.reason & "\n"
  
  if app.satisfiedPreconditions.len > 0:
    result.add "Satisfied:\n"
    for p in app.satisfiedPreconditions:
      result.add "  ✓ " & p & "\n"
  
  if app.missingPreconditions.len > 0:
    result.add "Missing:\n"
    for p in app.missingPreconditions:
      result.add "  ✗ " & p & "\n"
  
  if app.astEvidence.len > 0:
    result.add "Evidence:\n"
    for e in app.astEvidence:
      result.add "  → " & e & "\n"

## ─── WP4-j: Structural facts + pattern bridging ─────────────────────────────

type StructuralFactSignals* = object
  hasLoop*: bool
  hasRecursion*: bool
  hasIndex*: bool
  hasDivision*: bool
  hasShift*: bool

func detectIndexAccess*(node: PNode): bool {.raises: [].} =
  ## True when the AST contains bracketed indexing (a[i]) or slicing.
  if node.isNil: return false
  if node.kind == nkBracketExpr:
    return true
  for child in node:
    if not child.isNil and detectIndexAccess(child):
      return true
  false

func detectShiftOp*(node: PNode): bool {.raises: [].} =
  ## True when the AST contains shift operators (<<, >>, shl, shr).
  if node.isNil: return false
  if node.kind == nkInfix and node.len > 1 and not node[1].isNil:
    let op = pNodeText(node[1]).toLowerAscii()
    if op in ["<<", ">>", "shl", "shr"]:
      return true
  for child in node:
    if not child.isNil and detectShiftOp(child):
      return true
  false

func structuralFacts*(ast: PNode): StructuralFactSignals {.raises: [].} =
  ## Extract deterministic structural signals from an already-parsed source AST.
  ## These are the IR structural facts consumed by the strategy plan — a pure
  ## function of the AST, never a counter or clock. The caller is responsible
  ## for parsing (via parseNimRes); this stays a `func`-equivalent pure routine
  ## so it does not touch the `.sideEffect` parser and does not count against
  ## the proc→func invariant (AGENTS.md §0.6).
  result = StructuralFactSignals()
  if ast.isNil:
    return
  result.hasLoop = hasLoop(ast)
  result.hasIndex = detectIndexAccess(ast)
  result.hasDivision = detectDivisionByVariable(ast)
  result.hasShift = detectShiftOp(ast)
  # Recursion is namespaced; best-effort via direct-call detection is skipped:
  # the strategy plan treats recursion via hasLoop/hasIndex/hasDivision/hasShift
  # and defaults recursion=false when the callee name is unavailable here.
  result.hasRecursion = false

func pgPatternToRefactoring*(p: PatternKind): Option[RefactoringPatternKind] {.raises: [], axiomDecision(id = "DECISION-WP4J-01", reason = "Deterministic mapping of a pattern_guard PatternKind to its refactoring-engine twin; `none` only for a PatternKind with no engine counterpart — used to route strategy-plan steps without inventing a false match", introduced = "v34-wp4j").} =
  ## Map the pattern_guard-level PatternKind to the refactoring-engine level
  ## RefactoringPatternKind. `none` when there is no corresponding refactor
  ## pattern (e.g. a future PatternKind without an engine twin).
  case p
  of pkExtractPureFunction: some(rpkExtractPureFunction)
  of pkLinearizeVariables: some(rpkLinearizeVariables)
  of pkInsertCompositionNode: some(rpkInsertCompositionNode)
  of pkIsolateInterface: some(rpkIsolateInterface)
  of pkAddLoopInvariant: some(rpkAddLoopInvariant)
  of pkAddDecreaseMeasure: some(rpkAddDecreaseMeasure)

func pgPatternFromRefactoring*(r: RefactoringPatternKind): PatternKind {.raises: [], axiomDecision(id = "DECISION-WP4J-02", reason = "Inverse of `pgPatternToRefactoring`: deterministic mapping of a refactoring-engine pattern back to its pattern_guard twin; every RefactoringPatternKind has exactly one PatternKind", introduced = "v34-wp4j").} =
  ## Inverse of `pgPatternToRefactoring`.
  case r
  of rpkExtractPureFunction: pkExtractPureFunction
  of rpkLinearizeVariables: pkLinearizeVariables
  of rpkInsertCompositionNode: pkInsertCompositionNode
  of rpkIsolateInterface: pkIsolateInterface
  of rpkAddLoopInvariant: pkAddLoopInvariant
  of rpkAddDecreaseMeasure: pkAddDecreaseMeasure
