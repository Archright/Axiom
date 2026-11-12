import core/trusted/layer_declaration
axiomLayer "presentation"
{.push raises: [CatchableError].}

import ui/ax_tui_reporter_part1
import ui/ax_tui_reporter_part2
export ax_tui_reporter_part1
export ax_tui_reporter_part2
{.pop.}
