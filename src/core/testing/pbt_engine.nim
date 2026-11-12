{.push raises: [].}
import core/trusted/layer_declaration
axiomLayer "domain"
import core/parsers/safe_parsers
import core/trusted/axiom_pragmas
import core/trusted/env_access
import core/types/results
import core/interfaces/logging_hub
import std/[envvars, json, monotimes, random, tables, times]
# ─── Types ────────────────────────────────────────────────────

type
  BitStream* = object
    ## Thin wrapper over Rand with cursor tracking for shrink sizing.
    rng*: Rand
    cursor*: int           ## consumed bit count (for shrink sizing)
    seed*: int64           ## origin seed (for replay)
    shrinkDepth*: int      ## current shrink iteration

  Gen*[T] = proc(bs: var BitStream): T
    ## Generator combinator type. Consumes from BitStream to produce T.

  PbtVerbosity* = enum
    PbtSilent  = "silent"  ## Default for PbtBasic: output only on failure
    PbtVerbose = "verbose" ## Default for PbtStress: all markers + shrink details

  PropertyTier* = enum
    PbtBasic  = "basic"    ## Required: runs in every CI push
    PbtStress = "stress"   ## Optional: nightly/manual only

  PropertyResult* = object
    passed*: bool
    seed*: int64
    shrinkSteps*: int
    originalSize*: int
    shrunkSize*: int
    counterExample*: string  ## repr of minimal failing input
    timedOut*: bool          ## true if shrink hit maxDuration
    passCount*: int
    failCount*: int
    discarded*: int

# ─── Helpers ──────────────────────────────────────────────────

func randInt*(bs: var BitStream; min, max: int): int =
  ## Draw a random int from [min, max], advancing cursor.
  result = bs.rng.rand(min..max)
  inc bs.cursor
func randFloat*(bs: var BitStream): float =
  ## Draw a random float from [0.0, 1.0), advancing cursor.
  result = bs.rng.rand(1.0)
  inc bs.cursor
func randBool*(bs: var BitStream; p: float = 0.5): bool =
  ## Draw a random bool with probability p for true.
  result = bs.randFloat() < p
func randAlphanumeric*(bs: var BitStream; length: int): string =
  ## Generate a random alphanumeric string of given length.
  const chars = "abcdefghijklmnopqrstuvwxyz0123456789"
  result = newString(length)
  for i in 0..<length:
    result[i] = chars[bs.randInt(0, chars.high)]
# Pattern: Hypothesis @composite / flatmap / one_of / filter
func map*[T, U](gen: Gen[T]; f: proc(t: T): U): Gen[U] =
  ## Gen[T] -> Gen[U] via transformation. Shrinks along original T.
  return proc(bs: var BitStream): U = f(gen(bs))
func flatMap*[T, U](gen: Gen[T]; f: proc(t: T): Gen[U]): Gen[U] =
  ## Gen[T] -> (T -> Gen[U]) -> Gen[U]. For dependent data.
  return proc(bs: var BitStream): U =
    let t = gen(bs)
    let inner = f(t)
    inner(bs)
func filter*[T](gen: Gen[T]; pred: proc(t: T): bool;
                maxAttempts: int = 50): Gen[T] {.raises: [].} =
  ## Gen[T] -> Gen[T] (filtered). Retries up to maxAttempts.
  return proc(bs: var BitStream): T =
    for _ in 0..<maxAttempts:
      result = gen(bs)
      if pred(result): return
    result = gen(bs)
func oneOf*[T](gens: openArray[Gen[T]]): Gen[T] =
  ## Uniformly picks from provided generators.
  return proc(bs: var BitStream): T =
    let idx = bs.randInt(0, gens.high)
    gens[idx](bs)
func genSeq*[T](elemGen: Gen[T]; minLen, maxLen: int): Gen[seq[T]] =
  ## Generate seq[T] from element generator. Composable.
  return proc(bs: var BitStream): seq[T] =
    let len = bs.randInt(minLen, maxLen)
    result = newSeq[T](len)
    for i in 0..<len:
      result[i] = elemGen(bs)
func genTable*[T](keyGen: Gen[string]; valGen: Gen[T];
                  minLen, maxLen: int): Gen[Table[string, T]] =
  ## Generate Table[string, T] from key/value generators.
  return proc(bs: var BitStream): Table[string, T] =
    let len = bs.randInt(minLen, maxLen)
    result = initTable[string, T]()
    for i in 0..<len:
      let k = keyGen(bs)
      result[k] = valGen(bs)
func genInt*(min, max: int): Gen[int] =
  return proc(bs: var BitStream): int = bs.randInt(min, max)
func genBool*(): Gen[bool] =
  return proc(bs: var BitStream): bool = bs.randBool()
func genFloat*(): Gen[float] =
  return proc(bs: var BitStream): float = bs.randFloat()
func genString*(minLen, maxLen: int): Gen[string] =
  return proc(bs: var BitStream): string =
    let len = bs.randInt(minLen, maxLen)
    bs.randAlphanumeric(len)
func generateBitReduction*(bs: BitStream): BitStream =
  ## Course 1: halve the bitstream by resetting cursor midpoint.
  var reduced = bs
  reduced.cursor = max(0, bs.cursor div 2)
  reduced.shrinkDepth = bs.shrinkDepth + 1
  reduced
func generateValueSimplification*(bs: BitStream): BitStream =
  ## Course 2: zero out the rng seed to produce minimal values.
  var simplified = bs
  simplified.rng = initRand(0)
  simplified.shrinkDepth = bs.shrinkDepth + 1
  simplified
func generateStructurePruning*(bs: BitStream): BitStream =
  ## Course 3: reduce cursor by 1 (for seq length shrinkage).
  var pruned = bs
  pruned.cursor = max(0, bs.cursor - 1)
  pruned.shrinkDepth = bs.shrinkDepth + 1
  pruned
const
  defaultMaxShrinkSteps* = 100
  defaultMaxShrinkDuration* = initDuration(seconds = 5)
template withSnapshot*(bs: var BitStream; body: untyped): untyped =
  ## Guarantees BitStream cursor restoration even if body raises.
  let savedCursor = bs.cursor
  try:
    body
  finally:
    bs.cursor = savedCursor
proc initSeed*(): int64 {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  axiomIoHint("I/O boundary: getEnv + epochTime for seed initialization")
  ## Priority: AXIOM_PBT_SEED env > time-based.
  let envSeed = getAxiomEnv(evPbtSeed)
  if envSeed.len > 0:
    let parsed = safeParseInt(envSeed)
    if parsed.isOk(): return int64(parsed.get())
  ## [SEE: nim_effect_system_quirks.md §1.1]
  {.cast(noSideEffect).}:
    return int64(epochTime() * 1000) and 0x7FFFFFFFFFFFFFFF
func initBitStream*(seed: int64): BitStream {.raises: [].} =
  BitStream(rng: initRand(seed), cursor: 0, seed: seed, shrinkDepth: 0)
proc emitPbtMarker*(kind: string; seed: int64; detail: string = "";
                    verbosity: PbtVerbosity = PbtSilent) {.raises: [IOError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  axiomIoHint("I/O boundary: echo for CI marker output")
  ## PbtSilent (default): only output FAILED/TIMEOUT markers.
  ## PbtVerbose: output all markers including SEED and SHRINK.
  case kind
  of "FAILED", "TIMEOUT":
    logging_hub.logInfo("[PBT-" & $kind & "] Seed: " & $seed & " " & detail)
  of "SEED":
    if verbosity == PbtVerbose:
      logging_hub.logInfo("[PBT-SEED] Seed: " & $seed)
  of "SHRINK":
    if verbosity == PbtVerbose:
      logging_hub.logInfo("[PBT-SHRINK] " & $detail)
  else:
    discard
proc shrinkToMinimal*[T](
    gen: Gen[T]; prop: proc(t: T): bool; origBs: BitStream;
    maxSteps: int = defaultMaxShrinkSteps;
    maxDuration: Duration = defaultMaxShrinkDuration
): tuple[minimal: string; steps: int; timedOut: bool] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  axiomIoHint("I/O boundary: getMonoTime for shrink timeout")
  ## 3-course greedy shrinking per Hypothesis pattern.
  let startTime = getMonoTime()
  var bs = origBs
  var steps = 0

  # Generate initial value (caller already found it failing)
  bs.cursor = 0
  var bestValue: T
  try:
    bestValue = gen(bs)
  except CatchableError:
    return ("", 0, false)
  var bestSize = bs.cursor

  let courses = [generateBitReduction, generateValueSimplification,
                 generateStructurePruning]

  for courseFn in courses:
    var improved = true
    while improved:
      improved = false
      # Guard 1: step count limit
      if steps >= maxSteps:
        return ($bestValue, steps, false)
      # Guard 2: wall-clock timeout
      if (getMonoTime() - startTime).inNanoseconds > maxDuration.inNanoseconds:
        return ($bestValue, steps, true)
      inc steps
      let candidate = courseFn(bs)
      var testBs = candidate
      testBs.cursor = 0
      var value: T
      testBs.withSnapshot:
        try:
          value = gen(testBs)
        except Exception:
          inc steps
          continue
      var propFailed = true
      try:
        propFailed = not prop(value)
      except Exception:
        propFailed = true
      if propFailed and testBs.cursor < bestSize:
        bs = testBs
        bestValue = value
        bestSize = testBs.cursor
        improved = true

  return ($bestValue, steps, false)
proc checkProperty*[T](
    gen: Gen[T]; prop: proc(t: T): bool;
    iterations: int = 200;
    maxShrinkSteps: int = defaultMaxShrinkSteps;
    maxDuration: Duration = defaultMaxShrinkDuration;
    tier: PropertyTier = PbtBasic;
    verbosity: PbtVerbosity = PbtSilent;
    overrideSeed: int64 = 0
): PropertyResult {.raises: [IOError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  axiomIoHint("I/O boundary: orchestrates initSeed + emitPbtMarker + shrinkToMinimal")
  ## Generate+test+shrink. Silent by default.
  let seed = if overrideSeed != 0: overrideSeed else: initSeed()
  var bs = initBitStream(seed)

  # Phase 1: Generate + test
  for i in 0..<iterations:
    bs.cursor = 0
    var value: T
    bs.withSnapshot:
      try:
        value = gen(bs)
      except CatchableError:
        continue
    var propHolds = true
    try:
      propHolds = prop(value)
    except Exception:
        propHolds = false
    if not propHolds:
      # Phase 2: Shrink (multicourse)
      let origSize = bs.cursor
      let (minimal, steps, timedOut) = shrinkToMinimal(
        gen, prop, bs, maxShrinkSteps, maxDuration)
      if timedOut:
        emitPbtMarker("TIMEOUT", seed, minimal, verbosity)
      else:
        emitPbtMarker("FAILED", seed, minimal, verbosity)
      return PropertyResult(
        passed: false, seed: seed, shrinkSteps: steps,
        originalSize: origSize, shrunkSize: minimal.len,
        counterExample: minimal, timedOut: timedOut
      )

  emitPbtMarker("SEED", seed, verbosity = verbosity)
  return PropertyResult(passed: true, seed: seed)
