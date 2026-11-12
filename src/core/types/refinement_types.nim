import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

## refinement_types.nim — SSOT for refinement and liquid types.
## Extracted from domain_types.nim (Phase B-4).

import std/tables
import core/symbolic/symbolic_types_expr

type
  BaseTypeKind* = enum
    btInt
    btNat
    btBool
    btString
    btUnknown

  RefinementType* = object
    base*: BaseTypeKind
    predicate*: SymSExpr

  LiquidTypeEnv* = Table[string, RefinementType]

{.pop.}
