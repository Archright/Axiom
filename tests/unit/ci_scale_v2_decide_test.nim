import std/[options, sequtils, unittest]
import ci/scale_v2/decide

proc r(host: string; busy: bool; online: bool = true): RunnerObs =
  RunnerObs(host: host, busy: busy, online: online)

proc freeSlot(i: int; p: Policy): SlotRecord =
  SlotRecord(index: i, host: slotHostName(p, i), lease: none(ProvisionLease))

proc leased(i: int; host: string; st: SlotState; startS: int64): SlotRecord =
  SlotRecord(index: i, host: host, lease: some(newLease(i, host, st, startS)))

proc leased(i: int; host: string; st: SlotState; startS: int64;
            absentSinceS, idleSinceS: int64): SlotRecord =
  SlotRecord(index: i, host: host, lease: some(newLease(i, host, st, startS)),
             absentSinceS: absentSinceS, idleSinceS: idleSinceS)

suite "capacity math":
  test "requiredCapacity = queued + busy; desired = min(required, maxCapacity)":
    let p = defaultPolicy()
    let now = 1_500i64
    let res = decide(DecideInput(
      nowS: now, policy: p, queuedMatchingJobs: 2,
      runners: @[r("ax-ci-v2-r0", true), r("ax-ci-v2-r1", true)],
      slots: @[leased(0, "ax-ci-v2-r0", ssRegistered, now - 800),
               leased(1, "ax-ci-v2-r1", ssRegistered, now - 800)]))
    check res.requiredCapacity == 4
    check res.desired == 4
    check res.busy == 2
    check res.available == 0

  test "desired never exceeds maxCapacity=16":
    let p = defaultPolicy()
    let now = 1_500i64
    var runners: seq[RunnerObs] = @[]
    for i in 0 ..< 4:
      runners.add(r(slotHostName(p, i), true))
    let res = decide(DecideInput(nowS: now, policy: p, queuedMatchingJobs: 20,
                                 runners: runners, slots: @[]))
    check res.requiredCapacity == 24
    check res.desired == 16

suite "scale-up":
  test "shortage is based on actualCapacity (busy+available+provisioning), round cap 4":
    let p = defaultPolicy()
    let now = 1_500i64
    var runners = @[r("ax-ci-v2-r0", true), r("ax-ci-v2-r1", true),
                    r("ax-ci-v2-r2", false)]
    var slots: seq[SlotRecord] = @[]
    for i in 0 ..< 3:
      slots.add(leased(i, slotHostName(p, i), ssRegistered, now - 800))
    for i in 3 ..< 6:
      slots.add(leased(i, slotHostName(p, i), ssProvisioning, now - 100))
    let res = decide(DecideInput(nowS: now, policy: p, queuedMatchingJobs: 14,
                                 runners: runners, slots: slots))
    check res.desired == 16
    check res.busy == 2
    check res.available == 1
    check res.provisioning == 3
    check res.actualCapacity == 6
    # shortage = 16 - 6 = 10, but round cap is 4
    check res.createActions.len == 4
    check res.createActions.mapIt(it.host) ==
      @["ax-ci-v2-r6", "ax-ci-v2-r7", "ax-ci-v2-r8", "ax-ci-v2-r9"]

  test "create count tracks shortage when below the round cap":
    let p = defaultPolicy()
    let now = 1_500i64
    let res = decide(DecideInput(nowS: now, policy: p, queuedMatchingJobs: 2,
                                 runners: @[], slots: @[]))
    check res.desired == 2
    check res.actualCapacity == 0
    check res.createActions.len == 2
    check res.createActions[0].host == "ax-ci-v2-r0"
    check res.createActions[1].host == "ax-ci-v2-r1"

suite "provisioning lease (rev 11)":
  test "lease-less create attempt adds no capacity":
    let p = defaultPolicy()
    let now = 1_500i64
    let res = decide(DecideInput(nowS: now, policy: p, queuedMatchingJobs: 4,
                                 runners: @[], slots: @[]))
    check res.createActions.len == 4          # 4 create attempts issued this round
    check res.provisioning == 0               # no lease booked -> counts nothing
    check res.actualCapacity == 0
    check res.desired == 4

  test "expired lease leaves provisioning, becomes failed/reconcilable, re-provisions next round":
    let p = defaultPolicy()
    let l0 = leased(0, "ax-ci-v2-r0", ssProvisioning, 1000)
    # round 1: lease still inside 600s window (now 1500 <= 1000+600)
    let res1 = decide(DecideInput(nowS: 1500, policy: p, queuedMatchingJobs: 1,
                                  runners: @[], slots: @[l0]))
    check res1.provisioning == 1              # active lease counts as capacity
    check res1.createActions.len == 0         # no shortage yet
    check res1.slots[0].lease.get().state == ssProvisioning

    # round 2: now 1700 > 1000+600 — lease expired
    let res2 = decide(DecideInput(nowS: 1700, policy: p, queuedMatchingJobs: 1,
                                  runners: @[], slots: res1.slots))
    check res2.provisioning == 0              # removed from provisioning
    check res2.slots[0].lease.get().state == ssFailed
    check res2.events.anyIt(it.kind == evLeaseExpired and it.slot == 0)
    check res2.actualCapacity == 0
    check res2.createActions.len == 1
    check res2.createActions[0].slot == 0     # re-provision the failed slot
    check res2.createActions[0].host == "ax-ci-v2-r0"

  test "expired leases never inflate actualCapacity (fake-convergence regression)":
    let p = defaultPolicy()
    let now = 1_000_000i64
    var runners: seq[RunnerObs] = @[]
    var slots: seq[SlotRecord] = @[]
    for i in 0 ..< 12:                        # 12 real registered busy runners
      let host = slotHostName(p, i)
      runners.add(r(host, true))
      slots.add(leased(i, host, ssRegistered, now - 2000))
    for i in 12 ..< 16:                       # 4 dead/expired leases (never became ready)
      let host = slotHostName(p, i)
      slots.add(leased(i, host, ssFailed, now - 4000))
    let res = decide(DecideInput(nowS: now, policy: p, queuedMatchingJobs: 4,
                                 runners: runners, slots: slots))
    # the 4 expired leases must NOT fake actualCapacity up to 16
    check res.actualCapacity == 12
    check res.provisioning == 0
    check res.desired == 16
    check res.createActions.len == 4
    check res.createActions.mapIt(it.host) ==
      @["ax-ci-v2-r12", "ax-ci-v2-r13", "ax-ci-v2-r14", "ax-ci-v2-r15"]

suite "scale-down":
  test "no deletes for busy hosts; no deletes below grace windows":
    let p = defaultPolicy()
    let now = 1_000_000i64
    var runners = @[r("ax-ci-v2-r0", true),   # busy now, but bookkeeping idle >= grace
                    r("ax-ci-v2-r1", false),  # idle but below 300s grace
                    r("ax-ci-v2-r2", false)]  # idle >= 300s grace
    var slots: seq[SlotRecord] = @[]
    slots.add(leased(0, "ax-ci-v2-r0", ssRegistered, now - 2000, 0, now - 400))
    slots.add(leased(1, "ax-ci-v2-r1", ssRegistered, now - 2000, 0, now - 100))
    slots.add(leased(2, "ax-ci-v2-r2", ssRegistered, now - 2000, 0, now - 400))
    slots.add(leased(3, "ax-ci-v2-r3", ssRegistered, now - 2000, now - 50, 0))
    slots.add(leased(4, "ax-ci-v2-r4", ssRegistered, now - 2000, now - 200, 0))
    let res = decide(DecideInput(nowS: now, policy: p, queuedMatchingJobs: 0,
                                 runners: runners, slots: slots))
    let deleted = res.deleteActions.mapIt(it.host)
    check deleted.contains("ax-ci-v2-r0") == false   # busy — never deleted
    check deleted.contains("ax-ci-v2-r1") == false   # idle below grace
    check deleted.contains("ax-ci-v2-r3") == false   # absent below grace
    check deleted == @["ax-ci-v2-r4", "ax-ci-v2-r2"] # absent(120s) first, then idle(300s)
    check res.deleteActions[0].recheckBusy == false  # deregistered: race-free
    check res.deleteActions[1].recheckBusy == true   # idle-registered: recheck before delete
    check res.guardViolationCount == 1               # busy recheck on r0 blocked
    check res.events.anyIt(it.kind == evBusyDeleteBlocked and it.host == "ax-ci-v2-r0")

suite "determinism":
  test "identical input twice -> identical output":
    let p = defaultPolicy()
    let now = 1_000_000i64
    var runners = @[r("ax-ci-v2-r0", true), r("ax-ci-v2-r1", false),
                    r("ax-ci-v2-r2", true)]
    var slots: seq[SlotRecord] = @[]
    slots.add(leased(0, "ax-ci-v2-r0", ssRegistered, now - 2000))
    slots.add(leased(1, "ax-ci-v2-r1", ssRegistered, now - 2000))
    slots.add(leased(2, "ax-ci-v2-r2", ssRegistered, now - 4000))
    for i in 3 ..< 5:
      slots.add(leased(i, slotHostName(p, i), ssProvisioning, now - 700))
    slots.add(leased(5, "ax-ci-v2-r5", ssFailed, now - 4000))
    let inp = DecideInput(nowS: now, policy: p, queuedMatchingJobs: 4,
                          runners: runners, slots: slots)
    let a = decide(inp)
    let b = decide(inp)
    check a == b

suite "failure backoff":
  test "creation is held during backoff, resumes after":
    let p = defaultPolicy()
    let now = 1_000_000i64
    let inp = DecideInput(nowS: now, policy: p, queuedMatchingJobs: 4,
                          runners: @[], slots: @[],
                          backoffUntilS: now + 300, backoffAttempts: 2)
    let held = decide(inp)
    check held.createActions.len == 0
    check held.events.anyIt(it.kind == evBackoffHold)
    check held.backoffUntilS == now + 300      # preserved while active
    check held.backoffAttempts == 2

    let resumed = DecideInput(nowS: now + 301, policy: p, queuedMatchingJobs: 4,
                              runners: @[], slots: @[],
                              backoffUntilS: now + 300, backoffAttempts: 2)
    let res = decide(resumed)
    check res.createActions.len == 4
    check res.events.anyIt(it.kind == evBackoffHold) == false
    check res.backoffUntilS == 0               # backoff cleared
    check res.backoffAttempts == 0
