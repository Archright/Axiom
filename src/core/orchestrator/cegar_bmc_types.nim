import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## CEGAR-BMC Bridge Result — pure shared type.
##
## Lives in core/orchestrator so that both Infrastructure consumers
## (verification/pipeline_state_types, verification/cegar_bmc_bridge) can share it
## without creating a module cycle.

import core/orchestrator/cegar_types
import core/bmc/bmc_generic

type
  CegarBmcResult* = object
    cegarVerdict*: CegarEngineVerdict
    bmcVerdict*: GenericBmcVerdict
    concreteWitness*: string     ## Human-readable witness trace
    propertyKind*: BmcPropertyKind

{.pop.}
