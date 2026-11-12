## Unit tests for z3_pool.getBudgetFor Per-Phase Liveness Ceiling.
## SmtBudget.timeoutMs: liveness ceiling; rlimit (z3DeterministicBudget) is
## the deterministic solve budget. getBudgetFor clamps via min(PhaseDefault, AXIOM_SMT_TIMEOUT).
##
## Env isolation: each test sets/clears AXIOM_SMT_TIMEOUT via putEnv/delEnv
## (std/os, re-exported from std/envvars) before/after, so no leakage across
## tests or into other suites. Nim 2.x uses delEnv (removeEnv is not available).

import std/[unittest, os]
import verification/solver/z3_pool

proc setBudgetEnv(value: string) =
  if value.len == 0:
    delEnv("AXIOM_SMT_TIMEOUT")
  else:
    putEnv("AXIOM_SMT_TIMEOUT", value)

proc clearBudgetEnv() =
  delEnv("AXIOM_SMT_TIMEOUT")

suite "Z3BudgetClamp":
  test "default budget when AXIOM_SMT_TIMEOUT unset":
    clearBudgetEnv()
    defer: clearBudgetEnv()
    check getBudgetFor(spBmc).timeoutMs == 8000
    check getBudgetFor(spBaseCase).timeoutMs == 2000
    check getBudgetFor(spInductiveStep).timeoutMs == 5000

  test "AXIOM_SMT_TIMEOUT=4000 applies per-phase clamp":
    setBudgetEnv("4000")
    defer: clearBudgetEnv()
    check getBudgetFor(spBmc).timeoutMs == 4000
    check getBudgetFor(spBaseCase).timeoutMs == 2000
    check getBudgetFor(spInductiveStep).timeoutMs == 4000

  test "AXIOM_SMT_TIMEOUT=3000 clamps inductive below default":
    setBudgetEnv("3000")
    defer: clearBudgetEnv()
    check getBudgetFor(spBmc).timeoutMs == 3000
    check getBudgetFor(spBaseCase).timeoutMs == 2000
    check getBudgetFor(spInductiveStep).timeoutMs == 3000

  test "AXIOM_SMT_TIMEOUT=0 keeps defaults (fallback)":
    setBudgetEnv("0")
    defer: clearBudgetEnv()
    check getBudgetFor(spBmc).timeoutMs == 8000
    check getBudgetFor(spBaseCase).timeoutMs == 2000
    check getBudgetFor(spInductiveStep).timeoutMs == 5000

  test "AXIOM_SMT_TIMEOUT=-5 keeps defaults (fallback)":
    setBudgetEnv("-5")
    defer: clearBudgetEnv()
    check getBudgetFor(spBmc).timeoutMs == 8000
    check getBudgetFor(spBaseCase).timeoutMs == 2000
    check getBudgetFor(spInductiveStep).timeoutMs == 5000

  test "AXIOM_SMT_TIMEOUT=non-integer keeps defaults (fallback)":
    setBudgetEnv("abc")
    defer: clearBudgetEnv()
    check getBudgetFor(spBmc).timeoutMs == 8000
    check getBudgetFor(spBaseCase).timeoutMs == 2000
    check getBudgetFor(spInductiveStep).timeoutMs == 5000

# ── Z3WorkerLease: per-query exclusive worker lease ────────────────────
# Proves the pool never hands one worker to two in-flight queries: the
# lease blocks while all workers are busy (no shared pipe / stolen
# sentinel), and releaseZ3WorkerLease frees the worker again. z3ExecPersistent
# releases via defer on every exit path, so a normal return AND the
# large-payload bypass return must both leave every worker leasable.

import std/[monotimes, times]  # Thread/createThread come from system (--threads:on)
import core/results  # Result.isOk for z3ExecPersistent return values

type
  LeaseProbe = object
    idx: int
    done: bool
  ExecProbe = object
    okCount: int
    errCount: int

proc selectWorkerThread(p: ptr LeaseProbe) {.thread.} =
  p[].idx = acquireZ3WorkerLease()
  p[].done = true

proc execWorkerThread(p: ptr ExecProbe) {.thread.} =
  const q = "(declare-fun x () Int)\n(assert (= x 42))\n(check-sat)\n"
  for i in 0 ..< 4:
    var cd, td: string
    let r = z3ExecPersistent(q, 5000, desiredWorkers = 2,
      canonicalEnvelopeDigest = cd, transportPayloadDigest = td)
    if r.isOk: inc p[].okCount
    else: inc p[].errCount

proc waitForProbeDone(p: ptr LeaseProbe; timeoutMs: int): bool =
  let deadline = getMonoTime() + initDuration(milliseconds = timeoutMs)
  while getMonoTime() < deadline and not p[].done:
    sleep(10)
  p[].done

suite "Z3WorkerLease":
  test "two concurrent leases are exclusive; select waits while all workers busy":
    z3EnsurePersistentPool(2)
    let first = acquireZ3WorkerLease()
    check first >= 0
    let second = acquireZ3WorkerLease()
    check second >= 0
    check second != first  # two in-flight queries never share one worker

    # Every worker is leased: a third lease attempt must wait instead of
    # returning a busy worker (the pre-lease bug handed out the same index).
    var probe: LeaseProbe
    var t: Thread[ptr LeaseProbe]
    t.createThread(selectWorkerThread, addr probe)
    check not waitForProbeDone(addr probe, 300)  # blocked — no busy handout
    releaseZ3WorkerLease(first)
    check waitForProbeDone(addr probe, 5000)     # freed worker became leasable
    check probe.idx == first
    joinThreads(t)
    releaseZ3WorkerLease(second)
    releaseZ3WorkerLease(probe.idx)

  test "concurrent query threads progress on distinct workers without deadline burns":
    z3EnsurePersistentPool(2)
    var pa, pb: ExecProbe
    var ta, tb: Thread[ptr ExecProbe]
    ta.createThread(execWorkerThread, addr pa)
    tb.createThread(execWorkerThread, addr pb)
    joinThreads(ta)
    joinThreads(tb)
    # Both threads completed all queries with sentinel-correct answers; a
    # shared worker would have burned the 60s read deadline per collision
    # and returned read-deadline errors instead.
    check pa.okCount == 4
    check pa.errCount == 0
    check pb.okCount == 4
    check pb.errCount == 0

  test "normal and large-payload-bypass exits release the lease (no leak)":
    z3EnsurePersistentPool(2)
    var cd, td: string
    let okRes = z3ExecPersistent("(declare-fun x () Int)\n(assert (= x 1))\n(check-sat)\n",
      5000, desiredWorkers = 2,
      canonicalEnvelopeDigest = cd, transportPayloadDigest = td)
    check okRes.isOk
    # >60KB payload bypasses the persistent pipe into the one-shot fallback
    # and returns early — the defer must still release the leased worker.
    var big = "(declare-fun x () Int)\n(assert (= x 1))\n(check-sat)\n"
    while big.len <= 61_000:
      big.add("(assert (>= x 0))\n")
    let bigRes = z3ExecPersistent(big, 20000, desiredWorkers = 2,
      canonicalEnvelopeDigest = cd, transportPayloadDigest = td)
    check bigRes.isOk
    # Both workers must be leasable again immediately; one leaked lease
    # would leave at most one free worker and the second acquisition below
    # would block until the watchdog times out.
    let a = acquireZ3WorkerLease()
    check a >= 0
    var probe: LeaseProbe
    var t: Thread[ptr LeaseProbe]
    t.createThread(selectWorkerThread, addr probe)
    check waitForProbeDone(addr probe, 3000)
    joinThreads(t)
    releaseZ3WorkerLease(a)
    releaseZ3WorkerLease(probe.idx)
