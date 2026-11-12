import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## Vault Index Types
## Forwarding stub: types now defined in core/types/domain_types.
## Re-exported for backward compatibility.
## Per AGENTS.md §1.3b: Stub contains only import and export.

import core/types/domain_types
export domain_types.VaultIndexEntry
export domain_types.VaultIndex

{.pop.}
