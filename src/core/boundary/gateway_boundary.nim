import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

## Gateway — Boundary forwarding stub.
##
## Canonical definitions live in core/gateway/gateway.
## This module re-exports everything for layer boundary compliance.
## SSOT: core/gateway/gateway is the single source of truth.

from core/gateway/gateway import nil
export gateway

{.pop.}
