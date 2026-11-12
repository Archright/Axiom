import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

## AxiomPragmas — Boundary forwarding stub.
##
## Canonical definitions live in `core/trusted/axiom_pragmas`.
## This module re-exports everything for layer boundary compliance.
## SSOT: `core/trusted/axiom_pragmas` is the single source of truth.

from core/trusted/axiom_pragmas import nil
export axiom_pragmas

{.pop.}
