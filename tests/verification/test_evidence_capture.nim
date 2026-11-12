# Phase-2 Evidence Capture — lossless, no-claim vertical slice.
# Capture must be deterministic and must NOT decide PROVED/assurance/cert/VKD.

import std/sequtils
import std/strutils
import core/trusted/layer_declaration
import core/trusted/axiom_ir_helpers
import core/trusted/specification_artifact
import core/trusted/evidence_capture
import core/trusted/dependency_snapshot

proc makeFuncDef(post: string): IRFuncDef =
  ## Minimal IR func with one synthesized postcondition.
  let bv64 = irTypeBitVec64()
  let x = irVar("x", bv64)
  let postCond = irBinOp(boGe, irVar("result", bv64), x)
  result = irFuncDef(
    name = "f",
    params = @[("x", bv64)],
    ret = bv64,
    body = x
  )
  result.postConditions = @[postCond]

proc main() =
  echo "=== Phase-2 Evidence Capture ==="

  # 1. same funcDef -> same SpecID (deterministic capture identity)
  block:
    let f1 = makeFuncDef("x")
    let f2 = makeFuncDef("x")
    let s1 = captureSpecification(f1, soCanonicalDerived, "v1")
    let s2 = captureSpecification(f2, soCanonicalDerived, "v1")
    doAssert s1.specIdentity == s2.specIdentity,
      "specId must be identical for the same funcDef"
    doAssert s1.rawPostConditions.len == f1.postConditions.len,
      "raw IRExpr must be preserved (not reconstructed)"
    echo "  OK: same funcDef -> same SpecID"

  # 2. postcondition change -> SpecID changes
  block:
    let f1 = makeFuncDef("x")
    let f2 = makeFuncDef("y")  # different body/post
    # force a different postcondition
    let s1 = captureSpecification(f1, soCanonicalDerived, "v1")
    var f2b = f2
    f2b.postConditions = @[irBinOp(boGe, irVar("result", irTypeBitVec64()), irLit(0))]
    let s2 = captureSpecification(f2b, soCanonicalDerived, "v1")
    doAssert s1.specIdentity != s2.specIdentity,
      "postcondition change must change SpecID"
    echo "  OK: postcondition change -> SpecID changes"

  # 3. dependency change -> snapshot hash changes (no policy)
  block:
    let d1 = captureDependencySnapshot(@["a", "b"], "src")
    let d2 = captureDependencySnapshot(@["a", "c"], "src")
    doAssert d1.snapshotHash != d2.snapshotHash, "deps change must change snapshot hash"
    doAssert d1.snapshotHash == captureDependencySnapshot(@["a", "b"], "src").snapshotHash,
      "same deps -> same hash"
    echo "  OK: dependency snapshot hash sensitive + deterministic"

  # 4. full capture: no claim decided, minimal solver evidence (no proof digest)
  block:
    let f = makeFuncDef("x")
    let bundle = captureEvidence(f, soCanonicalDerived, "v1", @["a"], "src")
    doAssert bundle.specificationArtifact.specIdentity.len > 0
    doAssert bundle.dependencySnapshot.snapshotHash.len > 0
    doAssert bundle.facts.solver.solverIdentity == "z3"
    doAssert bundle.facts.provenanceComplete == false, "capture must not claim provenance"
    doAssert bundle.facts.solver.proofDigest == "", "no proof artifact required in T0"
    echo "  OK: capture is claim-free + minimal solver evidence"

  echo "=== Phase-2 Evidence Capture OK ==="
