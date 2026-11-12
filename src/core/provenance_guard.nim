import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# Forwarding stub — import encapsulation boundary (verification → core)
import core/trusted/provenance_guard
export provenance_guard
{.pop.}
