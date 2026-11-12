## Forwarding Stub — core/hubs/verification_pipeline_context
##
## Re-exports `core/types/hubs/verification_pipeline_context` so that external layers
## (engine/, gate/, cli/) can use `import core/hubs/verification_pipeline_context`
## without reaching into `core/types/hubs/` internals.
##
## AGENTS.md §1: Import Encapsulation via hub modules.

import core/trusted/layer_declaration
axiomLayer "domain"
import core/types/hubs/verification_pipeline_context
{.push raises: [].}
export verification_pipeline_context

{.pop}
