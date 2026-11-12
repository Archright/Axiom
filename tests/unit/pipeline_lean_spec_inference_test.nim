import std/unittest

import core/logic/universal_translation_types
import verification/pipeline_lean_spec_inference

suite "Universal pipeline Lean spec inference":
  test "dedicated module infers replay metadata":
    let translation = UniversalTranslation(
      language: "nim",
      functionName: "advance",
      ilEntries: @[AstMapEntry(kind: "loop", il: "add version")],
      smt2: "(assert true)",
      controlFlowCount: 1,
      memoryAccessCount: 0,
      stateSpace: @["version"],
      stateInvariants: @["version >= 0"],
      transitionRelation: @["env delta -> version"],
      transitionInvariants: @["next.version >= state.version"],
      operationalSemantics: @["assign version_next"],
      environmentInputs: @["delta"],
      envInputConstructors: @[],
      stepFunctionCases: @[],
      loopControlVariables: @["version"],
      rankVariables: @["version"]
    )

    let direct = pipeline_lean_spec_inference.inferLeanSpec(
      "src/sample.nim",
      "advance",
      translation,
      "",
      "version >= 0"
    )

    check direct.theoremName.len > 0
    check direct.environmentInputs == @["delta"]
    check direct.stepConstructors.len >= 2
    check "version" in direct.rankVariables
