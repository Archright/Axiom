import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## Verification Interface — Contract layer forwarding stub.
##
## Canonical definitions live in core/boundary/verification_interface.
## This module re-exports everything for backward compatibility.
## SSOT: boundary/verification_interface.nim is the single source of truth.
##
## nimtry ssot-type-duplication: eliminated by this forwarding pattern.

from core/boundary/verification_interface import nil
export verification_interface

{.pop.}
