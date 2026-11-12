## Forwarding Stub — core/domain_types
##
## Re-exports `core/types/domain_types` so that external layers
## (engine/, gate/, cli/) can use `import core/domain_types`
## without reaching into `core/types/` internals.
##
## AGENTS.md §1: Import Encapsulation via hub modules.

import core/trusted/layer_declaration
axiomLayer "domain"
import core/types/domain_types
{.push raises: [].}
export domain_types

{.pop}
