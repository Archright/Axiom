import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## Verified Axioms Dictionary — Re-export Facade
##
## This module re-exports all public symbols from:
##   - verified_axioms_core (types + utility functions)
##   - verified_axioms_catalog (mapping table + lookup functions)
##
## Importers of `verified_axioms` get the full public API without
## requiring any changes.

import core/verified_axioms/verified_axioms_core
export verified_axioms_core

import core/verified_axioms/verified_axioms_catalog_part1
export verified_axioms_catalog_part1

{.pop.}
