import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# Forwarding stub — import encapsulation boundary
import core/types/semantic_types
export semantic_types
{.pop.}
