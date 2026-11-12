import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# Forwarding stub — import encapsulation boundary
import core/types/symbolic_types_lean
export symbolic_types_lean
{.pop.}
