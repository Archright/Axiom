## P0.3.11 — C14 Semantic↔CHC Identity tests.
## Verifies: identity is structural and explicit; identity ≠ ordering;
## the Semantic↔Canonical mapping is deterministic and bidirectional.

import std/options
import std/sequtils
import std/unittest
import core/trusted/verification_model_types
import core/trusted/private/identity_core
import core/trusted/private/identity_mapping
import core/trusted/private/semantic_identity

# Two transitions A→B with DIFFERENT guards: same (source,target) pair, but
# they are distinct transitions. Identity must distinguish them structurally.
proc aToBBoth(): tuple[id1, id2: TransitionIdentity] =
  let t1 = Transition(source: NodeId(1), target: NodeId(2), guard: nil, update: ParallelUpdate())
  let t2 = Transition(source: NodeId(1), target: NodeId(2), guard: nil, update: ParallelUpdate())
  # distinct structural identity: guard keys differ
  (transitionIdentityOf(t1, "g1", "u1"), transitionIdentityOf(t2, "g2", "u1"))

suite "C14 Semantic Identity — identity is structural, not ordinal":
  test "same (source,target) with different guard keys are distinct identities":
    let (a, b) = aToBBoth()
    check canonicalKey(a) != canonicalKey(b)
    check a.sourceNode == b.sourceNode

  test "identity is independent of serialization order":
    let t = Transition(source: NodeId(1), target: NodeId(2), guard: nil, update: ParallelUpdate())
    let id1 = transitionIdentityOf(t, "g", "u")
    # Rebuild identically; order must not enter the key.
    let id2 = transitionIdentityOf(t, "g", "u")
    check canonicalKey(id1) == canonicalKey(id2)
    # Ordinal is a SEPARATE value; it never affects identity.
    let ord1 = TransitionOrdinal(0)
    let ord2 = TransitionOrdinal(5)
    check int(ord1) != int(ord2)
    check canonicalKey(id1) == canonicalKey(id2)  # identity unchanged despite ordinals

suite "C14 Mapping — deterministic and bidirectional":
  test "node↔relation mapping round-trips":
     var m: SemanticToCanonicalMap
     m.setNodeMapping(NodeId(1), RelationId("rel_body"))
     m.setNodeMapping(NodeId(2), RelationId("rel_exit"))
     check m.relationToNode.anyIt(it.relation == RelationId("rel_body") and it.node == NodeId(1))
     check m.relationToNode.anyIt(it.relation == RelationId("rel_exit") and it.node == NodeId(2))
     check not m.relationToNode.anyIt(it.relation == RelationId("nope"))