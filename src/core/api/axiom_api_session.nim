import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## Axiom API Session
## Public API module for session management, proof generation, and verification operations.
##
## This module re-exports all sub-modules that were previously included as part files.
## The include-based structure (axiom_api_session_parts/) has been replaced with proper
## import-based modules for better encapsulation and compilation unit isolation.

import core/api/axiom_api_session_types
export axiom_api_session_types

import core/api/axiom_api_session_helpers
export axiom_api_session_helpers

import core/api/axiom_api_session_proof
export axiom_api_session_proof

import core/api/axiom_api_session_ops
export axiom_api_session_ops

{.pop.}
