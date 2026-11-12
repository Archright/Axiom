import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

## FileUtils — Boundary forwarding stub.
##
## Canonical definitions live in `core/io/file_utils`.
## This module re-exports everything for layer boundary compliance.
## SSOT: `core/io/file_utils` is the single source of truth.

from core/io/file_utils import nil
export file_utils

{.pop.}
