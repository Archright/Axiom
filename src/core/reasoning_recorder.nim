import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# Forwarding stub — import encapsulation boundary (verification → core)
import core/trusted/reasoning_recorder
export reasoning_recorder
{.pop.}
