
import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push, raises: [CatchableError].}
# axiomIoBoundary
## Verification Analyzer
## Orchestrator router for the 14-stage verification pipeline.
## All stage logic lives in analyzer/stages/; this module only coordinates.
## DEBT#010: verifyCertificates refactored to ≤20-line pipeline entry point.
import
  std / os

import
  core / types / domain_types

import
  verification / analyzer / analyzer_pipeline

import
  verification / analyzer / stage_adapters

import
  verification / analyzer / stage_08_reporter

proc auditAdapter(stepName: string; report: VerificationReportSummary) {.
    nimcall, raises: [].} =
  auditVerificationStep(stepName, report)

func buildPipeline(): VerificationPipeline {.raises: [].} =
  ## Constructs the ordered 14-stage verification pipeline.
  result = VerificationPipeline()
  result.addStage("vault_sync", stageVaultSync)
  result.addStage("symbolic_gc", stageSymbolicGc)
  result.addStage("cert_load", stageCertLoad)
  result.addStage("hydration", stageHydration)
  result.addStage("canonicalize", stageCanonicalize)
  result.addStage("vault_enrich", stageVaultEnrich, auditAfter = false)
  result.addStage("influence_gate", stageInfluenceGate)
  result.addStage("audit_influence", stageAuditInfluence)
  result.addStage("type_gate", stageTypeGate)
  result.addStage("symbolic_analysis", stageSymbolicAnalysis)
  result.addStage("symbolic_audit", stageSymbolicAudit, auditAfter = false)
  result.addStage("semantic_audit", stageSemanticAudit)
  result.addStage("certified_exempt", stageCertifiedExempt, auditAfter = false)
  result.addStage("finalize", stageFinalize)

proc verifyCertificates*(certDir: string; enableSymbolic: bool = false;
                         srcRootOverride: string = "";
                         freezeGraphCache: bool = false): VerificationReportSummary {.
    raises: [CatchableError].} =
  ## Entry point: initialize context, build pipeline, run all stages.
  if not dirExists(certDir):
    result.blockingFailure = true
    result.missingCertificates = 1
    return
  var ctx = initVerificationContext(certDir, enableSymbolic, srcRootOverride,
                                    freezeGraphCache)
  buildPipeline().run(ctx, auditAdapter)
  result = ctx.report

{.pop.}
