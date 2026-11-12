import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## PipelineConfig — Read-only configuration for the defunctionalized pipeline.
##
## Extracted from PipelineContext. All fields are immutable after construction.
## Passed by value (`let`) to each stage function to enforce purity.

import std/monotimes
import core/types/pipeline_core_types
import core/logic/universal_translation_types

type
  PipelineConfig* = object
    ## Immutable configuration for a single pipeline execution.
    req*: UniversalPipelineRequest
    translation*: UniversalTranslation
    priorPromotion*: tuple[invariant: string; snapshotPath: string]
    maxIterations*: int
    guardNodeId*: string
    guardStartTime*: MonoTime

{.pop.}
