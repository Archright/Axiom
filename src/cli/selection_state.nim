import core/trusted/layer_declaration
axiomLayer "presentation"
{.push raises: [CatchableError].}
# axiomIoBoundary

## Deterministic Ranking-Based Node Selection State.
##
## Persists per-node selection counts and ASI history across `ax prove` runs.
## Enables score-ranked selection: Score(s) = 1 / (Count(s) + 1).
## Nodes selected fewer times get higher priority, guaranteeing diversity.
##
## Storage: JSON by default, with backend abstraction for future binary/SQLite.

import std/algorithm
import std/json
import std/options
import std/os
import std/tables
import std/times

import core/trusted/stdlib_shield  # safeMoveFile: Exception isolation for stdlib moveFile quirk
import core/axiom_pragmas
import core/types/asi_types

proc stateJoin(parts: varargs[string]): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## AXIOM_STATE_DIR 설정 시 <state>/<parts...>, 미설정 시 기존 CWD 상대 경로 그대로(zero-diff).
  let base = block:
    let v = getEnv("AXIOM_STATE_DIR")
    if v.len > 0: v else: getCurrentDir()
  result = base
  for p in parts: result = joinPath(result, p)

const
  StateFilename* = "node_selection_state.json"
  DefaultAsiHistoryMax* = 20
  StallDeltaThreshold* = 0.0001

type
  SelectionStoreBackend* = enum
    ssbJson        ## Current: .axiom/cache/node_selection_state.json
    ssbBinary      ## Future: fixed-size binary KV (nodeIdHash:u64 → count:u16)
    ssbSqlite      ## Future: .axiom/cache/selection.db for >50K nodes

  SelectionStore* = object
    backend*: SelectionStoreBackend
    path*: string

  NodeSelectionState* = object
    counts*: Table[string, int]       ## nodeId → selection count
    asiHistory*: seq[ASIRatio]        ## ASI values from recent runs
    lastRunTimestamp*: string         ## ISO timestamp
    stallCount*: int                  ## Consecutive stall rounds (Phase 3: deterministic relaxation)

# ─── Pure Computation (func / {.raises: [].}) ─────────────────────────────

func computeScore*(count: int): float =
  ## Score function: higher score = higher priority (less-selected nodes).
  ## Score(s) = 1 / (Count(s) + 1)
  ##   Count=0 → 1.0, Count=1 → 0.5, Count=5 → 0.167
  1.0 / (count.float + 1.0)

func incrementCount*(state: var NodeSelectionState; nodeIds: seq[string]) =
  ## Bump selection count for each node in the list.
  for nodeId in nodeIds:
    state.counts[nodeId] = state.counts.getOrDefault(nodeId, 0) + 1

func recordAsi*(
  state: var NodeSelectionState;
  asi: ASIRatio;
  maxHistory: int = DefaultAsiHistoryMax
) =
  ## Append ASI value to history, keeping only the last `maxHistory` entries.
  state.asiHistory.add(asi)
  if state.asiHistory.len > maxHistory:
    state.asiHistory = state.asiHistory[state.asiHistory.len - maxHistory .. ^1]

func isStalled*(state: NodeSelectionState; threshold: int = 3): bool =
  ## True if the last `threshold` ASI values are identical (delta < 0.0001).
  if state.asiHistory.len < threshold:
    return false
  let recent = state.asiHistory[state.asiHistory.len - threshold .. ^1]
  let baseline = recent[0]
  for i in 1 ..< recent.len:
    if abs(recent[i].toFloat - baseline.toFloat) > StallDeltaThreshold:
      return false
  true

# ─── Deterministic Threshold Relaxation (Phase 3) ────────────────────────

func computeRelaxedThreshold*(stallCount: int): float =
  ## Gradual threshold relaxation based on stall duration.
  ## stallCount=0 → 0.50 (default), increasing toward 1.00.
  ## This replaces the old all-or-nothing stall bypass budget.
  const stages = [
    (count: 0, threshold: 0.50),
    (count: 1, threshold: 0.65),
    (count: 2, threshold: 0.80),
    (count: 3, threshold: 1.00),
  ]
  for stage in stages:
    if stallCount <= stage.count:
      return stage.threshold
  stages[^1].threshold

func emptyState*(): NodeSelectionState =
  ## Create an empty initial state.
  NodeSelectionState(
    counts: initTable[string, int](),
    asiHistory: @[],
    lastRunTimestamp: "",
    stallCount: 0
  )

# ─── JSON Serialization (pure, no I/O) ────────────────────────────────────

func stateToJson*(state: NodeSelectionState): JsonNode =
  ## Serialize state to JSON node (deterministic key ordering).
  var countsJson = newJObject()
  # Sort keys for deterministic output
  var keys: seq[string] = @[]
  for k in state.counts.keys:
    keys.add(k)
  keys.sort()
  for k in keys:
    countsJson[k] = newJInt(state.counts.getOrDefault(k))

  var historyJson = newJArray()
  for v in state.asiHistory:
    historyJson.add(newJFloat(v.toFloat))

  result = %*{
    "version": 1,
    "counts": countsJson,
    "asiHistory": historyJson,
    "lastRunTimestamp": state.lastRunTimestamp,
    "stallCount": state.stallCount
  }

func stateFromJson*(node: JsonNode): NodeSelectionState =
  ## Deserialize state from JSON node. Returns empty state on malformed input.
  result = emptyState()
  if node.kind != JObject:
    return

  # Parse counts
  let countsNode = node.getOrDefault("counts")
  if not countsNode.isNil and countsNode.kind == JObject:
    for k, v in countsNode:
      if v.kind == JInt:
        result.counts[k] = v.getInt()

  # Parse ASI history
  let historyNode = node.getOrDefault("asiHistory")
  if not historyNode.isNil and historyNode.kind == JArray:
    for v in historyNode:
      if v.kind in {JInt, JFloat}:
        let ratioOpt = initAsiRatio(v.getFloat())
        if ratioOpt.isSome:
          result.asiHistory.add(ratioOpt.get)

  # Parse timestamp
  let tsNode = node.getOrDefault("lastRunTimestamp")
  if not tsNode.isNil and tsNode.kind == JString:
    result.lastRunTimestamp = tsNode.getStr("")

  # Parse stall count (Phase 3: deterministic relaxation)
  let stallNode = node.getOrDefault("stallCount")
  if not stallNode.isNil and stallNode.kind == JInt:
    result.stallCount = stallNode.getInt()

# ─── I/O Boundary ─────────────────────────────────────────────────────────

proc loadSelectionState*(cacheDir: string): NodeSelectionState {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Load selection state from cache directory.
  ## Returns empty state if file missing or malformed.
  let statePath = joinPath(cacheDir, StateFilename)
  if not fileExists(statePath):
    return emptyState()
  try:
    let content = readFile(statePath)
    let node = parseJson(content)
    result = stateFromJson(node)
  except CatchableError:
    result = emptyState()

{.push warning[BareExcept]:off.}
proc saveSelectionState*(state: NodeSelectionState; cacheDir: string) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Save selection state using atomic write (temp + fsync + rename).
  let statePath = joinPath(cacheDir, StateFilename)
  let tmpPath = statePath & ".tmp"
  try:
    if not dirExists(cacheDir):
      createDir(cacheDir)
    let jsonNode = stateToJson(state)
    writeFile(tmpPath, jsonNode.pretty())
    safeMoveFile(tmpPath, statePath)
  except CatchableError:
    # Clean up temp file on failure
    if fileExists(tmpPath):
      try:
        removeFile(tmpPath)
      except CatchableError:
        discard  # axiom:best-effort(ioboundary catch)
{.pop.}

proc detectBackend*(cacheDir: string): SelectionStoreBackend {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Auto-detect storage backend from existing files.
  if fileExists(joinPath(cacheDir, "selection.db")):
    ssbSqlite
  elif fileExists(joinPath(cacheDir, "node_selection_state.bin")):
    ssbBinary
  else:
    ssbJson

proc loadCountsFromStore*(store: SelectionStore): Table[string, int] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Load counts via the abstracted backend.
  case store.backend
  of ssbJson:
    if not fileExists(store.path):
      return initTable[string, int]()
    try:
      let content = readFile(store.path)
      let node = parseJson(content)
      let state = stateFromJson(node)
      return state.counts
    except CatchableError:
      return initTable[string, int]()
  of ssbBinary:
    # Future: binary KV loader
    initTable[string, int]()
  of ssbSqlite:
    # Future: SQLite loader
    initTable[string, int]()

proc saveCountsToStore*(
  store: SelectionStore; counts: Table[string, int]
) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  ## Save counts via the abstracted backend.
  case store.backend
  of ssbJson:
    var state = emptyState()
    state.counts = counts
    state.lastRunTimestamp = $now().utc
    saveSelectionState(state, parentDir(store.path))
  of ssbBinary:
    # Future: binary KV writer
    discard
  of ssbSqlite:
    # Future: SQLite writer
    discard

{.pop.}
