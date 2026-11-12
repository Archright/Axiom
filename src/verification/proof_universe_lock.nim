import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

## Verification re-export wrapper for proof-universe lock modules
##
## Wave 7 split this module into three physical files:
##   src/core/proof_universe_lock.nim          — pure math kernel
##   src/verification/proof_universe_lock_io.nim   — disk I/O [REMOVED 2dea3263d]
##   src/verification/proof_universe_commit.nim    — side-effect orchestration
##
## This wrapper preserves backward compatibility for downstream imports.

import core/proof/proof_universe_lock as lock_math
import verification/proof_universe_commit
# axiomIoBoundary

export lock_math
export proof_universe_commit

{.pop.}
