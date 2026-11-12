import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
{.push noSideEffect.}

## BMC Race — backward compatibility re-export module.
## Types moved to bmc_types.nim, engine logic moved to bmc_engine.nim.

import core/bmc/bmc_types
export bmc_types
import core/bmc/bmc_engine
export bmc_engine

{.pop.}
{.pop.}
