import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

## gate_types.nim — Forwarding stub.
## Re-exports all symbols from gate_contract.nim (types + re-exports)
## and gate_types_impl.nim (utility functions).
##
## All consumers that import `gate/gate_types` continue to work unchanged.
## The actual contract lives in gate_contract.nim — see that file for version policy.

from gate/gate_contract import nil
export gate_contract

from gate/gate_types_impl import nil
export gate_types_impl

{.pop.}
