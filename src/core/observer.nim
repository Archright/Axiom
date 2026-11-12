import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

## observer.nim — Axiom Pipeline Engine Foundation
## Re-exports: types, scanner, ast_builder, state_hash
## Single entry point for all pipeline consumers.
##
## Usage:
##   import core/observer
##   let pm = scanProject(repoRoot)
##   let ast = buildASTCache(pm)
##   let state = computeStateHash(pm, repoRoot)

import ./observer/types
export types

import ./observer/scanner
export scanner

import ./observer/ast_builder
export ast_builder

import ./observer/state_hash
export state_hash

{.pop.}
