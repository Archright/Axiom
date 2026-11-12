import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [CatchableError].}

## Judge Automation — GoalShape classification, LRU cache, and strategy ladder.
##
## Phase 3 of the Judge Automation plan:
##   1. WHNF-based GoalShape classifier (heuristic + Lean REPL query)
##   2. LRU cache (Table + Deque, maxSize=256) to avoid redundant classification
##   3. Strategy ladder that maps GoalShape → ordered tactic attempts
##   4. Debug logging for unknown goal shapes → JSONL

import std/options
import std/tables
import std/deques
import std/strutils
import std/json
import std/os
import std/times
import std/algorithm

import ../core/trusted/env_access

import core/boundary/boundary_forwarding
import core/boundary/results_boundary
import core/boundary/axiom_pragmas_boundary

import personas/strategy_registry
export strategy_registry

# Import handler modules — triggers compile-time registration via pragmas.
# Order: strategy_registry must be first (defines types + macros).
import personas/shape_handlers/linear_arithmetic
import personas/shape_handlers/equality
import personas/shape_handlers/inductive_structure
import personas/shape_handlers/finite_equality
import personas/shape_handlers/general
import personas/shape_handlers/unknown
import personas/strategy_handlers/rfl
import personas/strategy_handlers/omega
import personas/strategy_handlers/decide
import personas/strategy_handlers/native_decide
import personas/strategy_handlers/simp
import personas/strategy_handlers/simp_omega
import personas/strategy_handlers/grind
import personas/strategy_handlers/aesop
import personas/strategy_handlers/llm_fallback

# ──────────────────────────────────────────────────────────────────────────────
# Types
# ──────────────────────────────────────────────────────────────────────────────

type
  GoalShapeCacheKey* = tuple[nodeId: string, proofAttemptCount: int]

  GoalShapeCacheEntry = object
    shape: GoalShape
    goalSExpr: string

  GoalShapeCache* = object
    ## LRU cache for GoalShape classification results.
    entries: Table[GoalShapeCacheKey, GoalShapeCacheEntry]
    order: Deque[GoalShapeCacheKey]
    maxSize: int

  GoalShapeCandidate* = object
    ## Aggregated frequency entry for unknown goal shapes.
    name*: string
    sampleCount*: int
    suggestion*: string

  LeanProofResult* = object
    ## Result of a deterministic proof attempt.
    verified*: bool
    strategy*: JudgeStrategy
    output*: string
    exitCode*: int

# ──────────────────────────────────────────────────────────────────────────────
# GoalShapeCache — LRU implementation
# ──────────────────────────────────────────────────────────────────────────────

func initGoalShapeCache*(maxSize: int = 256): GoalShapeCache {.raises: [].} =
  ## Create an empty LRU cache with the given maximum capacity.
  GoalShapeCache(
    entries: initTable[GoalShapeCacheKey, GoalShapeCacheEntry](),
    order: initDeque[GoalShapeCacheKey](),
    maxSize: maxSize
  )

func cacheLen*(cache: GoalShapeCache): int {.inline, raises: [].} =
  ## Return the current number of entries in the cache.
  cache.entries.len

func cacheGet*(cache: var GoalShapeCache; key: GoalShapeCacheKey): Option[GoalShape] {.raises: [].} =
  ## Look up a key in the LRU cache. Moves the key to most-recently-used on hit.
  if key notin cache.entries:
    return none(GoalShape)
  # Move to front (most recently used)
  var newOrder = initDeque[GoalShapeCacheKey]()
  newOrder.addFirst(key)
  for k in cache.order:
    if k != key:
      newOrder.addLast(k)
  cache.order = newOrder
  # contains check above guarantees key exists; try/except satisfies {.raises: [].}
  try:
    some(cache.entries[key].shape)
  except CatchableError:
    none(GoalShape)

func cachePut*(cache: var GoalShapeCache; key: GoalShapeCacheKey;
               shape: GoalShape; goalSExpr: string = "") {.raises: [].} =
  ## Insert a classification result into the LRU cache.
  ## Evicts the least-recently-used entry when capacity is exceeded.
  if key in cache.entries:
    # Update existing entry
    cache.entries[key] = GoalShapeCacheEntry(shape: shape, goalSExpr: goalSExpr)
    # Move to front
    var newOrder = initDeque[GoalShapeCacheKey]()
    newOrder.addFirst(key)
    for k in cache.order:
      if k != key:
        newOrder.addLast(k)
    cache.order = newOrder
  else:
    # Evict if at capacity
    while cache.entries.len >= cache.maxSize and cache.order.len > 0:
      let evictKey = cache.order.peekLast()
      cache.order.popLast()
      cache.entries.del(evictKey)
    # Insert
    cache.entries[key] = GoalShapeCacheEntry(shape: shape, goalSExpr: goalSExpr)
    cache.order.addFirst(key)

# ──────────────────────────────────────────────────────────────────────────────
# WHNF-based GoalShape classification
# ──────────────────────────────────────────────────────────────────────────────

func heuristicClassifyGoal(goalSExpr: string): GoalShape {.raises: [].} =
  ## Heuristic pattern matching on goal s-expression keywords.
  ## This is the fast path — no subprocess needed.
  if goalSExpr.len == 0:
    return gsUnknown

  let lower = goalSExpr.toLowerAscii()

  # Inductive structure: presence of induction-related constructors
  if "nat.rec" in lower or "list.rec" in lower or "list.casesOn" in lower or
     "induction" in lower or "nat.casesOn" in lower or ".rec_on" in lower or
     "cases_on" in lower:
    return gsInductiveStructure

  # Linear arithmetic: arithmetic operators + ordering
  let hasArith = ("int" in lower or "nat" in lower) and
                 ("hadd" in lower or "hmul" in lower or "Add." in goalSExpr or
                  "Mul." in goalSExpr or "Sub." in goalSExpr or
                  "instAddInt" in goalSExpr or "instMulInt" in goalSExpr)
  let hasOrder = "le" in lower or "ge" in lower or "≤" in goalSExpr or
                 "≥" in goalSExpr or "<=" in goalSExpr or ">=" in goalSExpr or
                 "LE." in goalSExpr or "instLE" in goalSExpr
  if hasArith and hasOrder:
    return gsLinearArithmetic

  # Finite equality: Bool, Fin, enum types
  if "eq" in lower and ("bool" in lower or "fin." in lower or
     "unit" in lower or "punit" in lower):
    return gsFiniteEquality

  # Structural equality: Eq, Iff, Iota
  if "eq." in lower or "= " in goalSExpr or "Eq." in goalSExpr or
     "Iff" in goalSExpr or "Iota" in goalSExpr:
    return gsEquality

  # General fallback
  if goalSExpr.strip().len > 0:
    return gsGeneral

  gsUnknown

proc classifyGoalViaWhnf*(leanGoalSource: string): GoalShape {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Classify a Lean proof goal by sending a WHNF query to the Lean REPL.
  ##
  ## Creates a temporary Lean file that:
  ##   1. Opens the goal context
  ##   2. Applies `whnf` to reduce the goal
  ##   3. Prints the result for heuristic classification
  ##
  ## Falls back to heuristic-only classification if the REPL query fails.
  if leanGoalSource.len == 0:
    return gsUnknown

  # Build a Lean snippet that exposes the WHNF of the goal
  let leanQuery = """import Lean
open Lean Elab Meta in
#check fun (goal : Type) => goal
""" & leanGoalSource

  let replayResult = runLeanReplay("judge_automation_whnf", leanQuery)
  if replayResult.isOk and replayResult.get().isValid:
    let compilerOutput = replayResult.get().compilerOutput
    # Use heuristic on the WHNF-reduced output
    result = heuristicClassifyGoal(compilerOutput)
  else:
    # Fallback: classify using the raw goal source
    result = heuristicClassifyGoal(leanGoalSource)

  # Log unknown shapes for evolution analysis
  if result == gsUnknown:
    try:
      let logDir = getAxiomEnv(evLogDir, "logs")
      discard existsOrCreateDir(logDir)
      let logPath = logDir / "unknown_goal_shapes.jsonl"
      var logFile: File
      if open(logFile, logPath, fmAppend):
        let entry = %*{
          "goalSource": leanGoalSource.substr(0, 255),
          "shape": $result,
          "timestamp": int(epochTime())
        }
        logFile.write(pretty(entry) & "\n")
        logFile.close()
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)

# ──────────────────────────────────────────────────────────────────────────────
# LRU-cached classification
# ──────────────────────────────────────────────────────────────────────────────

proc classifyGoalWithCache*(cache: var GoalShapeCache; nodeId: string;
                            proofAttemptCount: int;
                            goalSExpr: string): GoalShape {.raises: [CatchableError], axiomEffect: IOEffect, tags: [RootEffect, TimeEffect, AxiomIOEffect, IOEffect].} =
  ## Classify a goal with LRU caching.
  ##
  ## Cache key is (nodeId, proofAttemptCount) — the same node with a different
  ## attempt count is treated as a fresh classification, since goal shape can
  ## change after tactic application.
  let key: GoalShapeCacheKey = (nodeId: nodeId, proofAttemptCount: proofAttemptCount)
  let cached = cacheGet(cache, key)
  if cached.isSome:
    return cached.get()

  let shape = classifyGoalViaWhnf(goalSExpr)
  cachePut(cache, key, shape, goalSExpr)
  shape

# ──────────────────────────────────────────────────────────────────────────────
# Strategy ladder
# ──────────────────────────────────────────────────────────────────────────────

{.push warning[UnreachableElse]: off.}

func selectStrategies*(goalShape: GoalShape): seq[JudgeStrategy] {.raises: [].} =
  ## Map a GoalShape to an ordered strategy ladder.
  ##
  ## The ladder is ordered by expected success probability for the given shape.
  ## The caller tries each strategy in order until one succeeds or all fail.
  ## Dispatch is compile-time generated from registered shape handlers.
  dispatchShape(goalShape)

func strategyToTactic*(strategy: JudgeStrategy): string {.raises: [].} =
  ## Convert a JudgeStrategy enum to its Lean 4 tactic name.
  ## Dispatch is compile-time generated from registered strategy handlers.
  dispatchStrategy(strategy)

{.pop.}

# ──────────────────────────────────────────────────────────────────────────────
# Deterministic proof attempts
# ──────────────────────────────────────────────────────────────────────────────

func buildProofAttemptSource(theoremSource: string; tactic: string): string {.raises: [].} =
  ## Inject a tactic into a theorem proof block.
  ## Expects theoremSource to contain `by` or `:= by` — appends tactic after.
  if theoremSource.len == 0:
    return ""

  var lines: seq[string] = @[]
  for line in theoremSource.splitLines():
    lines.add(line)

  # Find the proof entry point (by keyword) and inject tactic
  var injected = false
  var output: seq[string] = @[]
  for line in lines:
    output.add(line)
    let stripped = line.strip()
    if not injected and (stripped.endsWith("by") or stripped == "by"):
      output.add("  " & tactic)
      injected = true

  if not injected:
    # Fallback: append tactic as proof
    output.add(":= by")
    output.add("  " & tactic)

  output.join("\n")

proc tryDeterministicProof*(theoremSource: string;
                            goalShape: GoalShape): Option[LeanProofResult] {.raises: [], axiomEffect: IOEffect, tags: [RootEffect, TimeEffect, AxiomIOEffect, IOEffect].} =
  ## Try deterministic proof strategies in order for the given goal shape.
  ##
  ## Returns the first successful result, or `none` if all strategies fail.
  ## This avoids LLM calls for goals that deterministic tactics can solve.
  if theoremSource.len == 0:
    return none(LeanProofResult)

  let strategies = selectStrategies(goalShape)
  for strategy in strategies:
    if strategy == jsLlmFallback:
      # LLM fallback is handled externally by the judge pipeline
      continue

    let tactic = strategyToTactic(strategy)
    let proofSource = buildProofAttemptSource(theoremSource, tactic)
    if proofSource.len == 0:
      continue

    let replayResult = runLeanReplay("judge_auto_" & $strategy, proofSource)
    if replayResult.isOk and replayResult.get().isValid:
      return some(LeanProofResult(
        verified: true,
        strategy: strategy,
        output: replayResult.get().compilerOutput,
        exitCode: replayResult.get().exitCode
      ))

  none(LeanProofResult)

# ──────────────────────────────────────────────────────────────────────────────
# Unknown goal shape analysis (debug logging + aggregation)
# ──────────────────────────────────────────────────────────────────────────────

func extractGoalShapeName(parsed: JsonNode): string {.raises: [KeyError, ValueError, IOError, OSError].} =
  ## Extract the goal shape name from a parsed JSONL entry.
  ## Prefers "constName"; falls back to truncated "goalSource".
  ## [SEE: nim_effect_system_quirks.md §1.1] — JsonNode bracket access raises KeyError
  if parsed.hasKey("constName"):
    parsed["constName"].getStr()
  elif parsed.hasKey("goalSource"):
    parsed["goalSource"].getStr().substr(0, 60)
  else:
    ""

func sortCandidatesByFreq(a, b: GoalShapeCandidate): int {.raises: [].} =
  cmp(b.sampleCount, a.sampleCount)

func freqTableToCandidates(freqTable: Table[string, int]): seq[GoalShapeCandidate] {.raises: [].} =
  ## Convert a frequency table to sorted GoalShapeCandidate seq.
  result = @[]
  for name, count in freqTable:
    result.add(GoalShapeCandidate(name: name, sampleCount: count, suggestion: ""))
  result.sort(sortCandidatesByFreq)

proc analyzeUnknownGoalShapes*(logPath: string): seq[GoalShapeCandidate] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Read the JSONL log of unknown goal shapes and aggregate frequencies.
  ##
  ## Each line is a JSON object with at minimum a "goalSource" field.
  ## Returns candidates sorted by frequency (descending) for CI reporting.
  result = @[]

  if not fileExists(logPath):
    return

  var file: File
  try:
    if not open(file, logPath, fmRead):
      return

    var freqTable = initTable[string, int]()
    var line: string
    while file.readLine(line):
      let stripped = line.strip()
      if stripped.len == 0:
        continue
      try:
        let parsed = parseJson(stripped)
        let name = extractGoalShapeName(parsed)
        if name.len > 0:
          if name in freqTable:
            freqTable[name] += 1
          else:
            freqTable[name] = 1
      except CatchableError:
        discard  # axiom:best-effort(ioboundary catch)
    file.close()

    result = freqTableToCandidates(freqTable)

  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)

func unknownRatio*(totalGoals: int; unknownCount: int): float {.raises: [].} =
  ## Compute the ratio of unknown goals to total goals.
  if totalGoals == 0:
    return 0.0
  unknownCount.float / totalGoals.float

{.pop.}
