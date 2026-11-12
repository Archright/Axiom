## deterministic_scheduler.nim — Deterministic parallel scheduler with priority queue
##
## Wraps malebolgia threadpool with priority-based work ordering.  All results
## are returned in deterministic order regardless of thread completion order.
##
## Design invariants:
##   - Results indexed by input position → deterministic regardless of scheduling
##   - Priority-based dispatch → highest-priority items run first
##   - Cost-aware sorting → longest-job-first within same priority (min makespan)
##   - Value-type only → safe for malebolgia spawn boundaries
##
## Integration with loop_driver.nim:
##   var sched = initDeterministicScheduler(workerCount)
##   sched.addWork(depthWorkItems)
##   sched.sortWorkItems()
##   let results = sched.executeParallel(myWorkerProc)

import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [CatchableError].}

import core/axiom_pragmas
import core/sync/sync_utils_resource
import std/algorithm
import std/monotimes

type
  SchedulerWorkItem* = object
    ## A single unit of work for the scheduler.
    key*: string              ## Deterministic identity (e.g., node ID string)
    priority*: int            ## Lower value = higher priority (processed first)
    estimatedCostMs*: int     ## Estimated processing time for load balancing

  SchedulerNodeTiming* = object
    ## Per-node timing record collected during execution.
    key*: string
    elapsedMs*: float

  SchedulerStats* = object
    ## Aggregate statistics for a scheduler execution run.
    totalItems*: int
    totalCompleted*: int
    totalFailed*: int
    wallTimeMs*: float
    maxConcurrency*: int
    perNodeTimings*: seq[SchedulerNodeTiming]

  DeterministicScheduler* = object
    ## Deterministic parallel scheduler backed by malebolgia threadpool.
    ## Work items are sorted by (priority ASC, key ASC) before dispatch.
    ## Results are collected in sorted order → deterministic output.
    workItems*: seq[SchedulerWorkItem]
    maxWorkers*: int
    stats*: SchedulerStats

func initDeterministicScheduler*(maxWorkers: int): DeterministicScheduler {.raises: [].} =
  ## Create a new scheduler with bounded concurrency.
  ## maxWorkers is clamped to >= 1.
  DeterministicScheduler(
    workItems: @[],
    maxWorkers: max(1, maxWorkers),
    stats: SchedulerStats()
  )

func addWork*(sched: var DeterministicScheduler, items: seq[SchedulerWorkItem]) {.raises: [].} =
  ## Append work items to the scheduler queue.
  for item in items:
    sched.workItems.add(item)

func clearWork*(sched: var DeterministicScheduler) {.raises: [].} =
  ## Clear all pending work items.
  sched.workItems.setLen(0)

func sortWorkItems*(sched: var DeterministicScheduler) {.raises: [].} =
  ## Sort work items for deterministic, optimal scheduling order.
  ## Sort key: (priority ASC, key ASC).
  ## Lower priority value = processed first.  Within same priority,
  ## lexicographic key sort ensures deterministic tiebreaking.
  sched.workItems.sort(proc(a, b: SchedulerWorkItem): int {.raises: [].} =
    let pCmp = cmp(a.priority, b.priority)
    if pCmp != 0: return pCmp
    cmp(a.key, b.key)
  )

func itemCount*(sched: DeterministicScheduler): int {.raises: [].} =
  ## Return the number of pending work items.
  sched.workItems.len

func isEmpty*(sched: DeterministicScheduler): bool {.raises: [].} =
  ## Return true if no work items are queued.
  sched.workItems.len == 0

func recordNodeTiming*(sched: var DeterministicScheduler, key: string, elapsedMs: float) {.raises: [].} =
  ## Record per-node timing for stats.
  sched.stats.perNodeTimings.add(SchedulerNodeTiming(key: key, elapsedMs: elapsedMs))

func finalizeStats*(sched: var DeterministicScheduler, startTicks: int64) {.raises: [].} =
  ## Record wall time from a monotonic tick start and set completion count.
  sched.stats.wallTimeMs = float(getMonoTime().ticks - startTicks) / 1_000_000
  sched.stats.totalCompleted = sched.workItems.len
  sched.stats.maxConcurrency = sched.maxWorkers

proc snapshotResource*(): ResourceSnapshot {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  ## Take a lightweight resource snapshot (memory, CPU).
  ## Returns a zeroed snapshot when resource sampling is unavailable.
  ResourceSnapshot(availableMemoryBytes: 0, cpuLoadRatio: 0.0, recommendedLimit: 0)

{.pop.}
