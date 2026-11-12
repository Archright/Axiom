import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

## BMC Generic — Boundary forwarding stub.
##
## Canonical definitions live in core/bmc/bmc_generic.
## This module re-exports everything for layer boundary compliance.
## SSOT: core/bmc/bmc_generic is the single source of truth.

from core/bmc/bmc_generic import nil
export bmc_generic

{.pop.}
