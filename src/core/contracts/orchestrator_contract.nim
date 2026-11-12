import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
{.push noSideEffect.}

## Orchestrator Contract — Facade exposing only pure types and functions.

from core/orchestrator/orchestrator_types import nil
export orchestrator_types

from core/orchestrator/cegar_bmc_types import nil
export cegar_bmc_types

# --- Extended for persona dependencies (Phase G) ---
from core/orchestrator/cegar_types import nil
export cegar_types

{.pop.}
{.pop.}
