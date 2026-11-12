import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# Forwarding stub — import encapsulation boundary (gate → core)
import core/symbolic/symbolic_types_expr
export symbolic_types_expr
{.pop.}
