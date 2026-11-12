## Refactoring Engine — machine-actionable refactoring rules for unverifiable code.
##
## Maps complexity signals from diagnostics_engine to specific Nim refactoring patterns.
## Each rule produces a RefactoringTemplate that can be applied and Z3-verified.
##
## Design: Phase 3 of ax prove architecture refactor.
## Escape strategy: 3 consecutive Z3 rejections → escalation to human architect.

import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

import std/algorithm
import std/math
import std/options
import std/strutils
import core/types/domain_types
import core/utils/text_utils
import core/logic/refinement_string
import core/solver/equivalence_checker
import core/diagnostics/pattern_guard as pg
import core/diagnostics/strategy_plan
import core/parser_utils  # parseNimRes — parsing stays at the engine boundary (proc), facts are func
import core/types/results  # Result.isOk/isErr/get value accessors for parseNimRes

import core/types/hubs/refactoring_hub
import core/types/refactor_task_types  # RefactorResult, RefactorStatus, etc.
import core/types/obligation_evidence  # ObligationEvidence, emptyEvidence, withLayer
export refactoring_hub

type
  ProgressMetric* = object
    unsatCoreSize*: int
    invariantCount*: int
    leanKernelVerified*: bool
    proofDepth*: int
    roundIndex*: int

  RefactoringStagnation* = object
    consecutiveFailures*: int
    maxFailures*: int            ## Default 3
    escalated*: bool
    escalationReport*: string
    metricsHistory*: seq[ProgressMetric]  # NEW


func computeSynergyMetrics*(signals: seq[RefactoringSignalKind]): SynergyMetrics {.raises: [].} =
  if signals.len == 0:
    return SynergyMetrics(fFactor: -1.0, gFactor: -1.0, hFactor: -1.0, geometricMean: -1.0)
  var f = 1.0
  var g = 1.0
  var h = 1.0
  for signal in signals:
    case signal
    of rskQuantifierExcess: f -= 0.15
    of rskNonLinearArithmetic: g -= 0.20
    of rskDeepDependency: h -= 0.15
    of rskHighCoupling: h -= 0.20
    of rskMissingLoopInvariant: f -= 0.10
    of rskMissingDecreaseMeasure: f -= 0.10
  result.fFactor = max(0.0, min(1.0, f))
  result.gFactor = max(0.0, min(1.0, g))
  result.hFactor = max(0.0, min(1.0, h))
  let product = result.fFactor * result.gFactor * result.hFactor
  if product <= 0.0:
    result.geometricMean = 0.0
  else:
    result.geometricMean = pow(product, 1.0/3.0)

const
  defaultMaxRefactoringFailures* = 3

  signalPatternTable*: array[RefactoringSignalKind, RefactoringPatternKind] = [
    rpkExtractPureFunction,      # rskQuantifierExcess
    rpkLinearizeVariables,       # rskNonLinearArithmetic
    rpkInsertCompositionNode,    # rskDeepDependency
    rpkIsolateInterface,         # rskHighCoupling
    rpkAddLoopInvariant,         # rskMissingLoopInvariant
    rpkAddDecreaseMeasure        # rskMissingDecreaseMeasure
  ]

  patternDescriptions*: array[RefactoringPatternKind, string] = [
    "Extract quantifier scope into a pure function to reduce proof obligations",
    "Replace multiplication/nonlinear constraints with linear auxiliary variables",
    "Insert intermediate composition node to decompose proof obligation",
    "Isolate boundary contract from external interface coupling",
    "Add explicit loop invariant annotation for bounded verification",
    "Add termination measure (decrease clause) for recursive functions"
  ]

  patternNimHints*: array[RefactoringPatternKind, string] = [
    "func extractedPure(...): T = ... # move quantified body here",
    "let auxLinear = f(x) # decompose nonlinear term",
    "func intermediate(...): T = ... # composition node",
    "func boundaryContract(...): T = ... # interface isolation",
    "var invariant: bool = ... # loop invariant",
    "func decreaseMeasure(...): int = ... # termination proof"
  ]

  patternSeverities: array[RefactoringPatternKind, PreconditionSeverity] = [
    rpkExtractPureFunction: psSoft,
    rpkLinearizeVariables: psSoft,
    rpkInsertCompositionNode: psSoft,
    rpkIsolateInterface: psSoft,
    rpkAddLoopInvariant: psHard,
    rpkAddDecreaseMeasure: psHard,
  ]

func initRefactoringStagnation*(maxFailures: int = defaultMaxRefactoringFailures): RefactoringStagnation =
  RefactoringStagnation(
    consecutiveFailures: 0,
    maxFailures: maxFailures,
    escalated: false,
    escalationReport: "",
    metricsHistory: @[]
  )

func recordFailure*(stagnation: var RefactoringStagnation; reason: string) =
  inc stagnation.consecutiveFailures
  if stagnation.consecutiveFailures >= stagnation.maxFailures:
    stagnation.escalated = true
    stagnation.escalationReport =
      "REFORMATTING ESCALATED after " & $stagnation.consecutiveFailures & " consecutive failures.\n" &
      "Last failure: " & reason & "\n" &
      "Recommendation: Manual architectural review required."

func recordSuccess*(stagnation: var RefactoringStagnation) =
  stagnation.consecutiveFailures = 0

func recordProgress*(stagnation: var RefactoringStagnation; metric: ProgressMetric) {.raises: [].} =
  if metric.unsatCoreSize < 0:
    stagnation.escalated = true
    stagnation.escalationReport = "MEASUREMENT INVALID: unsat core extraction failed"
    return
  stagnation.metricsHistory.add(metric)
  let histLen = stagnation.metricsHistory.len
  if histLen >= 3:
    let last = stagnation.metricsHistory[histLen - 1].unsatCoreSize
    let prev = stagnation.metricsHistory[histLen - 2].unsatCoreSize
    let prev2 = stagnation.metricsHistory[histLen - 3].unsatCoreSize
    # H2: Stagnation — unchanged for 3 consecutive rounds
    if last == prev and prev == prev2:
      stagnation.escalated = true
      stagnation.escalationReport = "STAGNATION: unsatCoreSize frozen for 3 rounds"
  if histLen >= 2:
    let last = stagnation.metricsHistory[histLen - 1].unsatCoreSize
    let prev = stagnation.metricsHistory[histLen - 2].unsatCoreSize
    # H3: Regression — increased from previous round
    if last > prev:
      stagnation.escalated = true
      stagnation.escalationReport = "REGRESSION: unsatCoreSize increased"

func classifySignals*(
  quantifierCount: int;
  nonLinearArithmeticCount: int;
  dependencyDepth: int;
  couplingScore: int;
  hasLoop: bool;
  hasRecursion: bool
): seq[RefactoringSignalKind] =
  if quantifierCount > 0: result.add(rskQuantifierExcess)
  if nonLinearArithmeticCount > 0: result.add(rskNonLinearArithmetic)
  if dependencyDepth >= 3: result.add(rskDeepDependency)
  if couplingScore > 5: result.add(rskHighCoupling)
  if hasLoop: result.add(rskMissingLoopInvariant)
  if hasRecursion: result.add(rskMissingDecreaseMeasure)

func generateTemplates*(signals: seq[RefactoringSignalKind]): seq[RefactoringTemplate] =
  for signal in signals:
    let pattern = signalPatternTable[signal]
    result.add(RefactoringTemplate(
      signal: signal,
      pattern: pattern,
      description: patternDescriptions[pattern],
      nimHint: patternNimHints[pattern],
      priority: ord(signal),  # higher signal kind = higher priority
      severity: patternSeverities[pattern]
    ))
  # Sort by priority (descending)
  result.sort(proc (a, b: RefactoringTemplate): int = cmp(b.priority, a.priority), Descending)

proc applyRefactoringTemplate*(
  sourceCode: string;
  vulnerabilityKind: string;
  z3Check: proc(query: string): bool {.closure, gcsafe, raises: [CatchableError].} = nil;
  z3ModelQuery: proc(query: string): string {.closure, gcsafe, raises: [CatchableError].} = nil
): RefactorResult {.raises: [CatchableError].} =
  ## Map vulnerability kind to refactoring signal and apply line-level template.
  let signal = case vulnerabilityKind
    of "vkBufferOverflow": rskDeepDependency
    of "vkNullPointerDereference": rskQuantifierExcess
    of "vkIntegerOverflowUnderflow": rskNonLinearArithmetic
    of "vkGhostUpdate": rskHighCoupling
    of "vkDeadlockRaceCondition": rskMissingLoopInvariant
    else: return RefactorResult(status: rsEscalated, escalateReason: erGuardHardReject, contextLog: "unknown vulnerability: " & vulnerabilityKind, evidence: emptyEvidence().withLayer("StructuralAST", leFailedSat))

  var pattern = signalPatternTable[signal]

  ## Layer 1 Guard: AST-level precondition validation before pattern application.
  ## This prevents applying patterns to code that doesn't meet structural prerequisites.
  let guardPattern = case pattern
    of rpkExtractPureFunction: pg.pkExtractPureFunction
    of rpkLinearizeVariables: pg.pkLinearizeVariables
    of rpkInsertCompositionNode: pg.pkInsertCompositionNode
    of rpkIsolateInterface: pg.pkIsolateInterface
    of rpkAddLoopInvariant: pg.pkAddLoopInvariant
    of rpkAddDecreaseMeasure: pg.pkAddDecreaseMeasure
  var guardResult = pg.checkApplicability(sourceCode, guardPattern)
  if not guardResult.applicable:
    ## WP4-j: pattern mismatch is a STRATEGY failure, not a candidate failure.
    ## A hard `paParseFailure` or `paEmptySource` is genuinely terminal and
    ## stays fail-closed. A `paPreconditionMiss` (structural shape mismatch)
    ## is recoverable: consult the deterministic obligation-driven strategy
    ## plan and retry the next plan step that is applicable to this source.
    case guardResult.failureKind
    of paParseFailure, paEmptySource:
      return RefactorResult(status: rsEscalated, escalateReason: erGuardHardReject, contextLog: guardResult.reason, evidence: emptyEvidence().withLayer("StructuralAST", leFailedSat))
    of paPreconditionMiss, paNone:
      # Compute structural facts from the current source to drive the plan.
      # This is a pure function of (structural facts, obligation capability);
      # retry is plan-index advance, never an attempt counter. Parsing happens
      # here at the engine boundary (proc), facts stay pure (func); a parse
      # failure yields zero signals deterministically (termination preserved).
      var astFacts = StructuralFactSignals()
      let pr = parseNimRes(sourceCode)
      if pr.isOk:
        astFacts = pg.structuralFacts(pr.get())
      let plan = computeStrategyPlan(
        obligationCount = 0,          # refactor guard runs pre-IR; obligations arrive downstream
        obligationKinds = @[],
        hasLoop = astFacts.hasLoop,
        hasRecursion = astFacts.hasRecursion,
        hasIndex = astFacts.hasIndex,
        hasDivision = astFacts.hasDivision,
        hasShift = astFacts.hasShift
      )
      # Try the next applicable strategy in canonical order, starting after the
      # current pattern. Whichever is applicable first becomes the active pattern.
      var fallback: Option[RefactoringPatternKind] = none(RefactoringPatternKind)
      for step in plan.steps:
        let candidatePg = step.pattern
        if candidatePg == guardPattern:
          continue  # skip the very pattern that already failed
        let candidateRpk = pg.pgPatternToRefactoring(candidatePg)
        if candidateRpk.isNone:
          continue
        let candGuard = pg.checkApplicability(sourceCode, candidatePg)
        if candGuard.applicable:
          fallback = some(candidateRpk.get())
          break
      if fallback.isSome:
        # The failed guard pattern is replaced by an applicable fallback; keep
        # the original escalated reason attached for traceability through
        # `pattern` substitution below.
        guardResult = pg.checkApplicability(sourceCode, pg.pgPatternFromRefactoring(fallback.get()))
        pattern = fallback.get()
      else:
        # Plan exhausted — explicit accounting terminal (not silent pass).
        return RefactorResult(status: rsEscalated, escalateReason: erGuardHardReject,
          contextLog: "strategy plan exhausted after pattern mismatch: " & guardResult.reason,
          evidence: emptyEvidence().withLayer("StructuralAST", leFailedSat))
  # Soft-miss transparent path: applicable=true with softMissing > 0
  # means hard-only check passed; transformation proceeds transparently.
  # Soft miss info is captured via RefactorResult if needed downstream.

  var updated = sourceCode
  var changed = false

  case pattern
  of rpkAddLoopInvariant:
    let lines = sourceCode.splitLines()
    # Idempotency guard: skip if invariant already inserted before loop
    var alreadyApplied = false
    for line in lines:
      if line.strip().startsWith("var invariant: bool"):
        alreadyApplied = true
        break
    if not alreadyApplied:
      var output: seq[string] = @[]
      var inserted = false
      for line in lines:
        let stripped = line.strip()
        if not inserted and (stripped.startsWith("for ") or stripped.startsWith("while ")):
          let indent = leadingWhitespace(line)
          output.add(indent & "var invariant: bool = true")
          inserted = true
        output.add(line)
      if inserted:
        updated = output.join("\n")
        changed = true
  of rpkExtractPureFunction:
    let lines = sourceCode.splitLines()
    # Idempotency guard: skip if extraction stub already inserted
    var alreadyApplied = false
    for line in lines:
      if "extractedPure()" in line:
        alreadyApplied = true
        break
    if not alreadyApplied:
      var output: seq[string] = @[]
      var inserted = false
      for line in lines:
        let stripped = line.strip()
        if not inserted and (stripped.startsWith("proc ") or stripped.startsWith("func ")):
          let indent = leadingWhitespace(line)
          output.add(indent & "func extractedPure(): auto =")
          output.add(indent & "  discard ## extracted pure body")
          inserted = true
        output.add(line)
      if inserted:
        updated = output.join("\n")
        changed = true
  of rpkLinearizeVariables:
    let lines = sourceCode.splitLines()
    var output: seq[string] = @[]
    for line in lines:
      let stripped = line.strip()
      if " = " in stripped:
        let parts = stripped.split(" = ")
        if parts.len > 2:
          let indent = leadingWhitespace(line)
          for i in 1 ..< parts.len:
            output.add(indent & parts[i-1].strip() & " = " & parts[i].strip())
          changed = true
          continue
      output.add(line)
    if changed:
      updated = output.join("\n")
  of rpkInsertCompositionNode:
    let lines = sourceCode.splitLines()
    var output: seq[string] = @[]
    var inserted = false
    for line in lines:
      let stripped = line.strip()
      if not inserted and stripped.count('(') > 3:
        let indent = leadingWhitespace(line)
        output.add(indent & "## [AUTOGEN] Nested call depth: " & $stripped.count('(') & ". " &
                 "Consider extracting intermediate result to reduce nesting.")
        inserted = true
      output.add(line)
    if inserted:
      updated = output.join("\n")
      changed = true
  of rpkIsolateInterface:
    let lines = sourceCode.splitLines()
    var output: seq[string] = @[]
    var inserted = false
    for line in lines:
      let stripped = line.strip()
      if not inserted and stripped.startsWith("func ") and sourceCode.find("proc ") >= 0:
        let indent = leadingWhitespace(line)
        output.add(indent & "## [AUTOGEN] I/O boundary detected: func alongside proc. " &
                 "Consider extracting I/O to a dedicated wrapper proc.")
        inserted = true
      output.add(line)
    if inserted:
      updated = output.join("\n")
      changed = true
  of rpkAddDecreaseMeasure:
    let lines = sourceCode.splitLines()
    # Idempotency guard: skip if decreasing pragma already inserted
    var alreadyApplied = false
    for line in lines:
      if line.strip().startsWith("{.decreasing.}"):
        alreadyApplied = true
        break
    if not alreadyApplied:
      var output: seq[string] = @[]
      var inserted = false
      for line in lines:
        let stripped = line.strip()
        if not inserted and (stripped.startsWith("proc ") or stripped.startsWith("func ")):
          let indent = leadingWhitespace(line)
          output.add(indent & "{.decreasing.}")
          inserted = true
        output.add(line)
      if inserted:
        updated = output.join("\n")
        changed = true

  # Early skip: no pattern transformation matched → avoid wasted Z3 verification.
  if not changed:
    return RefactorResult(status: rsSkipped, skipReason: srNoTransformApplied, softMisses: @[], evidence: emptyEvidence().withLayer("StructuralAST", leFailedUnknown))

  let fpBefore = computeSourceFingerprint(sourceCode)
  let fpAfter = computeSourceFingerprint(updated)
  if fpBefore == fpAfter:
    return RefactorResult(status: rsSkipped, skipReason: srNoTransformApplied, softMisses: @[], evidence: emptyEvidence().withLayer("StructuralAST", leFailedUnknown))

  # Tier 2: Z3 structural equivalence verification
  if z3Check != nil:
    var isEquivalent = true
    let equivQuery = buildEquivalenceQuery(sourceCode, updated, "refactored")
    try: isEquivalent = verifySemanticEquivalence(sourceCode, updated, "refactored", z3Check)
    except CatchableError: isEquivalent = false  # Z3 failure → reject refactoring
    if not isEquivalent:
      ## Phase A.4: Extract Z3 counterexample model when available.
      var evidence = emptyEvidence().withLayer("StructuralAST", leFailedSat)
      if equivQuery.len > 0 and z3ModelQuery != nil:
        try:
          let modelQuery = equivQuery & "\n(get-model)\n"
          let rawOutput = z3ModelQuery(modelQuery)
          if rawOutput.len > 0:
            let z3Model = extractZ3Model(rawOutput, "equivalence")
            evidence = evidence.withZ3Model(z3Model)
        except CatchableError: discard  # Model extraction is best-effort  # axiom:best-effort(ioboundary catch)
      return RefactorResult(status: rsEscalated, escalateReason: erZ3Rejected, contextLog: "Z3 equivalence check failed", evidence: evidence)

  ## Phase A.4: Evidence carries the layer trace; z3Model populated only on sat.
  return RefactorResult(status: rsVerified, refactoredSource: updated, evidence: emptyEvidence().withLayer("StructuralAST", leSucceeded))

func formatEscalationReport*(
  stagnation: RefactoringStagnation;
  originalCode: string;
  attemptedTemplates: seq[RefactoringTemplate];
  z3CounterExamples: seq[string]
): string =
  result.add("=== REFACTORING ESCALATION REPORT ===\n")
  result.add("Consecutive failures: " & $stagnation.consecutiveFailures & "\n\n")
  result.add("--- Original Code ---\n")
  result.add(originalCode & "\n\n")
  result.add("--- Attempted Transformations ---\n")
  for i, tmpl in attemptedTemplates:
    result.add($i & ". " & tmpl.description & "\n")
    result.add("   Hint: " & tmpl.nimHint & "\n")
    if i < z3CounterExamples.len:
      result.add("   Z3 counterexample: " & z3CounterExamples[i] & "\n")
  result.add("\n--- Recommendation ---\n")
  result.add("Manual architectural refactoring required.\n")
  result.add("Consider decomposing into smaller pure functions.\n")

{.pop.}
