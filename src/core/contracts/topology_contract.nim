import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
{.push noSideEffect.}

## Topology Contract — Facade exposing only pure types and functions.

from core/topology/topology_types import nil
export topology_types

from core/topology/plan import nil
export plan

from core/topology/staging import nil
export staging

from core/topology/lock_update import nil
export lock_update

from core/topology/apply import nil
export apply

{.pop.}
{.pop.}
