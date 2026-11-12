import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

## PolicyTypes — Boundary forwarding stub.
##
## Canonical definitions live in `core/policy/architecture_policy_types`.
## This module re-exports everything for layer boundary compliance.
## SSOT: `core/policy/architecture_policy_types` is the single source of truth.

from core/policy/architecture_policy_types import nil
export architecture_policy_types

{.pop.}
