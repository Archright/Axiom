import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# Forwarding stub — import encapsulation boundary
import core/schema/task_schema
export task_schema
{.pop.}
