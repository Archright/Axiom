import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
{.push noSideEffect.}

import core/sorter/sorter_core
import core/orchestrator/orchestrator_report_types
import core/orchestrator/orchestrator_request_types
import core/orchestrator/protocols
import core/sync/sync_utils_resource
import core/vault/vault_manager_spec

type
  ParallelTaskQueue* = object
    maxWorkers*: int

  ParallelTaskInput* = object
    workItem*: SorterWorkItem
    request*: OrchestrationProofRequest
    solverSemaphore*: ptr ResourceSemaphore
    cegarEngine*: CegarCallback
    encodeSmtlib2*: EncodeSmtlib2Callback

  ParallelTaskResult* = object
    workItem*: SorterWorkItem
    status*: OrchestrationNodeStatus
    smtlib2*: string
    solverElapsedMs*: int64
    timeoutMs*: int
    evidenceLogJson*: string
    usedIntervalDomain*: bool
    vulnerabilityType*: string
    assuranceTier*: string = ""  ## Phase 1 Tier semantics: tierLabel value or "" when unresolved
    tierResolution*: string = ""  ## "resolved" | "unavailable"

  VaultHydrationRecord* = object
    resolved*: bool
    valid*: bool
    vaultPath*: string
    spec*: AxiomSpec

{.pop.}
{.pop.}
