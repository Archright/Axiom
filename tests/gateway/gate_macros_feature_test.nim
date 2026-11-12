{.push raises: [CatchableError].}
## BDD feature test for gate_macros.feature
## Verifies GateRunContext lifecycle, AuditEntry creation/finalization,
## and ARC ownership tracking.

import std/unittest
import std/times
import gate/utils/gate_macros

suite "GateRunContext — construction":

  test "initGateRunContext sets projectRoot correctly":
    let ctx = initGateRunContext("/my/project", VfsHandle(nil))
    check ctx.projectRoot == "/my/project"

  test "initGateRunContext initializes empty audit log":
    let ctx = initGateRunContext("/tmp", VfsHandle(nil))
    check ctx.auditLog.len == 0

  test "initGateRunContext initializes empty context paths":
    let ctx = initGateRunContext("/tmp", VfsHandle(nil))
    check ctx.contextPaths.len == 0

  test "initGateRunContext sets epoch":
    let ctx = initGateRunContext("/tmp", VfsHandle(nil), epoch = 42)
    check ctx.epoch == 42

  test "initGateRunContext sets maxJobs":
    let ctx = initGateRunContext("/tmp", VfsHandle(nil), maxJobs = 8)
    check ctx.maxJobs == 8

  test "initGateRunContext sets owner defaults":
    let ctx = initGateRunContext("/tmp", VfsHandle(nil))
    check ctx.owner.vfsRefCount == 1
    check ctx.owner.isShared == false
    check ctx.owner.version == 0

suite "GateRunContext — clone (structural sharing)":

  test "clone increments vfsRefCount":
    var ctx = initGateRunContext("/tmp", VfsHandle(nil))
    var cloned = clone(ctx)
    check cloned.owner.vfsRefCount == 2

  test "clone marks as shared":
    var ctx = initGateRunContext("/tmp", VfsHandle(nil))
    var cloned = clone(ctx)
    check cloned.owner.isShared == true

  test "clone preserves projectRoot":
    var ctx = initGateRunContext("/project", VfsHandle(nil))
    var cloned = clone(ctx)
    check cloned.projectRoot == "/project"

  test "clone preserves epoch":
    var ctx = initGateRunContext("/tmp", VfsHandle(nil), epoch = 7)
    var cloned = clone(ctx)
    check cloned.epoch == 7

  test "double clone increments refcount correctly":
    var ctx = initGateRunContext("/tmp", VfsHandle(nil))
    var c1 = clone(ctx)
    var c2 = clone(c1)
    check c2.owner.vfsRefCount == 3
    check c2.owner.isShared == true

suite "GateRunContext — addAuditEntry":

  test "addAuditEntry appends to log":
    var ctx = initGateRunContext("/tmp", VfsHandle(nil))
    let entry = AuditEntry(
      gateId: "test-gate",
      startTime: getTime(),
      endTime: getTime(),
      exitCode: 0,
      output: "ok",
      sandboxed: false,
      cacheHit: false,
      epoch: 1
    )
    ctx.addAuditEntry(entry)
    check ctx.auditLog.len == 1
    check ctx.auditLog[0].gateId == "test-gate"

  test "multiple addAuditEntry calls accumulate":
    var ctx = initGateRunContext("/tmp", VfsHandle(nil))
    for i in 0..2:
      ctx.addAuditEntry(AuditEntry(gateId: "gate-" & $i))
    check ctx.auditLog.len == 3

suite "AuditEntry — creation and finalization":

  test "initAuditEntry sets gateId and exitCode to -1":
    let entry = initAuditEntry("my-gate")
    check entry.gateId == "my-gate"
    check entry.exitCode == -1
    check entry.output == ""
    check entry.sandboxed == false
    check entry.cacheHit == false

  test "finalize sets exitCode and output":
    var entry = initAuditEntry("my-gate")
    finalize(entry, exitCode = 0, output = "passed")
    check entry.exitCode == 0
    check entry.output == "passed"
    check entry.endTime > entry.startTime

  test "finalize sets sandboxed flag":
    var entry = initAuditEntry("sandbox-gate")
    finalize(entry, exitCode = 0, output = "", sandboxed = true)
    check entry.sandboxed == true

  test "finalize sets cacheHit flag":
    var entry = initAuditEntry("cached-gate")
    finalize(entry, exitCode = 0, output = "", cacheHit = true)
    check entry.cacheHit == true

  test "finalize with non-zero exitCode":
    var entry = initAuditEntry("failing-gate")
    finalize(entry, exitCode = 1, output = "error occurred")
    check entry.exitCode == 1
    check entry.output == "error occurred"

suite "GateRunOwner — defaults":

  test "GateRunOwner zero-init has expected defaults":
    var owner: GateRunOwner
    check owner.vfsRefCount == 0
    check owner.isShared == false
    check owner.version == 0

  test "GateRunOwner tracks version":
    var owner = GateRunOwner(vfsRefCount: 1, isShared: false, version: 42)
    check owner.version == 42

{.pop.}
