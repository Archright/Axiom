import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# Forwarding stub — import encapsulation boundary
import core/types/function_verification_summary
export function_verification_summary
{.pop.}
