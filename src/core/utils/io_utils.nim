## Forwarding Stub — io_utils
## AGENTS.md §1.3b: Stub contains only import/export, no business logic.

import core/trusted/layer_declaration
axiomLayer "domain"
import core/io/io_utils
{.push raises: [].}
# axiomIoBoundary
export io_utils

{.pop}
