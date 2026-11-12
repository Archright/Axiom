import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# Forwarding stub — import encapsulation boundary
import core/types/pipeline_core_types
export pipeline_core_types
{.pop.}
