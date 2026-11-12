import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

## Job Semaphore
##
## Thread-safe counting semaphore for gate concurrency control.
## Limits the number of concurrently executing gate processes to
## ``maxJobs``, blocking callers via condition variable when the
## limit is reached.
##
## Part of the 4-Layer Resource Defense Stack (L1 CPU).
## Used by the orchestrator to prevent CPU saturation during
## parallel gate execution.
import std/locks
import ../core/trusted/axiom_pragmas

type JobSemaphore* = object
  lock: Lock
  cond: Cond
  maxJobs: int
  activeJobs: int

## Initializes a ``JobSemaphore`` with the given concurrency limit.
## ``maxJobs`` must be >= 1. The semaphore starts with 0 active jobs.
  ## axiom-smt: (assert (and (and (>= maxJobs -9223372036854775808) (<= maxJobs 9223372036854775807)) (>= result 0)))
  ## axiom-lean: maxJobs ≥ -9223372036854775808 ∧ maxJobs ≤ 9223372036854775807 ∧ (result ≥ 0)
func initJobSemaphore*(maxJobs: int): JobSemaphore {.axiomTryImpl.} =
  result.maxJobs = maxJobs
  result.activeJobs = 0
  initLock(result.lock)
  initCond(result.cond)

## Acquires a semaphore token, blocking if ``maxJobs`` are already active.
## Uses a condition variable to avoid busy-waiting.
  ## axiom-smt: (assert (and (>= sem_activeJobs 0) (>= sem_maxJobs 0) (and (>= sem_maxJobs -9223372036854775808) (<= sem_maxJobs 9223372036854775807)) (and (>= sem_activeJobs -9223372036854775808) (<= sem_activeJobs 9223372036854775807))))
  ## axiom-lean: sem_activeJobs ≥ 0 ∧ sem_maxJobs ≥ 0 ∧ sem_maxJobs ≥ -9223372036854775808 ∧ sem_maxJobs ≤ 9223372036854775807 ∧ sem_activeJobs ≥ -9223372036854775808 ∧ sem_activeJobs ≤ 9223372036854775807
func acquire*(sem: var JobSemaphore) {.axiomTryImpl.} =
  acquire(sem.lock)
  while sem.activeJobs >= sem.maxJobs:
    wait(sem.cond, sem.lock)
  inc(sem.activeJobs)
  release(sem.lock)

## Releases a semaphore token, signaling one waiting caller.
## Must be called exactly once per ``acquire`` to prevent resource leaks.
  ## axiom-smt: (assert (and (>= sem_activeJobs 0) (and (>= sem_maxJobs -9223372036854775808) (<= sem_maxJobs 9223372036854775807)) (and (>= sem_activeJobs -9223372036854775808) (<= sem_activeJobs 9223372036854775807))))
  ## axiom-lean: sem_activeJobs ≥ 0 ∧ sem_maxJobs ≥ -9223372036854775808 ∧ sem_maxJobs ≤ 9223372036854775807 ∧ sem_activeJobs ≥ -9223372036854775808 ∧ sem_activeJobs ≤ 9223372036854775807
func release*(sem: var JobSemaphore) {.axiomTryImpl.} =
  acquire(sem.lock)
  dec(sem.activeJobs)
  signal(sem.cond)
  release(sem.lock)
{.pop.}
