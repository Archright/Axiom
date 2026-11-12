import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# Forwarding stub — import encapsulation boundary (gate → core)
import core/types/domain_utils
export domain_utils
{.pop.}
