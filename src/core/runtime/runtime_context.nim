## runtime_context.nim — Extended runtime context with shadow guard.
##
## Shadow-first registration guard for testing gates before promotion to L0.
##
## Architecture: Runtime module in src/core/runtime/.
## Imports: std/*, core/types/results, core/schema/task_schema (SOC-compliant).

import core/trusted/layer_declaration
axiomLayer "domain"
import std/deques
import core/types/results
import core/schema/task_schema
{.push raises: [].}

# ---------------------------------------------------------------------------
# Types
# ---------------------------------------------------------------------------

type
  GitOperations* = proc(operation: string, args: seq[string]): Result[string, string] {.gcsafe.}
    ## Abstract git operations — wraps git CLI behind a pure interface.

  ShadowGuard* = object
    ## Shadow-first registration guard.
    ## Tracks success rate to determine promotion readiness.
    tolerance*: ShadowTolerance
    shadowMode*: bool
    successCount*: int
    totalAttempts*: int
    recentResults*: Deque[bool]   ## Sliding window of recent results

  ShadowEnvironment* = object
    ## Shadow environment for testing before promotion.
    guard*: ShadowGuard
    baselinePath*: string
    currentPath*: string

# ---------------------------------------------------------------------------
# ShadowGuard Operations
# ---------------------------------------------------------------------------

func initShadowGuard*(tolerance: ShadowTolerance, shadowMode: bool = false): ShadowGuard =
  ## Construct a ShadowGuard with properly initialized sliding window.
  ShadowGuard(
    tolerance: tolerance,
    shadowMode: shadowMode,
    successCount: 0,
    totalAttempts: 0,
    recentResults: initDeque[bool]()
  )

func isPromotable*(guard: ShadowGuard): bool {.gcsafe.} =
  ## Check if shadow gate can be promoted to L0.
  ## Requires: sliding window filled, autoPromote enabled, both window and overall rates above thresholds.
  if guard.recentResults.len < guard.tolerance.windowSize: return false
  if not guard.tolerance.autoPromote: return false
  var windowSuccess = 0
  for r in guard.recentResults:
    if r: inc windowSuccess
  let windowRate = windowSuccess.float / guard.recentResults.len.float
  let overallRate = if guard.totalAttempts > 0: guard.successCount.float / guard.totalAttempts.float else: 0.0
  windowRate >= guard.tolerance.promotionThreshold and overallRate >= guard.tolerance.minSuccessRate

func recordResult*(guard: var ShadowGuard, success: bool) {.gcsafe.} =
  ## Record an execution result for promotion tracking.
  ## Maintains the sliding window — evicts oldest when exceeding windowSize.
  inc guard.totalAttempts
  if success: inc guard.successCount
  guard.recentResults.addLast(success)
  if guard.recentResults.len > guard.tolerance.windowSize:
    let removed = guard.recentResults.popFirst()
    if removed: dec guard.successCount

# ---------------------------------------------------------------------------
# ShadowEnvironment Operations
# ---------------------------------------------------------------------------

func diff*(env: ShadowEnvironment): float =
  ## Calculate diff percentage between baseline and current.
  ## Placeholder — real implementation reads and compares files.
  0.0

{.pop}
