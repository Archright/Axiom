import core/trusted/layer_declaration
axiomLayer "trusted.core.pragmas"

import core/trusted/axiom_pragmas_lite
export axiom_pragmas_lite.axiomDecision

import core/trusted/ast_to_ir
import core/trusted/axiom_ir
import core/trusted/effect_bridge
export effect_bridge
import core/trusted/env_types
import core/utils/debt_params
import std/macros
import std/options
import std/os
import std/pathnorm
import std/sets
import std/strutils
import std/tables
import core/crypto/hash_consolidation
export hash_consolidation

include core/trusted/axiom_pragmas_types
include core/trusted/axiom_pragmas_vm_helpers
include core/trusted/axiom_pragmas_macros

{.experimental: "codeReordering".}

include core/trusted/axiom_pragmas_procs
