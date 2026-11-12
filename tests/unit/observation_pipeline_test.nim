## Unit tests for observation_pipeline.nim — 3-Stage Verification Observation Pipeline.
## Uses custom main() pattern to avoid unittest framework crashes.
## Verifies: classification contract, 3-stage transition integrity,
## content-addressed digest sensitivity, and status downgrade correctness.

import std/[os, strutils]
import core/crypto/hash_kernel
import verification/verification_dependency
import verification/observation_pipeline

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

  echo "=== Classification contract ==="

  block:
    check "module_content -> SEMANTIC":
      assert classifyReadClass(rcModuleContent) == dkSemantic
    check "baseline -> SEMANTIC":
      assert classifyReadClass(rcBaseline) == dkSemantic
    check "module_existence -> UNCLASSIFIED":
      assert classifyReadClass(rcModuleExistence) == dkUnclassified
    check "env_var -> UNCLASSIFIED":
      assert classifyReadClass(rcEnvVar) == dkUnclassified
    check "cwd -> UNCLASSIFIED":
      assert classifyReadClass(rcCwd) == dkUnclassified
    check "compiler_subprocess -> UNCLASSIFIED":
      assert classifyReadClass(rcCompilerSubprocess) == dkUnclassified
    check "other -> UNCLASSIFIED":
      assert classifyReadClass(rcOther) == dkUnclassified
    check "commit_id -> PROVENANCE":
      assert classifyReadClass(rcCommitId) == dkProvenance
    check "timestamp -> INTERNAL":
      assert classifyReadClass(rcTimestamp) == dkInternal
    check "gate_output -> OUTPUT":
      assert classifyReadClass(rcGateOutput) == dkOutput

  echo ""
  echo "=== 3-stage transition integrity ==="

  block:
    let raw = newRawObservation("src/core/gate/gate_memo.nim", rcModuleContent, "module contents here")
    let cls = classify(raw)
    check "classify produces ClassifiedObservation":
      assert cls.classifiedPath == "src/core/gate/gate_memo.nim"
    check "classify preserves read class":
      assert cls.classifiedReadClass == rcModuleContent
    check "classify preserves content":
      assert cls.classifiedContent == "module contents here"
    check "SEMANTIC + content -> Complete status":
      assert cls.classifiedStatus == osComplete
    let val = validate(cls)
    check "validate produces ValidatedDependency":
      assert val.depPath == "src/core/gate/gate_memo.nim"
    check "validate preserves kind":
      assert val.depKind == dkSemantic
    check "validate preserves content digest":
      assert val.depContentDigest.len > 0
    check "validate preserves status":
      assert val.depStatus == osComplete
    check "resolve SEMANTIC + Complete -> drDeclared":
      assert resolve(val) == drDeclared

  block:
    let raw = newRawObservation("/etc/hosts", rcOther, "")
    let cls = classify(raw)
    check "UNCLASSIFIED -> osUnclassified":
      assert cls.classifiedStatus == osUnclassified
    let val = validate(cls)
    check "UNCLASSIFIED -> FailClosed resolution":
      assert resolve(val) == drFailClosed

  block:
    # SEMANTIC read with NO content -> Incomplete -> Recompute
    let raw = newRawObservation("src/x.nim", rcModuleContent, "")
    let cls = classify(raw)
    check "SEMANTIC no content -> Incomplete":
      assert cls.classifiedStatus == osIncomplete
    let val = validate(cls)
    check "SEMANTIC no content -> Recompute":
      assert resolve(val) == drRecompute

  block:
    # PROVENANCE with content -> Complete -> Recompute (not semantic)
    let raw = newRawObservation("HEAD", rcCommitId, "abc123")
    let cls = classify(raw)
    let val = validate(cls)
    check "PROVENANCE -> not Declared":
      assert resolve(val) != drDeclared

  echo ""
  echo "=== Content-addressed digest sensitivity (KEY FIX TEST) ==="

  block:
    # Same path + same readClass + DIFFERENT content -> DIFFERENT digest
    let rawA = newRawObservation("src/foo.nim", rcModuleContent, "content-AAA")
    let rawB = newRawObservation("src/foo.nim", rcModuleContent, "content-BBB")
    let clsA = classify(rawA)
    let clsB = classify(rawB)
    check "same path, different content -> different classified content":
      assert clsA.classifiedContent != clsB.classifiedContent
    let valA = validate(clsA)
    let valB = validate(clsB)
    check "same path, different content -> different contentDigest":
      assert valA.depContentDigest != valB.depContentDigest

  block:
    # Same content -> same digest
    let rawA = newRawObservation("src/foo.nim", rcModuleContent, "same-content")
    let rawB = newRawObservation("src/foo.nim", rcModuleContent, "same-content")
    let valA = validate(classify(rawA))
    let valB = validate(classify(rawB))
    check "same content -> same contentDigest":
      assert valA.depContentDigest == valB.depContentDigest

  block:
    # Different readClass + same content -> different digest
    let valA = validate(classify(newRawObservation("src/foo.nim", rcModuleContent, "content")))
    let valB = validate(classify(newRawObservation("src/foo.nim", rcBaseline, "content")))
    check "different readClass -> different contentDigest":
      assert valA.depContentDigest != valB.depContentDigest

  block:
    # Non-SEMANTIC kinds produce empty digest
    let val = validate(classify(newRawObservation("HEAD", rcCommitId, "abc123")))
    check "PROVENANCE -> empty contentDigest":
      assert val.depContentDigest == ""

  echo ""
  echo "=== Status downgrade semantics ==="

  block:
    # SEMANTIC no content -> Incomplete -> Recompute
    let raw = newRawObservation("src/x.nim", rcModuleContent, "")
    let cls = classify(raw)
    check "SEMANTIC no content -> Incomplete status":
      assert cls.classifiedStatus == osIncomplete
    let val = validate(cls)
    check "SEMANTIC no content -> osIncomplete after validate":
      assert val.depStatus == osIncomplete
    check "SEMANTIC no content -> drRecompute":
      assert resolve(val) == drRecompute

  block:
    # UNCLASSIFIED -> FailClosed
    let raw = newRawObservation("/etc/hosts", rcOther, "")
    let cls = classify(raw)
    let val = validate(cls)
    check "UNCLASSIFIED -> osUnclassified":
      assert val.depStatus == osUnclassified
    check "UNCLASSIFIED -> drFailClosed":
      assert resolve(val) == drFailClosed

  block:
    # PROVENANCE no content -> Unknown
    let raw = newRawObservation("HEAD", rcCommitId, "")
    let cls = classify(raw)
    let val = validate(cls)
    check "PROVENANCE no content -> osUnknown":
      assert val.depStatus == osUnknown
    check "PROVENANCE no content -> drRecompute (not Declared)":
      assert resolve(val) != drDeclared

  echo ""
  echo "=== Results: " & $passed & " passed, " & $failed & " failed ==="
  if failed > 0: quit(1)

main()
