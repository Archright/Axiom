## Audit Layer Bridge — Thin Interface for tools/
## Re-exports hotspot analysis and burn-down queue types.
import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [CatchableError].}
import core/audit/hotspot_analyzer
import core/audit/burn_down_queue
export hotspot_analyzer.computeChurnScores
export burn_down_queue.HotspotTier, burn_down_queue.HotspotEntry
export burn_down_queue.buildPriorityQueue
{.pop.}