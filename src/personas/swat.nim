import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [CatchableError].}

import std/options
import core/boundary/axiom_pragmas_boundary

import core/boundary/boundary_forwarding
export persona_interface
import core/boundary/gateway_boundary
import core/boundary/results_boundary
import core/types/pipeline_core_types
import core/contracts/logic_contract
from core/boundary/verification_interface import StageKind, StageStatus, Layer1BmcVerdict

let ctx = initPersonaContext()

# @axiom-hint: lean="functionName.length ≥ 0 ∧ sourceChecksum.length ≥ 0" smt="(assert (and (>= (str.len functionName) 0) (>= (str.len sourceChecksum) 0)))"
# @axiom-hint: lean="functionName.length > 0" smt="(assert (and (> (str.len functionName) 0)))"
func swatLogLine(
  functionName: string;
  sourceChecksum: string;
  traceReport: TraceReport
): string {.raises: [], noSideEffect.} =
  let named = if functionName.len > 0: functionName else: "unknown"
  let evidence =
    if traceReport.pathSignature.len > 0:
      traceReport.pathSignature
    else:
      "trace-unavailable"
  "[SWAT] Raid complete: " & named & " evidence secured=" & evidence & " checksum=" & sourceChecksum

## Execute Raid.
# @axiom-hint: lean="ast_parse_failed_isolated" smt="(assert ast_parse_failed_isolated)"
func executeRaid*(
  req: UniversalPipelineRequest;
  translation: UniversalTranslation;
  initialScan: NegativeInvariantScan;
  activeInvariant: string;
  evolutionHit: Option[AnnotatedHit];
  traceReport: TraceReport
): Result[SwatArtifact, AxiomError] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Phase 1: SWAT Layer 1 — BMC fast path.
  ## Shallow BMC for loop-free functions; inconclusive results pass through to Detective.
  try:
    let bmcResult = ctx.runLayer1Bmc(req)

    if bmcResult.verdict == lbvBugFound:
      let bmcHit = AnnotatedHit(
        hit: VulnerabilityHit(kind: vkIntegerOverflowUnderflow, ioInfo: IntegerOverflowInfo(registerName: "", isOverflow: false)),
        sat: true,
        violatedProperty: "bmc-bug-found",
        counterExampleInput: "bmc-witness-steps:" & $bmcResult.witnessTrace.steps,
        remediation: ""
      )
      let syncResult = ctx.syncRecoveredSourceToModule(req, req.sourceCode)
      let sourceChecksumRes = ??syncResult
      let pocSnippet =
        if evolutionHit.isSome():
          buildPocSnippet(req.language, req.functionName, evolutionHit.get())
        else:
          ""
      let reproResult = ctx.writeReproductionArtifact(req, evolutionHit, pocSnippet)
      let reproductionPathRes = ??reproResult
      let bddResult = ctx.writeBddFeature(req, initialScan)
      let bddPathRes = ??bddResult
      return ok(SwatArtifact(
        healedSource: req.sourceCode,
        rounds: @[],
        sourceChecksum: sourceChecksumRes,
        reproductionPath: reproductionPathRes,
        bddFeaturePath: bddPathRes,
        pocSnippet: pocSnippet,
        traceReport: traceReport,
        vulnerabilityHits: @[bmcHit],
        logLines: @[swatLogLine(req.functionName, sourceChecksumRes, traceReport), "[BMC] bug-found fast-path"]
      ))

    if bmcResult.verdict == lbvProven:
      let syncResult = ctx.syncRecoveredSourceToModule(req, req.sourceCode)
      let sourceChecksumRes = ??syncResult
      let pocSnippet =
        if evolutionHit.isSome():
          buildPocSnippet(req.language, req.functionName, evolutionHit.get())
        else:
          ""
      let reproResult = ctx.writeReproductionArtifact(req, evolutionHit, pocSnippet)
      let reproductionPathRes = ??reproResult
      let bddResult = ctx.writeBddFeature(req, initialScan)
      let bddPathRes = ??bddResult
      return ok(SwatArtifact(
        healedSource: req.sourceCode,
        rounds: @[],
        sourceChecksum: sourceChecksumRes,
        reproductionPath: reproductionPathRes,
        bddFeaturePath: bddPathRes,
        pocSnippet: pocSnippet,
        traceReport: traceReport,
        vulnerabilityHits: @[],
        logLines: @[swatLogLine(req.functionName, sourceChecksumRes, traceReport), "[BMC] proven fast-path"]
      ))

    # BMC inconclusive: run negative invariant search as secondary heuristic scan
    let finalScan = ctx.runNegativeInvariantSearch(translation, req.sourceCode, activeInvariant)
    let syncResult = ctx.syncRecoveredSourceToModule(req, req.sourceCode)
    let sourceChecksumRes = ??syncResult
    let pocSnippet =
      if evolutionHit.isSome():
        buildPocSnippet(req.language, req.functionName, evolutionHit.get())
      else:
        ""
    let reproResult = ctx.writeReproductionArtifact(req, evolutionHit, pocSnippet)
    let reproductionPathRes = ??reproResult
    let bddResult = ctx.writeBddFeature(req, initialScan)
    let bddPathRes = ??bddResult
    ok(SwatArtifact(
      healedSource: req.sourceCode,
      rounds: @[],
      sourceChecksum: sourceChecksumRes,
      reproductionPath: reproductionPathRes,
      bddFeaturePath: bddPathRes,
      pocSnippet: pocSnippet,
      traceReport: traceReport,
      vulnerabilityHits: finalScan.hits,
      logLines: @[swatLogLine(req.functionName, sourceChecksumRes, traceReport)]
    ))
  except CatchableError:
    err(axiomErrInconsistentState)

{.pop.}
