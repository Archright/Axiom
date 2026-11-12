{.push raises: [].}

## Wave 2 relocation — Minimal Verification test
## Validates that relocated modules compile and their public API is accessible.
## Deleted modules (heal_parsing, heal_analysis, heal_node_executor) are no longer
## tested here; their successors live in core/types/heal_types.

import verification/state_manager
import core/boundary/persona_interface
import core/types/heal_types

# Compile-time verification: persona_interface artifact types
static:
  var la: LegislatorArtifact
  var da: DetectiveArtifact
  var ja: JudgeArtifact
  var sa: SwatArtifact
  discard la
  discard da
  discard ja
  discard sa

# Runtime verification: state_manager public procs are reachable
let state = loadProofState("nonexistent.json")
discard state

# Compile-time verification: heal_types exports are accessible
static:
  doAssert HintManager isnot void
  doAssert HealNodeInput isnot void

{.pop.}
