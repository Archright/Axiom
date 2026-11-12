## Forwarding Stub — core/compile_time_manifest
##
## Re-exports `core/trusted/compile_time_manifest` so that external layers
## (engine/, gate/, cli/) can use `import core/compile_time_manifest`
## without reaching into `core/trusted/` internals.
##
## AGENTS.md §1: Import Encapsulation via hub modules.

import core/trusted/layer_declaration
axiomLayer "domain"
import core/trusted/compile_time_manifest
{.push raises: [].}
export compile_time_manifest

{.pop}
