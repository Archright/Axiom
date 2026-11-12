import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
## Facade bridge: re-exports all orchestrator type clusters.
## Previous monolithic module split into focused files per SRP.

import core/orchestrator/orchestrator_report_types
import core/orchestrator/orchestrator_request_types
import core/orchestrator/orchestrator_parallel_types
import core/orchestrator/orchestrator_context_types

export orchestrator_report_types
export orchestrator_request_types
export orchestrator_parallel_types
export orchestrator_context_types

{.pop.}
