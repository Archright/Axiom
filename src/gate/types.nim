import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

## Gate Domain Types
##
## Extended type definitions for the gate layer beyond gate_types.nim.
## Includes resource limit types, process execution metadata,
## and gate scheduling primitives.
import std/strutils
import std/cpuinfo
import core/parsers/safe_parsers
import core/results
import core/trusted/axiom_pragmas
import core/trusted/env_access
import gate/gate_types
export gate_types

const MaxStdoutPerGate* = 2 * 1024 * 1024  ## 2MB hard cap per gate stdout/stderr
  ## Emergency defense against Nim 2.0 ORC per-thread allocation leak.
  ## See: docs/history/oom-reinvestigation-2026-05-27.md
  ## Remove once Zero-String Pipeline (Phase 1) is deployed.

# ============================================================================
# Memory-Aware Concurrency Utilities (Layer 1 OOM Defense)
# ============================================================================

proc getMemAvailableMB*(): int =
  ## Read Linux /proc/meminfo MemAvailable in megabytes.
  ## Returns -1 on any error (permission, parse failure, non-Linux).
  try:
    for line in lines("/proc/meminfo"):
      if line.startsWith("MemAvailable:"):
        let parts = line.splitWhitespace()
        if parts.len >= 2:
          let parsed = safeParseInt(parts[1])
          if parsed.isOk:
            return parsed.get div 1024
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)
  return -1

proc safeMaxJobs*(requested: int): int =
  ## Dynamically cap maxJobs based on available system memory AND CPU cores.
  ## Respects AXIOM_FORCE_MAX_JOBS and AXIOM_MEM_HEADROOM env vars.
  ## CPU cap: leaves 2 cores for UI/GPU/chrome to prevent desktop freeze.
  if getAxiomEnv(evForceMaxJobs).len > 0:
    return requested
  let avail = getMemAvailableMB()
  if avail < 0:
    return requested
  let headroomRaw = safeParseInt(getAxiomEnv(evMemHeadroom, "800"))
  let headroom = if headroomRaw.isOk: headroomRaw.get else: 800
  let memPerJobRaw = safeParseInt(getAxiomEnv(evMemPerJob, "300"))
  let memPerJob = if memPerJobRaw.isOk: memPerJobRaw.get else: 300
  let memBased = (avail - headroom) div memPerJob
  result = max(1, min(requested, memBased))
  # Layer 1b: CPU-aware throttling -- prevent UI freeze on workstation.
  # Use half of cores (rounded down) to leave headroom for chrome/GPU/Xorg.
  let cpuBased = max(1, countProcessors() div 2)
  result = min(result, cpuBased)

# ============================================================================
# DEBT#009: Multiplicative Parallelism Mitigation (Global Concurrency Budget)
# ============================================================================

proc computeGlobalConcurrencyBudget*(): int =
  ## Total worker process budget across ALL concurrent gate processes.
  ##
  ## Problem: Each gate independently computed maxJobs = safeMaxJobs(cost),
  ## which returns countProcessors() div 2. With 4 concurrent gates on a 16-core
  ## machine: 4 * 8 = 32 workers -- 2x overcommit causing OOM + GPU starvation.
  ##
  ## Solution: Compute a single global budget (CPU-aware + memory-aware), then
  ## divide among concurrent gates at spawn time via globalThrottledMaxJobs().
  ##
  ## Context7: Nim ORC uses reference counting + cycle collection. Per-thread
  ## allocation pressure scales with concurrent process count (destructors.md).
  ## AGENTS.md section 1.2: L1 CPU cap = countProcessors() div 2.
  let cpuCores = countProcessors()
  ## Leave 2 cores for UI/GPU/Xorg to prevent desktop freeze (L1 defense).
  let cpuBudget = max(1, cpuCores div 2)
  ## Memory-aware cap: safeMaxJobs applies (MemAvailable - headroom) / perJob.
  let memBudget = safeMaxJobs(cpuBudget)
  result = max(1, min(cpuBudget, memBudget))

proc globalThrottledMaxJobs*(gateCost: int; activeGateCount: int): int =
  ## Compute per-gate maxJobs that respects the global concurrency budget.
  ## DEBT#009: Previously each gate claimed countProcessors() div 2 workers.
  ## Now: total across all concurrent gates <= computeGlobalConcurrencyBudget().
  ##
  ## gateCost: the weight of this specific gate (e.g. gwHeavy = 3)
  ## activeGateCount: number of gates currently running (including this one)
  let budget = computeGlobalConcurrencyBudget()
  let perGateShare = max(1, budget div max(1, activeGateCount))
  result = max(1, min(perGateShare, gateCost))

# ============================================================================
# Per-Process Memory Limit (Layer 2 OOM Defense)
# ============================================================================

when defined(posix):
  import std/posix

  const RLIMIT_AS* = 9.cint
  const RLIM_INFINITY* = -1

  proc setProcessMemoryLimit*(mb: int) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
    ## Set RLIMIT_AS (virtual address space limit) for the current process
    ## and all future child processes (inherited via fork).
    ## Call before a batch loop; reset to RLIM_INFINITY after.
    var lim: RLimit
    lim.rlim_cur = mb * 1024 * 1024
    lim.rlim_max = mb * 1024 * 1024
    discard setrlimit(RLIMIT_AS, lim)

  proc resetProcessMemoryLimit*() {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
    ## Remove RLIMIT_AS restriction.
    var lim: RLimit
    lim.rlim_cur = RLIM_INFINITY
    lim.rlim_max = RLIM_INFINITY
    discard setrlimit(RLIMIT_AS, lim)
{.pop.}
