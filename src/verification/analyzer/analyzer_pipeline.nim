import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [CatchableError].}

import core/utils/constants
import core/domain_types
import core/hubs/verification_pipeline_context
import core/symbolic/global_symbol_graph_types
import std/os
import std/sets
import std/strutils
import std/tables
import std/times
import verification/vault_index
import core/trusted/axiom_pragmas
# axiomIoBoundary

export VerificationPipelineContext

type
  AuditFn* = proc(stepName: string; report: VerificationReportSummary) {.nimcall, raises: [CatchableError].}

  StageProc* = proc(ctx: var VerificationPipelineContext) {.nimcall, raises: [CatchableError].}

  PipelineStage* = object
    name*: string
    run*: StageProc
    auditAfter*: bool  ## Whether to call auditVerificationStep after this stage

  VerificationPipeline* = object
    stages*: seq[PipelineStage]
proc initVerificationContext*(
    certDir: string;
    enableSymbolic: bool;
    srcRootOverride: string;
    freezeGraphCache: bool
): VerificationPipelineContext {.raises: [CatchableError].} =
  ## Build the context from the original verifyCertificates parameters.
  result.tStart = epochTime()
  result.report.generatedAt = now().utc().format("yyyy-MM-dd'T'HH:mm:ss'Z'")
  result.certDir = certDir
  result.enableSymbolic = enableSymbolic
  result.freezeGraphCache = freezeGraphCache
  result.shouldAbort = false
  result.idx = VaultIndex(version: 1, lastVerifiedAt: 0,
    entries: initTable[string, VaultIndexEntry](),
    byFileName: initTable[string, string]())
  result.graph = GlobalSymbolGraph()
  result.knownFunctions = initHashSet[string]()
  result.globalsByModule = initTable[string, HashSet[string]]()
  result.moduleFunctionsByPath = initTable[string, HashSet[string]]()
  # Path computation (mirrors the original inline logic)
  var dir = certDir
  normalizePath(dir)
  result.report.certDir = dir
  let certBaseDir = absolutePath(certDir)
  result.certBaseDir = certBaseDir
  var normalizedCertDir = certBaseDir
  normalizePath(normalizedCertDir)
  result.normalizedCertDir = normalizedCertDir
  result.repoRoot =
    if normalizedCertDir.endsWith(defaultCertDir):
      parentDir(parentDir(parentDir(normalizedCertDir)))
    else:
      getCurrentDir()
  result.srcRoot = if srcRootOverride.len > 0: srcRootOverride else: joinPath(result.repoRoot, "src")
  result.idxPath = joinPath(result.repoRoot, "logs", "axiom_vault.idx")
func addStage*(pipeline: var VerificationPipeline; name: string;
    run: StageProc; auditAfter: bool = true) {.raises: [].} =
  pipeline.stages.add(PipelineStage(name: name, run: run, auditAfter: auditAfter))
proc run*(pipeline: VerificationPipeline; ctx: var VerificationPipelineContext;
    auditFn: AuditFn
) {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Execute all stages sequentially. Stops early if ctx.shouldAbort is set.
  ## Calls auditFn after each stage where auditAfter = true.
  for stage in pipeline.stages:
    if ctx.shouldAbort:
      break
    stage.run(ctx)
    if stage.auditAfter:
      auditFn(stage.name, ctx.report)

{.pop.}
