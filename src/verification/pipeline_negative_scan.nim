import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [CatchableError].}

import verification/pipeline_negative_scan_part1
export pipeline_negative_scan_part1
import verification/pipeline_negative_scan_part2
export pipeline_negative_scan_part2
import verification/pipeline_negative_scan_part3
# axiomIoBoundary
export pipeline_negative_scan_part3
{.pop.}
