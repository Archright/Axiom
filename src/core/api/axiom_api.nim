import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## Axiom API
## Public API facade — re-exports all sub-modules for session management,
## proof generation, and verification operations.

import core/api/axiom_api_session
export axiom_api_session

import core/api/axiom_api_verify
export axiom_api_verify

{.pop.}
