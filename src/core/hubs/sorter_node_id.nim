## Forwarding Stub — core/hubs/sorter_node_id
##
## Re-exports `core/types/hubs/sorter_node_id` so that external layers
## (engine/, gate/, cli/) can use `import core/hubs/sorter_node_id`
## without reaching into `core/types/hubs/` internals.
##
## AGENTS.md §1: Import Encapsulation via hub modules.

import core/trusted/layer_declaration
axiomLayer "domain"
import core/types/hubs/sorter_node_id
{.push raises: [].}
export sorter_node_id

{.pop}
