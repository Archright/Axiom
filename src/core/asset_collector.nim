import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# Forwarding stub — import encapsulation boundary (verification → core)
import core/trusted/asset_collector
export asset_collector
{.pop.}
