import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [CatchableError].}

# ── imported sub-modules ──
import verification/pipeline_core_runner_part1
import verification/pipeline_core_runner_part2
# axiomIoBoundary
export pipeline_core_runner_part1
export pipeline_core_runner_part2
{.pop.}
