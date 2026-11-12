import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

## Results — Boundary forwarding stub.
##
## Canonical definitions live in `core/types/results`.
## This module re-exports everything for layer boundary compliance.
## SSOT: `core/types/results` is the single source of truth.

from core/types/results import nil
export results

{.pop.}
