import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
import core/symbolic/symbolic_types_parse
export symbolic_types_parse
{.pop.}
