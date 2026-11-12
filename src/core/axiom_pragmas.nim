## Forwarding Stub — core/axiom_pragmas
##
## Re-exports `core/trusted/axiom_pragmas` so that external layers
## (engine/, gate/, cli/) can use `import core/axiom_pragmas`
## without reaching into `core/trusted/` internals.
##
## AGENTS.md §1: Import Encapsulation via hub modules.

import core/trusted/layer_declaration
axiomLayer "domain"
import core/trusted/axiom_pragmas
{.push raises: [].}
export axiom_pragmas

{.pop}
