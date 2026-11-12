import core/trusted/layer_declaration
axiomLayer "presentation"
{.push raises: [].}
## Product version is derived once in core/release/version_derive (staticRead of
## axiom.nimble). This module re-exports it so existing `cli/version` consumers
## keep working without a second version authority.
import ../core/release/version_derive
export version_derive
{.pop.}
