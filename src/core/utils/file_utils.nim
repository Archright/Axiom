## Forwarding Stub — file_utils
## AGENTS.md §1.3b: Stub contains only import/export, no business logic.

import core/trusted/layer_declaration
axiomLayer "domain"
import core/io/file_utils
{.push raises: [].}
# axiomIoBoundary
export file_utils

{.pop}
