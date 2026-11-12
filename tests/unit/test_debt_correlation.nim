## Unit tests for debt_correlation.nim — Layer-3 provenance correlation.
## Tests identity determinism, three-level separation, and broken-chain detection.

import core/trusted/layer_declaration
axiomLayer "domain"

import core/types/debt_types
import core/debt/debt_provenance
import core/debt/debt_correlation

proc main() =
  var passed = 0
  var failed = 0

  template check(name: string, body: untyped) =
    block:
      try:
        body
        inc passed
        echo "  PASS: " & name
      except CatchableError:
        inc failed
        echo "  FAIL: " & name & " - " & getCurrentExceptionMsg()

  # -----------------------------------------------------------------------
  # (a) structArtifactIdentity — determinism + three-level separation
  # -----------------------------------------------------------------------
  check "structArtifactIdentity determinism":
    let vid = newLineageId("verify-subject-42")
    let id1 = structArtifactIdentity(vid, "z3", "cfg-a", "inputs-x", "params-p")
    let id2 = structArtifactIdentity(vid, "z3", "cfg-a", "inputs-x", "params-p")
    assert id1.artifactId == id2.artifactId, "content digest must be deterministic"
    assert id1.executionId == id2.executionId, "execution id must be deterministic"
    assert id1.verificationId == id2.verificationId, "lineage id must be deterministic"

  check "structArtifactIdentity three-level separation":
    let vid = newLineageId("verify-subject-42")
    let id = structArtifactIdentity(vid, "z3", "cfg-a", "inputs-x", "params-p")
    # artifactId (content), executionId (execution), verificationId (lineage)
    # must all be distinct — no single hash serves double duty (禁止 #3)
    assert string(id.artifactId) != string(id.executionId),
      "artifactId and executionId must differ"
    assert string(id.artifactId) != string(id.verificationId),
      "artifactId and verificationId must differ"
    assert string(id.executionId) != string(id.verificationId),
      "executionId and verificationId must differ"
    # Each must be a valid content-addressed form
    assert isValidSha256Ref(string(id.artifactId)),
      "artifactId must be a valid sha256 ref"
    assert isValidSha256Ref(string(id.executionId)),
      "executionId must be a valid sha256 ref"
    assert isValidSha256Ref(string(id.verificationId)),
      "verificationId must be a valid sha256 ref"

  # -----------------------------------------------------------------------
  # (b) ProvenanceGraph — complete chain vs broken chain
  # -----------------------------------------------------------------------
  check "findBrokenChains complete chain returns empty":
    let execNode = ProvenanceNode(nodeId: "exec-1", kind: pnkObservation, payloadRef: "src/foo.nim")
    let proofNode = ProvenanceNode(nodeId: "proof-1", kind: pnkArtifact, payloadRef: "proof-artifact-1")
    let certNode  = ProvenanceNode(nodeId: "cert-1",  kind: pnkArtifact, payloadRef: "cert-artifact-1")

    let edges = @[
      ProvenanceEdge(edgeKind: peProves,     fromNode: "exec-1", toNode: "proof-1"),
      ProvenanceEdge(edgeKind: pePromotedBy, fromNode: "proof-1", toNode: "cert-1")
    ]
    let graph = buildGraph(@[execNode, proofNode, certNode], edges)
    let broken = findBrokenChains(graph, "execution")
    assert broken.len == 0, "complete chain should have no broken links"

  check "findBrokenChains detects missing peProves (execution gap)":
    let execNode = ProvenanceNode(nodeId: "exec-2", kind: pnkObservation, payloadRef: "src/bar.nim")
    let proofNode = ProvenanceNode(nodeId: "proof-2", kind: pnkArtifact, payloadRef: "proof-artifact-2")
    # Missing: no peProves edge from exec-2 to proof-2
    let edges = @[
      ProvenanceEdge(edgeKind: pePromotedBy, fromNode: "proof-2", toNode: "cert-2")
    ]
    let graph = buildGraph(@[execNode, proofNode], edges)
    let broken = findBrokenChains(graph, "execution")
    assert broken.len == 1, "should report exactly one broken chain"
    assert broken[0].missingEdge == peProves, "missing edge should be peProves"
    assert broken[0].fromNode == "exec-2", "broken node should be exec-2"
    assert broken[0].expectedToKind == pnkArtifact, "target kind should be pnkArtifact"
    assert broken[0].integrityPattern == "observation without proof link"

  check "findBrokenChains detects missing pePromotedBy (promotion gap)":
    let execNode = ProvenanceNode(nodeId: "exec-3", kind: pnkObservation, payloadRef: "src/baz.nim")
    let proofNode = ProvenanceNode(nodeId: "proof-3", kind: pnkArtifact, payloadRef: "proof-artifact-3")
    # Has peProves but missing pePromotedBy
    let edges = @[
      ProvenanceEdge(edgeKind: peProves, fromNode: "exec-3", toNode: "proof-3")
      # no pePromotedBy edge from proof-3
    ]
    let graph = buildGraph(@[execNode, proofNode], edges)
    let broken = findBrokenChains(graph, "proof")
    assert broken.len == 1, "should report exactly one broken chain"
    assert broken[0].missingEdge == pePromotedBy, "missing edge should be pePromotedBy"
    assert broken[0].fromNode == "proof-3", "broken node should be proof-3"
    assert broken[0].integrityPattern == "artifact without promotion link"

  check "declaredVsExecuted set difference":
    let declared = @["gate-a", "gate-b", "gate-c"]
    let executed = @["gate-a", "gate-c"]
    let gaps = declaredVsExecuted(declared, executed)
    assert gaps.len == 1, "should have exactly one gap"
    assert gaps[0] == "gate-b", "the gap should be gate-b"

  check "linkExecutionToArtifact complete chain":
    let edges = @[
      ProvenanceEdge(edgeKind: peProves,     fromNode: "exec-1", toNode: "proof-1"),
      ProvenanceEdge(edgeKind: pePromotedBy, fromNode: "proof-1", toNode: "cert-1")
    ]
    let status = linkExecutionToArtifact(edges)
    assert status == csComplete, "complete chain should return csComplete"

  check "linkExecutionToArtifact incomplete chain":
    let edges = @[
      ProvenanceEdge(edgeKind: peProves, fromNode: "exec-1", toNode: "proof-1")
      # missing pePromotedBy
    ]
    let status = linkExecutionToArtifact(edges)
    assert status == csMissingEdge, "incomplete chain should return csMissingEdge"

  # -----------------------------------------------------------------------
  # Summary
  # -----------------------------------------------------------------------
  echo "\n  " & $passed & " passed, " & $failed & " failed"
  if failed > 0:
    quit(1)

when isMainModule:
  main()
