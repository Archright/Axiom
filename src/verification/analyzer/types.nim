import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}
## Analyzer Types — Zero-Cost Distinct Identifier Layer
##
## Replaces string casts with distinct uint32 tokens for type safety
## and zero-allocation performance under ARC/ORC.

import core/hubs/sorter_node_id
# axiomIoBoundary
export sorter_node_id

type
  NodeId* = distinct uint32
  SymbolId* = distinct uint32

  AnalyzerTokenKind* = enum
    atkVariable, atkInvariant, atkConstraint, atkPredicate

  AnalyzerToken* = object
    kind*: AnalyzerTokenKind
    nodeId*: NodeId
    symId*: SymbolId

proc `==`*(a, b: NodeId): bool {.inline.} = a.uint32 == b.uint32
proc `==`*(a, b: SymbolId): bool {.inline.} = a.uint32 == b.uint32
proc `$`*(id: NodeId): string {.inline.} = $id.uint32
proc `$`*(id: SymbolId): string {.inline.} = $id.uint32

{.pop.}
