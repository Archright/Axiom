import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## Param Type Info Hub — SSOT for ParamTypeInfo.
## Extracted from semantic_hint_hub to resolve SOC-leaf-module-imports violation.
## This hub carries the RefinementType dependency; semantic_hint_hub remains pure.

import std/options
import core/types/domain_types
export domain_types

type
  ParamTypeInfo* = object
    name*: string
    nimType*: string
    refinedType*: Option[RefinementType]  ## AST-derived refinement from liquid inference

{.pop.}
