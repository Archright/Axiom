import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
import core/gate/gate_evaluators
import core/orchestrator/orchestrator_report_types
import core/orchestrator/orchestrator_request_types
import core/orchestrator/protocols
import core/sorter/sorter_core
type
  OrchestrationProgressEventKind* = enum
    orchestrationDepthStarted,
    orchestrationNodeStarted,
    orchestrationNodeFinished,
    orchestrationPrimingProgress

  OrchestrationProgressEvent* = object
    kind*: OrchestrationProgressEventKind
    dependencyDepth*: int
    totalDepths*: int
    activeNodeCount*: int
    workerCount*: int
    nodeId*: SorterNodeId
    status*: OrchestrationNodeStatus
    cacheHit*: bool
    primedCount*: int

  OrchestrationProgressSink* = proc(event: OrchestrationProgressEvent) {.gcsafe, closure, raises: [].}

  OrchestrationContext* = object
    ## Orchestrator에 주입되는 콜백과 설정을 묶는 컨텍스트.
    ## 필수: cegarEngine (nil이면 CEGAR 비활성화)
    ## 선택: 나머지 (nil = 기본값)
    cegarEngine*: CegarCallback
    encodeSmtlib2*: EncodeSmtlib2Callback
    proofLinkage*: ProofLinkageCallback
    progressSink*: OrchestrationProgressSink
    impactIndexLookup*: NodeImpactIndexLookup
    maxWorkers*: int
    maxWallClockMs*: int

func isValid*(ctx: OrchestrationContext): bool {.raises: [].} =
  ## Validate that the context has sane values.
  ctx.maxWorkers > 0 and ctx.maxWallClockMs > 0

func defaultOrchestrationContext*(): OrchestrationContext {.raises: [].} =
  ## Return an OrchestrationContext with sensible defaults.
  OrchestrationContext(
    maxWorkers: 4,
    maxWallClockMs: 3_600_000, # 1 hour
  )
{.pop.}
