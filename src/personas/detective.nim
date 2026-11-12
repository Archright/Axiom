import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [CatchableError].}

from core/boundary/verification_interface import StageKind, StageStatus, AbstractContext
import core/boundary/boundary_forwarding
import core/boundary/axiom_pragmas_boundary
import core/boundary/gateway_boundary
import core/boundary/results_boundary
import core/contracts/logic_contract
import core/contracts/orchestrator_contract
import core/contracts/solver_contract
import core/symbolic/symbolic_types_exec
import core/types/symbolic_types_exec
import core/symbolic/symbolic_types_expr
import core/types/z3_solver_config
import std/json
import std/osproc
import std/streams
import std/strutils
import std/tables
verifySpecCompleteness("detective", ModuleMetrics(
  hotspotDepth: 2.0,
  astNodeCount: 216.0,
  inDegree: 11.0
))

let ctx = defaultPersonaCtx

# @axiom-hint: lean="functionName.length ≥ 0 ∧ verificationVerdict.length ≥ 0" smt="(assert (and (>= (str.len functionName) 0) (>= (str.len verificationVerdict) 0)))"
# @axiom-hint: lean="functionName.length > 0" smt="(assert (and (> (str.len functionName) 0)))"
func detectiveLogLine(
  functionName: string;
  verificationVerdict: string;
  traceReport: TraceReport
): string {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let named = if functionName.len > 0: functionName else: "unknown"
  let suffix =
    if traceReport.vulnerabilityKind.len > 0:
      " / trace=" & traceReport.vulnerabilityKind
    else:
      ""
  "[Detective] Indictment complete: " & named & " verdict=" & verificationVerdict & suffix
proc buildTrackingSmtlib2*(candidates: seq[SymSExpr]): string {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if candidates.len == 0:
    return ""
  var smtParts: seq[string] = @[]
  smtParts.add("(set-option :produce-unsat-cores true)")
  var varSet = initTable[string, bool]()
  for c in candidates:
    let vars = sExprVariables(c)
    for v in vars:
      varSet[v] = true
  for v in varSet.keys:
    smtParts.add("(declare-const " & v & " Int)")
  for i, c in candidates:
    smtParts.add("(declare-const track_" & $i & " Bool)")
    smtParts.add("(assert (=> track_" & $i & " " & sExprToString(c) & "))")
  var trackVars: seq[string] = @[]
  for i in 0 ..< candidates.len:
    trackVars.add("track_" & $i)
  smtParts.add("(check-sat-assuming (" & trackVars.join(" ") & "))")
  smtParts.add("(get-unsat-core)")
  smtParts.join("\n")
proc extractUnsatCoreWithTracking*(trackingSmt: string): Result[seq[string], UnsatCoreExtractionStatus] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  var p: Process
  try:
    p = startProcess(resolveZ3Path(), args = @["-smt2", "-in"], options = {poUsePath})
  except CatchableError:
    return err(ucesProcessFailed)
  try:
    p.inputStream.write(trackingSmt & "\n")
    p.inputStream.close()
  except CatchableError:
    try:
      p.close()
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)
    return err(ucesIoError)
  var z3Output: string
  try:
    z3Output = p.outputStream.readAll()
  except CatchableError:
    try:
      p.close()
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)
    return err(ucesIoError)
  try:
    p.close()
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)
  let core = parseUnsatCore(z3Output)
  if core.len == 0 and "error" in z3Output:
    return err(ucesParseFailed)
  return ok(core)

## Open Case.
# @axiom-hint: lean="ast_parse_failed_isolated" smt="(assert ast_parse_failed_isolated)"
proc openCase*(
  req: UniversalPipelineRequest;
  translation: UniversalTranslation
): Result[DetectiveArtifact, AxiomError] {.raises: [], axiomEffect: IOEffect, tags: [RootEffect, AxiomIOEffect, IOEffect].} =
  ## Phase 2: Detective data-flow path.
  ## Initial heuristic scan followed by real CEGAR / fixed-point engine for loop invariant synthesis.
  try:
    ctx.logStage(skCegar, req.functionName, "opening case", 0, ssStarted, nil)
    let priorPromotion = ctx.loadPromotionFromProofVault(req)
    let initialScan = ctx.runNegativeInvariantSearch(translation, req.sourceCode, priorPromotion.invariant)

    # Real CEGAR / fixedpoint engine for abstract interpretation
    var invariant = priorPromotion.invariant
    var cegarSmtlib2 = ""
    var cegarEvidenceLog = ""
    var hasCegarCounterexample = false
    var unsatCoreVars: seq[string] = @[]
    var unsatCoreExtractionStatus = ucesNotAttempted
    let cfgRes = buildControlFlowGraph(req.sourceCode)
    if cfgRes.isOk:
      let cfg = cfgRes.get()
      let headerId = findPrimaryLoopHeader(cfg)
      if headerId >= 0:
        let indVars = ctx.detectInductionVariables(cfg, headerId)
        if indVars.len > 0:
          let fpResult = ctx.proveWithFixedpoint(cfg, headerId, indVars)
          if fpResult.invariant.len > 0:
            invariant = fpResult.invariant
          else:
            # Fixedpoint failed — fall back to CEGAR abstraction refinement
            # Build tracking SMT for unsat core extraction before CEGAR loop
            let intervals = ctx.analyzeVariableIntervalsAtLoopHeader(cfg, headerId)
            let loopCond = ctx.extractLoopConditionFromHeader(cfg, headerId)
            let abstractCtx = AbstractContext(intervals: intervals, loopCondition: loopCond, inductionVars: indVars, candidateInvariants: @[])
            let candidates = ctx.deriveInvariantCandidates(abstractCtx)
            let trackingSmt = buildTrackingSmtlib2(candidates)

            let z3Check = ctx.z3CheckViaProcess(resolveZ3Path(), @["-smt2", "-in"])
            let cegarRes = ctx.runCegarLoop(cfg, headerId, z3Check, maxIterations = 20, budgetMs = 30_000)
            cegarSmtlib2 = ctx.encodeProvedInvariantsSmtlib2(cegarRes.provedInvariants)
            cegarEvidenceLog = "CEGAR iterations=" & $cegarRes.iterations & " verdict=" & $cegarRes.verdict & " elapsedMs=" & $cegarRes.elapsedMs
            hasCegarCounterexample = (cegarRes.verdict == cegarCounterexample)
            if cegarRes.verdict == cegarCounterexample and trackingSmt.len > 0:
              let coreResult = extractUnsatCoreWithTracking(trackingSmt)
              if coreResult.isOk:
                unsatCoreVars = coreResult.get()
                unsatCoreExtractionStatus = ucesSuccess
              else:
                unsatCoreVars = @[]
                unsatCoreExtractionStatus = coreResult.error
            else:
              unsatCoreVars = cegarRes.unsatCoreVars
            if cegarRes.verdict == cegarProven and cegarRes.provedInvariants.len > 0:
              invariant = sExprToString(cegarRes.provedInvariants[0])

    let evolutionHit = selectEvolutionHit(initialScan)
    let traceReport = buildTraceReport(evolutionHit)
    ctx.logStage(skCegar, req.functionName, "case closed", 0, ssSucceeded, nil)
    ok(DetectiveArtifact(
      priorPromotion: (invariant: invariant, snapshotPath: priorPromotion.snapshotPath),
      initialScan: initialScan,
      finalScan: NegativeInvariantScan(logicModelConflicted: false),
      evolutionHit: evolutionHit,
      verificationVerdict: "",
      verificationVerdictReport: VerificationVerdictReport(),
      traceReport: traceReport,
      logLines: @[],
      cegarSmtlib2: cegarSmtlib2,
      cegarEvidenceLog: cegarEvidenceLog,
      cegarCounterexample: hasCegarCounterexample,
      unsatCoreVars: unsatCoreVars,
      unsatCoreExtractionStatus: unsatCoreExtractionStatus
    ))
  except CatchableError:
    err(axiomErrInconsistentState)

## Investigate.
# @axiom-hint: lean="ast_parse_failed_isolated" smt="(assert ast_parse_failed_isolated)"
proc investigate*(
  req: UniversalPipelineRequest;
  translation: UniversalTranslation;
  priorPromotion: tuple[invariant: string; snapshotPath: string];
  initialScan: NegativeInvariantScan;
  finalSource: string;
  activeInvariant: string;
  nearestLeanDiagnostic: string;
  failedReplayAttempts: int
): Result[DetectiveArtifact, AxiomError] {.raises: [], axiomEffect: IOEffect, tags: [RootEffect, AxiomIOEffect, IOEffect].} =
  ## Phase 5: Detective post-process data-flow path.
  try:
    let finalScan = ctx.runNegativeInvariantSearch(translation, finalSource, activeInvariant)
    let evolutionHit = selectEvolutionHit(initialScan)
    let verificationVerdict = inferVerificationVerdict(finalScan)
    let traceReport = buildTraceReport(evolutionHit)
    let verdictReport = buildVerificationVerdictReport(
      verificationVerdict,
      evolutionHit,
      nearestLeanDiagnostic,
      failedReplayAttempts
    )
    ok(DetectiveArtifact(
      priorPromotion: priorPromotion,
      initialScan: initialScan,
      finalScan: finalScan,
      evolutionHit: evolutionHit,
      verificationVerdict: verificationVerdict,
      verificationVerdictReport: verdictReport,
      traceReport: traceReport,
      logLines: @[detectiveLogLine(req.functionName, verificationVerdict, traceReport)],
      unsatCoreVars: @[]
    ))
  except CatchableError:
    err(axiomErrInconsistentState)

{.pop.}

