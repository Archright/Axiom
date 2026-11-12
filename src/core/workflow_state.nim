import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# Forwarding stub — import encapsulation boundary (cli → core)
import core/types/workflow_state
export workflow_state
{.pop.}
