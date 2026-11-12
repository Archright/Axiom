## task_schema_test.nim — Tests for core/schema/task_schema.
##
## Run: nim c -r tests/schema/task_schema_test.nim

import std/[unittest, json, tables, strutils]
import core/schema/task_schema
import core/types/results

# ─────────────────────────────────────────────────────────────────────────────
# TaskId
# ─────────────────────────────────────────────────────────────────────────────

suite "TaskId":
  test "toTaskId wraps string":
    let id = toTaskId("task-001")
    check $id == "task-001"
    check string(id) == "task-001"

  test "initTaskId wraps string":
    let id = initTaskId("task-002")
    check $id == "task-002"
    check string(id) == "task-002"

  test "equality is structural":
    check toTaskId("a") == toTaskId("a")
    check toTaskId("a") != toTaskId("b")

  test "isEmpty detects blank ids":
    check toTaskId("").isEmpty
    check not toTaskId("x").isEmpty

  test "< operator is lexicographic":
    check toTaskId("a") < toTaskId("b")
    check not (toTaskId("b") < toTaskId("a"))
    check not (toTaskId("a") < toTaskId("a"))

# ─────────────────────────────────────────────────────────────────────────────
# TaskState
# ─────────────────────────────────────────────────────────────────────────────

suite "TaskState serialization":
  test "all states round-trip":
    let states = [tsPending, tsRunning, tsCompleted, tsFailed, tsBlocked]
    for s in states:
      let str = taskStateToStr(s)
      let back = taskStateFromStr(str)
      check back.isOk
      check back.get() == s

  test "invalid string returns error":
    check taskStateFromStr("bogus").isErr

  test "json conversion produces JString":
    let node = %tsRunning
    check node.kind == JString
    check node.getStr() == "running"

# ─────────────────────────────────────────────────────────────────────────────
# ResourceClass
# ─────────────────────────────────────────────────────────────────────────────

suite "ResourceClass serialization":
  test "all values round-trip":
    let classes = [rcDefault, rcPrivileged]
    for rc in classes:
      let str = resourceClassToStr(rc)
      let back = resourceClassFromStr(str)
      check back.isOk
      check back.get() == rc

  test "invalid string returns error":
    check resourceClassFromStr("unknown").isErr

  test "json conversion produces JString":
    let node = %rcPrivileged
    check node.kind == JString
    check node.getStr() == "privileged"

# ─────────────────────────────────────────────────────────────────────────────
# initTaskSpec / default factories
# ─────────────────────────────────────────────────────────────────────────────

suite "initTaskSpec and defaults":
  test "initTaskSpec creates spec with defaults":
    let spec = initTaskSpec(initTaskId("t1"), "My Task", "A description")
    check spec.id == initTaskId("t1")
    check spec.title == "My Task"
    check spec.description == "A description"
    check spec.state == tsPending
    check spec.deps.len == 0
    check spec.resourceClass == rcDefault
    check spec.costWeight == 1.0
    check spec.blockedBy.len == 0
    check spec.metadata.len == 0
    check spec.timeoutMinutes == 0

  test "initTaskSpec with empty description":
    let spec = initTaskSpec(initTaskId("t2"), "Title Only")
    check spec.description == ""

  test "defaultDagConfig has expected values":
    let cfg = defaultDagConfig()
    check cfg.maxConcurrency == 4
    check cfg.globalTimeoutMinutes == 30
    check cfg.resourceLimits.len == 0

  test "defaultShadowTolerance has expected values":
    let st = defaultShadowTolerance()
    check st.maxDiffPercent == 5.0
    check st.autoPromote == false
    check st.retryBudget == 3

# ─────────────────────────────────────────────────────────────────────────────
# TaskSpec JSON round-trip
# ─────────────────────────────────────────────────────────────────────────────

suite "TaskSpec JSON round-trip":
  test "minimal spec (required fields only)":
    let spec = TaskSpec(
      id: toTaskId("t1"),
      title: "Test Task",
      description: "A test task",
      state: tsPending
    )
    let node = %spec
    let restored = fromJson(node, TaskSpec)
    check restored.isOk
    let r = restored.get()
    check r.id == toTaskId("t1")
    check r.title == "Test Task"
    check r.description == "A test task"
    check r.state == tsPending
    # Defaults
    check r.deps.len == 0
    check r.resourceClass == rcDefault
    check r.costWeight == 0.0  # Nim float default; fromJson default 1.0 only applies when key is absent
    check r.blockedBy.len == 0
    check r.metadata.len == 0
    check r.timeoutMinutes == 0

  test "full spec with all fields":
    var meta = initTable[string, string]()
    meta["env"] = "production"
    meta["region"] = "us-east-1"
    let spec = TaskSpec(
      id: toTaskId("t2"),
      title: "Deploy Service",
      description: "Rolling deploy",
      state: tsRunning,
      deps: @[toTaskId("t0"), toTaskId("t1")],
      resourceClass: rcPrivileged,
      costWeight: 2.5,
      blockedBy: @[toTaskId("t-block")],
      metadata: meta,
      timeoutMinutes: 30
    )
    let node = %spec
    let restored = fromJson(node, TaskSpec)
    check restored.isOk
    let r = restored.get()
    check r.id == toTaskId("t2")
    check r.state == tsRunning
    check r.deps.len == 2
    check r.deps[0] == toTaskId("t0")
    check r.deps[1] == toTaskId("t1")
    check r.resourceClass == rcPrivileged
    check r.costWeight == 2.5
    check r.blockedBy.len == 1
    check r.blockedBy[0] == toTaskId("t-block")
    check r.metadata["env"] == "production"
    check r.metadata["region"] == "us-east-1"
    check r.timeoutMinutes == 30

  test "json shape has expected keys":
    let spec = TaskSpec(
      id: toTaskId("t3"),
      title: "Shape Check",
      description: "Verify JSON keys",
      state: tsCompleted
    )
    let node = %spec
    check node.kind == JObject
    check node.hasKey("id")
    check node.hasKey("title")
    check node.hasKey("description")
    check node.hasKey("state")
    check node.hasKey("deps")
    check node.hasKey("resourceClass")
    check node.hasKey("costWeight")
    check node.hasKey("blockedBy")
    check node.hasKey("metadata")
    check node.hasKey("timeoutMinutes")

  test "fromJson rejects non-object":
    check fromJson(%"just a string", TaskSpec).isErr
    check fromJson(%123, TaskSpec).isErr

  test "fromJson rejects missing id":
    let node = %*{
      "title": "T",
      "description": "D",
      "state": "pending"
    }
    check fromJson(node, TaskSpec).isErr

  test "fromJson rejects invalid state":
    let node = %*{
      "id": "t1",
      "title": "T",
      "description": "D",
      "state": "not_a_state"
    }
    check fromJson(node, TaskSpec).isErr

  test "taskSpecFromJson round-trip":
    let spec = initTaskSpec(initTaskId("t-named"), "Named", "Named alias test")
    let node = toJson(spec)
    let restored = taskSpecFromJson(node)
    check restored.isOk
    check restored.get().id == initTaskId("t-named")
    check restored.get().title == "Named"

# ─────────────────────────────────────────────────────────────────────────────
# DagConfig JSON round-trip
# ─────────────────────────────────────────────────────────────────────────────

suite "DagConfig JSON round-trip":
  test "minimal config (no resourceLimits)":
    let cfg = DagConfig(
      maxConcurrency: 4,
      globalTimeoutMinutes: 120
    )
    let node = %cfg
    let restored = fromJson(node, DagConfig)
    check restored.isOk
    let r = restored.get()
    check r.maxConcurrency == 4
    check r.globalTimeoutMinutes == 120
    check r.resourceLimits.len == 0

  test "full config with resourceLimits":
    var limits = initTable[string, int]()
    limits["cpu"] = 8
    limits["memory"] = 16384
    limits["gpu"] = 2
    let cfg = DagConfig(
      maxConcurrency: 16,
      resourceLimits: limits,
      globalTimeoutMinutes: 60
    )
    let node = %cfg
    let restored = fromJson(node, DagConfig)
    check restored.isOk
    let r = restored.get()
    check r.maxConcurrency == 16
    check r.resourceLimits["cpu"] == 8
    check r.resourceLimits["memory"] == 16384
    check r.resourceLimits["gpu"] == 2
    check r.globalTimeoutMinutes == 60

  test "fromJson rejects non-object":
    check fromJson(%42, DagConfig).isErr

  test "fromJson rejects missing maxConcurrency":
    let node = %*{"globalTimeoutMinutes": 30}
    check fromJson(node, DagConfig).isErr

  test "fromJson rejects missing globalTimeoutMinutes":
    let node = %*{"maxConcurrency": 4}
    check fromJson(node, DagConfig).isErr

  test "dagConfigFromJson round-trip":
    let cfg = defaultDagConfig()
    let node = toJson(cfg)
    let restored = dagConfigFromJson(node)
    check restored.isOk
    check restored.get().maxConcurrency == 4

# ─────────────────────────────────────────────────────────────────────────────
# ShadowTolerance JSON round-trip
# ─────────────────────────────────────────────────────────────────────────────

suite "ShadowTolerance JSON round-trip":
  test "round-trip all fields":
    let st = ShadowTolerance(
      maxDiffPercent: 5.0,
      autoPromote: true,
      retryBudget: 3
    )
    let node = %st
    let restored = fromJson(node, ShadowTolerance)
    check restored.isOk
    let r = restored.get()
    check r.maxDiffPercent == 5.0
    check r.autoPromote == true
    check r.retryBudget == 3

  test "autoPromote false":
    let st = ShadowTolerance(
      maxDiffPercent: 0.0,
      autoPromote: false,
      retryBudget: 0
    )
    let node = %st
    let restored = fromJson(node, ShadowTolerance)
    check restored.isOk
    check restored.get().autoPromote == false

  test "fromJson rejects non-object":
    check fromJson(%true, ShadowTolerance).isErr

  test "fromJson rejects missing maxDiffPercent":
    let node = %*{"autoPromote": true, "retryBudget": 3}
    check fromJson(node, ShadowTolerance).isErr

  test "fromJson rejects missing autoPromote":
    let node = %*{"maxDiffPercent": 5.0, "retryBudget": 3}
    check fromJson(node, ShadowTolerance).isErr

  test "fromJson rejects missing retryBudget":
    let node = %*{"maxDiffPercent": 5.0, "autoPromote": true}
    check fromJson(node, ShadowTolerance).isErr

  test "shadowToleranceFromJson round-trip":
    let st = defaultShadowTolerance()
    let node = toJson(st)
    let restored = shadowToleranceFromJson(node)
    check restored.isOk
    check restored.get().retryBudget == 3

# ─────────────────────────────────────────────────────────────────────────────
# validateTaskSpec
# ─────────────────────────────────────────────────────────────────────────────

suite "validateTaskSpec":
  test "valid spec returns empty seq":
    let spec = TaskSpec(
      id: toTaskId("t1"),
      title: "Valid Task",
      description: "All fields present",
      state: tsPending,
      costWeight: 1.0,
      timeoutMinutes: 10
    )
    check validateTaskSpec(spec).len == 0

  test "empty id is invalid":
    let spec = TaskSpec(
      id: toTaskId(""),
      title: "T",
      description: "D",
      state: tsPending
    )
    let errors = validateTaskSpec(spec)
    check errors.len > 0
    check "id" in errors[0]

  test "empty title is invalid":
    let spec = TaskSpec(
      id: toTaskId("t1"),
      title: "",
      description: "D",
      state: tsPending
    )
    let errors = validateTaskSpec(spec)
    check errors.len > 0
    check "title" in errors[0]

  test "empty description is invalid":
    let spec = TaskSpec(
      id: toTaskId("t1"),
      title: "T",
      description: "",
      state: tsPending
    )
    let errors = validateTaskSpec(spec)
    check errors.len > 0
    check "description" in errors[0]

  test "negative costWeight is invalid":
    let spec = TaskSpec(
      id: toTaskId("t1"),
      title: "T",
      description: "D",
      state: tsPending,
      costWeight: -1.0
    )
    let errors = validateTaskSpec(spec)
    check errors.len > 0
    check "costWeight" in errors[0]

  test "zero costWeight is invalid":
    let spec = TaskSpec(
      id: toTaskId("t1"),
      title: "T",
      description: "D",
      state: tsPending,
      costWeight: 0.0
    )
    let errors = validateTaskSpec(spec)
    check errors.len > 0
    check "costWeight" in errors[0]

  test "negative timeoutMinutes is invalid":
    let spec = TaskSpec(
      id: toTaskId("t1"),
      title: "T",
      description: "D",
      state: tsPending,
      costWeight: 1.0,
      timeoutMinutes: -5
    )
    let errors = validateTaskSpec(spec)
    check errors.len > 0
    check "timeoutMinutes" in errors[0]

  test "zero timeoutMinutes is invalid":
    let spec = TaskSpec(
      id: toTaskId("t1"),
      title: "T",
      description: "D",
      state: tsPending,
      costWeight: 1.0,
      timeoutMinutes: 0
    )
    let errors = validateTaskSpec(spec)
    check errors.len > 0
    check "timeoutMinutes" in errors[0]

  test "self-dependency is invalid":
    let spec = TaskSpec(
      id: toTaskId("t1"),
      title: "T",
      description: "D",
      state: tsPending,
      deps: @[toTaskId("t2"), toTaskId("t1")],
      costWeight: 1.0,
      timeoutMinutes: 10
    )
    let errors = validateTaskSpec(spec)
    check errors.len > 0
    check "depend" in errors[0]

  test "multiple errors collected":
    let spec = TaskSpec(
      id: toTaskId(""),
      title: "",
      description: "",
      state: tsPending,
      costWeight: -1.0,
      timeoutMinutes: -1,
      deps: @[toTaskId("")]
    )
    let errors = validateTaskSpec(spec)
    # At minimum: id, title, description, costWeight, timeoutMinutes
    check errors.len >= 5

  test "valid spec with deps and metadata passes":
    var meta = initTable[string, string]()
    meta["key"] = "val"
    let spec = TaskSpec(
      id: toTaskId("t1"),
      title: "Task",
      description: "Desc",
      state: tsPending,
      deps: @[toTaskId("t0")],
      resourceClass: rcPrivileged,
      costWeight: 0.5,
      metadata: meta,
      timeoutMinutes: 10
    )
    check validateTaskSpec(spec).len == 0
