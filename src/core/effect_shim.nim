import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# Forwarding stub — import encapsulation boundary (verification → core)
import core/trusted/effect_shim
export effect_shim
{.pop.}
