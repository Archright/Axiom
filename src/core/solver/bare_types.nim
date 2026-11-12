import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## Bare Type Definitions — Solver Domain
## Forwarding stub: all types are now defined in core/types/domain_types.
## Re-exported for backward compatibility with solver/types.nim consumers.
## Per AGENTS.md §1.3b: Stub contains only import and export.

import core/types/domain_types
export domain_types

{.pop.}
