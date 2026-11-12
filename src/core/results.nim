## Forwarding Stub — core/results
##
## Re-exports `core/types/results` so that external layers
## (engine/, gate/, cli/) can use `import core/results`
## without reaching into `core/types/` internals.
##
## AGENTS.md §1: Import Encapsulation via hub modules.

import core/trusted/layer_declaration
axiomLayer "domain"
import core/types/results
{.push raises: [].}
export results

{.pop}
