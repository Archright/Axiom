import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
## Forwarding stub for compile-time scanner compatibility
## Re-exports from the canonical location
import core/symbolic/global_symbol_graph_types
export global_symbol_graph_types
{.pop.}
