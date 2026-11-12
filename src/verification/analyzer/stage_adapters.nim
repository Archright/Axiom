
import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push, raises: [CatchableError].}
import core/axiom_pragmas
# axiomIoBoundary
## Stage Adapters
## Thin wrappers that adapt existing stage runner signatures to the
## VerificationPipelineContext interface used by VerificationPipeline.
import
  verification / analyzer / analyzer_shared_cert

import
  verification / analyzer / analyzer_pipeline

import
  verification / analyzer / stage_01_ast_extract

import
  verification / analyzer / stage_03_dependency

import
  verification / analyzer / stage_04_gate_check

import
  verification / analyzer / stage_05_lean_bridge

import
  verification / analyzer / stage_06_proof_synth

import
  verification / analyzer / stage_07_certificate

import
  verification / analyzer / stage_08_reporter

proc stageVaultSync*(ctx: var VerificationPipelineContext) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, TimeEffect, RootEffect].} =
  ## Stage 1: Virtual DB Load & Sync
  runVaultSync(ctx.idx, ctx.certDir, ctx.idxPath)

proc stageSymbolicGc*(ctx: var VerificationPipelineContext) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, TimeEffect, RootEffect].} =
  ## Stage 2: Symbolic GC & Symbol Graph Cache
  runSymbolicGcExtract(ctx.idx, ctx.graph, ctx.srcRoot, ctx.certDir,
                       ctx.normalizedCertDir, ctx.repoRoot,
                       ctx.freezeGraphCache)

proc stageCertLoad*(ctx: var VerificationPipelineContext) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Stage 3: Load trusted certificates
  runCertLoad(ctx.report, ctx.idx, ctx.certDir)
  ctx.knownFunctions = collectKnownFunctions(ctx.report.certificates)

proc stageHydration*(ctx: var VerificationPipelineContext) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, TimeEffect, RootEffect].} =
  ## Stage 4: Incremental hydration
  runHydrationExtract(ctx.report, ctx.idx, ctx.certDir, ctx.graph,
                      ctx.normalizedCertDir, ctx.knownFunctions,
                      ctx.globalsByModule, ctx.moduleFunctionsByPath)

proc stageCanonicalize*(ctx: var VerificationPipelineContext) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, TimeEffect, RootEffect].} =
  ## Stage 5: Canonicalization + Architecture Gate
  runCanonicalizeAndArchGate(ctx.report)

proc stageVaultEnrich*(ctx: var VerificationPipelineContext) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Stage 6: Vault enrichment with winning strategies
  runVaultEnrich(ctx.report, ctx.certDir)

proc stageInfluenceGate*(ctx: var VerificationPipelineContext) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Stage 7: Global influence gate + early abort check
  runInfluenceGate(ctx.report, ctx.graph)
  if ctx.report.totalTrustedFunctions == 0:
    ctx.report.blockingFailure = true
    ctx.shouldAbort = true

proc stageAuditInfluence*(ctx: var VerificationPipelineContext) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Stage 8: Audit global influence events
  runAuditInfluence(ctx.report, ctx.repoRoot)

proc stageTypeGate*(ctx: var VerificationPipelineContext) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Stage 9: Type integrity gate
  runTypeGate(ctx.report, ctx.repoRoot)

proc stageSymbolicAnalysis*(ctx: var VerificationPipelineContext) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Stage 10: Symbolic analysis (loop invariant synthesis)
  runSymbolicAnalysis(ctx.report, ctx.graph, ctx.certDir, ctx.repoRoot,
                      ctx.enableSymbolic)

proc stageSymbolicAudit*(ctx: var VerificationPipelineContext) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Stage 11: Symbolic invariant audit
  runSymbolicAudit(ctx.report, ctx.repoRoot)

proc stageSemanticAudit*(ctx: var VerificationPipelineContext) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Stage 12: Semantic integrity audit
  runSemanticAudit(ctx.report, ctx.repoRoot)

func stageCertifiedExempt*(ctx: var VerificationPipelineContext) =
  ## Stage 12.5: Stateless hydration — certified_exempt count
  ## ax_proof_state.json is transient; no ASI impact. Set to 0 deterministically.
  ctx.report.certifiedExemptCount = 0

proc stageFinalize*(ctx: var VerificationPipelineContext) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  ## Stage 13: Finalize + audit trail + vault save + timeline
  runFinalize(ctx.report, ctx.idx, ctx.idxPath, ctx.repoRoot, ctx.tStart)

{.pop.}
