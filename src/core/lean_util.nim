import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# Forwarding stub — import encapsulation boundary (verification → core)
import core/trusted/lean_util
export lean_util
{.pop.}
