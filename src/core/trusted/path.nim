import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [ValueError].}
{.push noSideEffect.}

import core/crypto/hash_kernel
import core/trusted/monad
# axiomIoBoundary

## ReasoningPath — Hypothesis → Attempt → Evidence causal chain.
## Immutably linked, each node contains the hash of the previous node.

type
  ReasoningNodeKind* = enum
    rnkHypothesis,
    rnkAttempt,
    rnkEvidence

  ReasoningNode* = object
    kind*: ReasoningNodeKind
    payload*: string
    prevHash*: string
    timestamp*: int64

  ReasoningPath* = object
    nodes*: seq[ReasoningNode]
    headHash*: string

func hashNode(node: ReasoningNode): string {.inline.} =
  hash_kernel.sha256Hex(node.kind.repr & "|" & node.payload & "|" & node.prevHash & "|" & $node.timestamp)

## Add a new node to the path. Immutability guarantee: existing nodes are not modified.
func appendNode*(path: ReasoningPath; kind: ReasoningNodeKind; payload: string; timestamp: int64): ReasoningPath {.inline.} =
  result = path
  let prevHash = if path.nodes.len > 0: path.nodes[^1].hashNode() else: ""
  let node = ReasoningNode(kind: kind, payload: payload, prevHash: prevHash, timestamp: timestamp)
  result.nodes.add(node)
  result.headHash = node.hashNode()

## Verify path integrity: check that each node's prevHash matches the actual hash of the previous node.
func verifyPathIntegrity*(path: ReasoningPath): bool {.inline.} =
  for i in 1 ..< path.nodes.len:
    let expectedPrev = path.nodes[i - 1].hashNode()
    if path.nodes[i].prevHash != expectedPrev:
      return false
  true

## Seal the verified path as AxiomSafe.
func sealPath*(path: ReasoningPath): AxiomSafe[ReasoningPath] {.inline.} =
  if not verifyPathIntegrity(path):
    raise newException(ValueError, "Cannot seal corrupted path")
  seal(path)

{.pop.}

{.pop.}
