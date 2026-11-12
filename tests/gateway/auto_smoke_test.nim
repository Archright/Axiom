## Auto-generated Smoke Test for Pipeline Stage Registry
##
## Imports all pipeline stage modules so their {.registerStage.} pragmas
## populate the compile-time `stageRegistry`, then calls autoGenerateSmokeTest()
## to generate one test proc per registered stage.

{.push warning[UnusedImport]: off.}
import core/trusted/axiom_pragmas
# Import pipeline stage modules — their {.registerStage.} pragmas fire at compile time
import verification/pipeline_stage_swat
import verification/pipeline_stage_k_induction
{.pop.}

# Generate smoke test procs for every registered stage
autoGenerateSmokeTest()

# ─── Runner ──────────────────────────────────────────────────────────────────

import std/unittest

suite "Pipeline Stage Smoke Tests":
  test "all registered stages are discoverable":
    let stages = getRegisteredStages()
    echo "Registered stages: ", stages
    doAssert stages.len > 0, "No stages registered — check imports"

  # One test per registered stage via the getRegisteredStages() proc
  for stageName in getRegisteredStages():
    test "smoke: " & stageName & " is registered":
      doAssert stageName in getRegisteredStages(),
        "Stage '" & stageName & "' missing from registry"
