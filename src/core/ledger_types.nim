import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# Forwarding stub — import encapsulation boundary (cli → core)
import core/types/ledger_types
export ledger_types
{.pop.}
