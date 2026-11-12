import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

## Verification Facade
## Unified interface for rebuild_assets.nim and other verification consumers.
## Encapsulates 13 sub-module dependencies to satisfy SoC import limit.

import core/results as res
export res

import verification/ast_extractor
export ast_extractor

import verification/fingerprint_engine
export fingerprint_engine

import core/parsers/collect
export collect

import core/parsers/lean
export lean

import core/parsers/pred
export pred

import core/json/json_utils
export json_utils

import core/utils/constants
export constants

import core/provenance_guard
export provenance_guard

import core/symbol_graph/global_symbol_graph_query
export global_symbol_graph_query

import verification/certificate_manager
export certificate_manager

import verification/proof_state_convergence
export proof_state_convergence

import core/utils/io_utils
export io_utils

{.pop.}
