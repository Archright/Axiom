import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# Forwarding stub — import encapsulation boundary
import core/types/lean_lsp_types
export lean_lsp_types
{.pop.}
