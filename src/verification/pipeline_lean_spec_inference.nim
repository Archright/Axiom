import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

import verification/pipeline_lean_spec_inference_part1
import verification/pipeline_lean_spec_inference_part2
import verification/pipeline_lean_spec_inference_part3
# axiomIoBoundary
export pipeline_lean_spec_inference_part1
export pipeline_lean_spec_inference_part2
export pipeline_lean_spec_inference_part3
{.pop.}
