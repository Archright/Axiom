## Batch UAP Orchestrator — shared types and state.
##
## Defines BatchUapReport, BatchUapProgressSink, and summaryCache
## used across the orchestrator submodules.

import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [CatchableError].}

import std/tables
import core/proof/proof_budget
import core/orchestrator/orchestrator_types
import core/contracts/universal_pipeline_contract
import core/function_verification_summary
import core/types/refactor_task_types
# axiomIoBoundary

var summaryCache*: SummaryCache = initTable[string, FunctionVerificationSummary]()

type
  PromotionClassificationCounts* = object
    verified*: int        ## evidence-ready + promotable → promoted to canonical
    noObligation*: int    ## certNoObligation status; no obligation, not a failure
    unverifiable*: int    ## no semantic evidence or unsupported; not a failure
    failed*: int          ## structurally malformed cert or promotion failure → persist FAIL

  BatchUapReport* = object
    orchestrationReport*: OrchestrationReport
    uapResults*: Table[string, UniversalPipelineResult]
    budget*: ProofBudget
    refactorTasks*: seq[RefactorTask]
    persistFailures*: seq[string]  ## R8: promotable v3 certs whose canonical-vault promotion failed (persist FAIL)
    ## Verification-axis observability of IR pipeline failures (failed kernel
    ## unit names). Deliberately NOT persistFailures: an IR-failed kernel
    ## produced no verified node and no promotable certificate, so there is
    ## nothing whose persistence failed — folding these into the persist ledger
    ## reclassified unrelated units' verification failures as exit-2 persist
    ## errors. Surfaced in the report document as `irPipelineFailures`.
    irPipelineFailures*: seq[string]
    promotionClassifications*: PromotionClassificationCounts  ## P4: 4-way promotion-eligibility classification counts

  BatchUapProgressSink* = proc(nodeId: string; status: string) {.gcsafe, closure, raises: [CatchableError].}

{.pop.}
