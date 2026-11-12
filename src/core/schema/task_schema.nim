import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## task_schema.nim — Centralized task domain types for the Control Engine.
##
## Schema-as-Code: types + compile-time validation + serialization.
## Pure data definitions. No business logic. No I/O.
##
## Architecture: Schema module in src/core/schema/.
## Imports: std/* and core/types/results only (SOC-leaf compliant).

import std/[json, tables, hashes]
import core/types/results

# ---------------------------------------------------------------------------
# Distinct Types
# ---------------------------------------------------------------------------

type
  TaskId* = distinct string
    ## Opaque task identifier. Distinct type prevents accidental string mixing.

func `==`*(a, b: TaskId): bool {.inline.} =
  string(a) == string(b)

func `$`*(a: TaskId): string {.inline.} =
  string(a)

func toTaskId*(s: string): TaskId {.inline.} =
  ## Construct a TaskId from a raw string.
  TaskId(s)

func initTaskId*(s: string): TaskId {.inline.} =
  ## Canonical constructor for TaskId.
  TaskId(s)

func isEmpty*(id: TaskId): bool {.inline.} =
  ## True when the TaskId carries no content.
  string(id).len == 0

func `<`*(a, b: TaskId): bool {.inline.} =
  ## Lexicographic ordering for TaskId.
  string(a) < string(b)

func hash*(id: TaskId): Hash {.gcsafe.} =
  ## Hash operator for TaskId — enables use as Table key.
  hash(string(id))

# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------

type
  TaskState* = enum
    tsPending    ## Not yet started.
    tsRunning    ## Actively being processed.
    tsCompleted  ## Successfully finished.
    tsFailed     ## Terminated with an error.
    tsBlocked    ## Waiting on external dependency.
    tsSkipped    ## Skipped (dependency failed or user-cancelled).

  ResourceClass* = enum
    rcDefault     ## Standard resource allocation.
    rcPrivileged  ## Elevated resource allocation (e.g., root, GPU).

# ---------------------------------------------------------------------------
# Domain Objects
# ---------------------------------------------------------------------------

type
  TaskSpec* = object
    ## Complete specification of a single task within a DAG.
    id*: TaskId
    title*: string
    description*: string
    state*: TaskState
    deps*: seq[TaskId]          ## Upstream dependencies (must complete first).
    resourceClass*: ResourceClass
    costWeight*: float           ## Relative scheduling cost (>= 0).
    blockedBy*: seq[TaskId]     ## Tasks currently blocking progress.
    metadata*: Table[string, string]  ## Free-form key/value pairs.
    timeoutMinutes*: int        ## Per-task timeout; 0 means no limit.

  DagConfig* = object
    ## Global configuration for a Directed Acyclic Graph of tasks.
    maxConcurrency*: int                 ## Max parallel task slots.
    resourceLimits*: Table[string, int]  ## Resource-class → capacity mapping.
    globalTimeoutMinutes*: int           ## Hard wall-clock limit for entire DAG.

  ShadowTolerance* = object
    ## Controls shadow-mode diffing between two execution paths.
    maxDiffPercent*: float   ## Max allowed divergence before failure (0–100).
    autoPromote*: bool       ## Automatically promote when within tolerance.
    retryBudget*: int        ## Number of retries before hard failure.
    promotionThreshold*: float    ## Min success rate for promotion (0.0-1.0, default 0.95)
    windowSize*: int              ## Sliding window size for success rate (default 100)
    minSuccessRate*: float        ## Minimum sustained success rate (default 0.9)

# ---------------------------------------------------------------------------
# Constructors
# ---------------------------------------------------------------------------

func initTaskSpec*(id: TaskId, title: string, description: string = ""): TaskSpec =
  ## Construct a TaskSpec with defaults for optional fields.
  TaskSpec(
    id: id,
    title: title,
    description: description,
    state: tsPending,
    deps: @[],
    resourceClass: rcDefault,
    costWeight: 1.0,
    blockedBy: @[],
    metadata: initTable[string, string](),
    timeoutMinutes: 0
  )

func defaultDagConfig*(): DagConfig =
  ## Default DAG configuration: 4 concurrent tasks, 30-minute global timeout.
  DagConfig(maxConcurrency: 4, globalTimeoutMinutes: 30)

func defaultShadowTolerance*(): ShadowTolerance =
  ## Default shadow tolerance: 5% max diff, no auto-promote, 3 retries.
  ShadowTolerance(
    maxDiffPercent: 5.0,
    autoPromote: false,
    retryBudget: 3,
    promotionThreshold: 0.95,
    windowSize: 100,
    minSuccessRate: 0.9
  )

# ---------------------------------------------------------------------------
# TaskState Serialization
# ---------------------------------------------------------------------------

func taskStateToStr*(s: TaskState): string {.noSideEffect.} =
  case s
  of tsPending:   "pending"
  of tsRunning:   "running"
  of tsCompleted: "completed"
  of tsFailed:    "failed"
  of tsBlocked:   "blocked"
  of tsSkipped:   "skipped"

func taskStateFromStr*(s: string): Result[TaskState, string] {.noSideEffect.} =
  case s
  of "pending":   ok(tsPending)
  of "running":   ok(tsRunning)
  of "completed": ok(tsCompleted)
  of "failed":    ok(tsFailed)
  of "blocked":   ok(tsBlocked)
  of "skipped":   ok(tsSkipped)
  else: err("Unknown TaskState: " & s)

func `%`*(s: TaskState): JsonNode {.noSideEffect.} =
  %(taskStateToStr(s))

# ---------------------------------------------------------------------------
# ResourceClass Serialization
# ---------------------------------------------------------------------------

func resourceClassToStr*(rc: ResourceClass): string {.noSideEffect.} =
  case rc
  of rcDefault:    "default"
  of rcPrivileged: "privileged"

func resourceClassFromStr*(s: string): Result[ResourceClass, string] {.noSideEffect.} =
  case s
  of "default":    ok(rcDefault)
  of "privileged": ok(rcPrivileged)
  else: err("Unknown ResourceClass: " & s)

func `%`*(rc: ResourceClass): JsonNode {.noSideEffect.} =
  %(resourceClassToStr(rc))

# ---------------------------------------------------------------------------
# TaskId Serialization
# ---------------------------------------------------------------------------

func `%`*(id: TaskId): JsonNode {.noSideEffect.} =
  %(string(id))

func fromJson*(node: JsonNode, _: typedesc[TaskId]): Result[TaskId, string] {.noSideEffect.} =
  if node.kind == JString:
    ok(TaskId(node.getStr()))
  else:
    err("Expected JString for TaskId, got " & $node.kind)

# ---------------------------------------------------------------------------
# TaskSpec Serialization
# ---------------------------------------------------------------------------

func `%`*(spec: TaskSpec): JsonNode {.noSideEffect.} =
  %*{
    "id": spec.id,
    "title": spec.title,
    "description": spec.description,
    "state": spec.state,
    "deps": spec.deps,
    "resourceClass": spec.resourceClass,
    "costWeight": spec.costWeight,
    "blockedBy": spec.blockedBy,
    "metadata": spec.metadata,
    "timeoutMinutes": spec.timeoutMinutes
  }

func fromJson*(node: JsonNode, _: typedesc[TaskState]): Result[TaskState, string] {.noSideEffect.} =
  if node.kind == JString:
    taskStateFromStr(node.getStr())
  else:
    err("Expected JString for TaskState, got " & $node.kind)

func fromJson*(node: JsonNode, _: typedesc[ResourceClass]): Result[ResourceClass, string] {.noSideEffect.} =
  if node.kind == JString:
    resourceClassFromStr(node.getStr())
  else:
    err("Expected JString for ResourceClass, got " & $node.kind)

func fromJson*(node: JsonNode, _: typedesc[TaskSpec]): Result[TaskSpec, string] {.noSideEffect.} =
  ## Deserialize a JsonNode into a TaskSpec.
  ## Required fields: id, title, description, state.
  ## Optional fields use defaults (deps=@[], rcDefault, costWeight=1.0, etc.).
  if node.kind != JObject:
    return err("Expected JObject for TaskSpec, got " & $node.kind)

  # ── Required: id ──
  let idNode = node{"id"}
  if idNode.isNil:
    return err("TaskSpec missing required field: id")
  let idRes = fromJson(idNode, TaskId)
  if idRes.isErr:
    return err("TaskSpec.id: " & idRes.error)

  # ── Required: title ──
  let titleNode = node{"title"}
  if titleNode.isNil or titleNode.kind != JString:
    return err("TaskSpec missing or invalid field: title")

  # ── Required: description ──
  let descNode = node{"description"}
  if descNode.isNil or descNode.kind != JString:
    return err("TaskSpec missing or invalid field: description")

  # ── Required: state ──
  let stateNode = node{"state"}
  if stateNode.isNil:
    return err("TaskSpec missing required field: state")
  let stateRes = fromJson(stateNode, TaskState)
  if stateRes.isErr:
    return err("TaskSpec.state: " & stateRes.error)

  # ── Optional: deps (default: @[]) ──
  var deps: seq[TaskId]
  let depsNode = node{"deps"}
  if not depsNode.isNil:
    if depsNode.kind != JArray:
      return err("TaskSpec.deps must be an array")
    for item in depsNode:
      let dRes = fromJson(item, TaskId)
      if dRes.isErr:
        return err("TaskSpec.deps entry: " & dRes.error)
      deps.add(dRes.get())

  # ── Optional: resourceClass (default: rcDefault) ──
  var rc = rcDefault
  let rcNode = node{"resourceClass"}
  if not rcNode.isNil:
    let rcRes = fromJson(rcNode, ResourceClass)
    if rcRes.isErr:
      return err("TaskSpec.resourceClass: " & rcRes.error)
    rc = rcRes.get()

  # ── Optional: costWeight (default: 1.0) ──
  var cw = 1.0
  let cwNode = node{"costWeight"}
  if not cwNode.isNil:
    case cwNode.kind
    of JFloat: cw = cwNode.getFloat()
    of JInt:   cw = float(cwNode.getInt())
    else:      return err("TaskSpec.costWeight must be a number")

  # ── Optional: blockedBy (default: @[]) ──
  var blocked: seq[TaskId]
  let blockedNode = node{"blockedBy"}
  if not blockedNode.isNil:
    if blockedNode.kind != JArray:
      return err("TaskSpec.blockedBy must be an array")
    for item in blockedNode:
      let bRes = fromJson(item, TaskId)
      if bRes.isErr:
        return err("TaskSpec.blockedBy entry: " & bRes.error)
      blocked.add(bRes.get())

  # ── Optional: metadata (default: empty table) ──
  var meta: Table[string, string]
  let metaNode = node{"metadata"}
  if not metaNode.isNil:
    if metaNode.kind != JObject:
      return err("TaskSpec.metadata must be an object")
    for k, v in metaNode:
      if v.kind != JString:
        return err("TaskSpec.metadata[" & k & "] must be a string")
      meta[k] = v.getStr()

  # ── Optional: timeoutMinutes (default: 0) ──
  var tm = 0
  let tmNode = node{"timeoutMinutes"}
  if not tmNode.isNil:
    if tmNode.kind == JInt:
      tm = tmNode.getInt()
    else:
      return err("TaskSpec.timeoutMinutes must be an integer")

  ok(TaskSpec(
    id: idRes.get(),
    title: titleNode.getStr(),
    description: descNode.getStr(),
    state: stateRes.get(),
    deps: deps,
    resourceClass: rc,
    costWeight: cw,
    blockedBy: blocked,
    metadata: meta,
    timeoutMinutes: tm
  ))

# ---------------------------------------------------------------------------
# DagConfig Serialization
# ---------------------------------------------------------------------------

func `%`*(cfg: DagConfig): JsonNode {.noSideEffect.} =
  %*{
    "maxConcurrency": cfg.maxConcurrency,
    "resourceLimits": cfg.resourceLimits,
    "globalTimeoutMinutes": cfg.globalTimeoutMinutes
  }

func fromJson*(node: JsonNode, _: typedesc[DagConfig]): Result[DagConfig, string] {.noSideEffect.} =
  ## Deserialize a JsonNode into a DagConfig.
  ## Required fields: maxConcurrency, globalTimeoutMinutes.
  ## Optional: resourceLimits (default: empty table).
  if node.kind != JObject:
    return err("Expected JObject for DagConfig, got " & $node.kind)

  # ── Required: maxConcurrency ──
  let mcNode = node{"maxConcurrency"}
  if mcNode.isNil or mcNode.kind != JInt:
    return err("DagConfig missing or invalid field: maxConcurrency")

  # ── Required: globalTimeoutMinutes ──
  let gtNode = node{"globalTimeoutMinutes"}
  if gtNode.isNil or gtNode.kind != JInt:
    return err("DagConfig missing or invalid field: globalTimeoutMinutes")

  # ── Optional: resourceLimits (default: empty table) ──
  var limits: Table[string, int]
  let rlNode = node{"resourceLimits"}
  if not rlNode.isNil:
    if rlNode.kind != JObject:
      return err("DagConfig.resourceLimits must be an object")
    for k, v in rlNode:
      if v.kind != JInt:
        return err("DagConfig.resourceLimits[" & k & "] must be an integer")
      limits[k] = v.getInt()

  ok(DagConfig(
    maxConcurrency: mcNode.getInt(),
    resourceLimits: limits,
    globalTimeoutMinutes: gtNode.getInt()
  ))

# ---------------------------------------------------------------------------
# ShadowTolerance Serialization
# ---------------------------------------------------------------------------

func `%`*(st: ShadowTolerance): JsonNode {.noSideEffect.} =
  %*{
    "maxDiffPercent": st.maxDiffPercent,
    "autoPromote": st.autoPromote,
    "retryBudget": st.retryBudget,
    "promotionThreshold": st.promotionThreshold,
    "windowSize": st.windowSize,
    "minSuccessRate": st.minSuccessRate
  }

func fromJson*(node: JsonNode, _: typedesc[ShadowTolerance]): Result[ShadowTolerance, string] {.noSideEffect.} =
  ## Deserialize a JsonNode into a ShadowTolerance.
  ## Required fields: maxDiffPercent, autoPromote, retryBudget.
  ## Optional fields: promotionThreshold (0.95), windowSize (100), minSuccessRate (0.9).
  if node.kind != JObject:
    return err("Expected JObject for ShadowTolerance, got " & $node.kind)

  # ── Required: maxDiffPercent ──
  let mdpNode = node{"maxDiffPercent"}
  if mdpNode.isNil:
    return err("ShadowTolerance missing required field: maxDiffPercent")
  var mdp: float
  case mdpNode.kind
  of JFloat: mdp = mdpNode.getFloat()
  of JInt:   mdp = float(mdpNode.getInt())
  else:      return err("ShadowTolerance.maxDiffPercent must be a number")

  # ── Required: autoPromote ──
  let apNode = node{"autoPromote"}
  if apNode.isNil or apNode.kind != JBool:
    return err("ShadowTolerance missing or invalid field: autoPromote")

  # ── Required: retryBudget ──
  let rbNode = node{"retryBudget"}
  if rbNode.isNil or rbNode.kind != JInt:
    return err("ShadowTolerance missing or invalid field: retryBudget")

  # ── Optional: promotionThreshold (default 0.95) ──
  var pt = 0.95
  let ptNode = node{"promotionThreshold"}
  if not ptNode.isNil:
    case ptNode.kind
    of JFloat: pt = ptNode.getFloat()
    of JInt:   pt = float(ptNode.getInt())
    else:      return err("ShadowTolerance.promotionThreshold must be a number")

  # ── Optional: windowSize (default 100) ──
  var ws = 100
  let wsNode = node{"windowSize"}
  if not wsNode.isNil:
    if wsNode.kind == JInt:
      ws = wsNode.getInt()
    else:
      return err("ShadowTolerance.windowSize must be an integer")

  # ── Optional: minSuccessRate (default 0.9) ──
  var msr = 0.9
  let msrNode = node{"minSuccessRate"}
  if not msrNode.isNil:
    case msrNode.kind
    of JFloat: msr = msrNode.getFloat()
    of JInt:   msr = float(msrNode.getInt())
    else:      return err("ShadowTolerance.minSuccessRate must be a number")

  ok(ShadowTolerance(
    maxDiffPercent: mdp,
    autoPromote: apNode.getBool(),
    retryBudget: rbNode.getInt(),
    promotionThreshold: pt,
    windowSize: ws,
    minSuccessRate: msr
  ))

# ---------------------------------------------------------------------------
# Named toJson Aliases
# ---------------------------------------------------------------------------

func toJson*(id: TaskId): JsonNode {.noSideEffect.} =
  ## Serialize a TaskId to JSON.
  %(id)

func toJson*(state: TaskState): JsonNode {.noSideEffect.} =
  ## Serialize a TaskState to JSON.
  %(state)

func toJson*(rc: ResourceClass): JsonNode {.noSideEffect.} =
  ## Serialize a ResourceClass to JSON.
  %(rc)

func toJson*(spec: TaskSpec): JsonNode {.noSideEffect.} =
  ## Serialize a TaskSpec to JSON.
  %(spec)

func toJson*(cfg: DagConfig): JsonNode {.noSideEffect.} =
  ## Serialize a DagConfig to JSON.
  %(cfg)

func toJson*(st: ShadowTolerance): JsonNode {.noSideEffect.} =
  ## Serialize a ShadowTolerance to JSON.
  %(st)

# ---------------------------------------------------------------------------
# Named fromJson Aliases
# ---------------------------------------------------------------------------

func taskSpecFromJson*(node: JsonNode): Result[TaskSpec, string] {.noSideEffect.} =
  ## Deserialize a JsonNode into a TaskSpec (named alias).
  fromJson(node, TaskSpec)

func dagConfigFromJson*(node: JsonNode): Result[DagConfig, string] {.noSideEffect.} =
  ## Deserialize a JsonNode into a DagConfig (named alias).
  fromJson(node, DagConfig)

func shadowToleranceFromJson*(node: JsonNode): Result[ShadowTolerance, string] {.noSideEffect.} =
  ## Deserialize a JsonNode into a ShadowTolerance (named alias).
  fromJson(node, ShadowTolerance)

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

func validateTaskSpec*(spec: TaskSpec): seq[string] {.noSideEffect.} =
  ## Validate a TaskSpec invariants. Returns a seq of error strings.
  ## Empty seq means the spec is valid.
  result = @[]

  if spec.id.isEmpty:
    result.add("TaskSpec.id must not be empty")

  if spec.title.len == 0:
    result.add("TaskSpec.title must not be empty")

  if spec.description.len == 0:
    result.add("TaskSpec.description must not be empty")

  if spec.costWeight <= 0.0:
    result.add("TaskSpec.costWeight must be positive")

  if spec.timeoutMinutes <= 0:
    result.add("TaskSpec.timeoutMinutes must be positive")

  # Self-dependency check
  for dep in spec.deps:
    if dep == spec.id:
      result.add("TaskSpec must not depend on itself (self-dependency on " & $dep & ")")
      break

{.pop.}
