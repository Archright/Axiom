import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [].}

## Forbidden source-text patterns — thin facade.
## Actual query implementations split into:
##   - safety_queries.nim  (forbidden patterns, duplicate imports, language ban)
##   - purity_queries.nim   (proc purity, new-code-must-be-func)

import gate/nimtry/safety_queries
import gate/nimtry/purity_queries

export safety_queries
export purity_queries

{.pop.}
