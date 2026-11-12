import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## Boundary Extraction Types
## Type definitions shared across boundary_extraction sub-modules.
## Extracted from boundary_extraction_core.nim to enable proper import-based module structure.

import std/options
import core/judge/smart_search

type
  BoundaryCompleteness* = enum
    bcComplete       ## Pure function; all boundaries determinable
    bcPartialHavoc   ## var params or global mutation; havoc assumptions used
    bcIncompleteIO   ## External I/O; skip Z3 entirely
    bcTrivialDiscard ## Only trivial assertions (length >= 0); no semantic value

  ParamBoundary* = object
    name*: string
    nimType*: string
    isVar*: bool
    smtConstraint*: string
    leanProposition*: string

  BoundaryExtractionResult* = object
    completeness*: BoundaryCompleteness
    functionName*: string
    params*: seq[ParamBoundary]
    returnType*: string
    hint*: Option[SemanticHint]
    smtParts*: seq[string]
    leanParts*: seq[string]

{.pop.}
