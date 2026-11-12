import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# Forwarding stub — import encapsulation boundary (cli → core)
import core/trusted/stdlib_shield
export stdlib_shield
{.pop.}
