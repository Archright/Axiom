import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
import ../utils/axiom_clock
import std/options
import std/times  # for initDuration
type
  BmcPropertyKind* = enum
    bpkRaceCondition        ## Original: concurrent write deviation
    bpkIntegerOverflow      ## New: value exceeds bit-width bounds
    bpkIndexOutOfBounds     ## New: array index outside [0, length)
    bpkNullDereference      ## New: dereference of null/nil value

  BmcConfig* = object
    threadCount*: int             ## Number of threads (default 2)
    variableCount*: int           ## Number of shared variables (default 1)
    stepBound*: int               ## Exploration depth (default 10)
    property*: BmcPropertyKind    ## Property to check
    bitWidth*: int                ## For overflow: 32 or 64 (default 32)
    arrayLength*: int             ## For bounds: array length (default 100)
    timeoutMs*: int               ## Wall-clock timeout in milliseconds

  GenericPcState* = enum
    gpcInit
    gpcCompute
    gpcCheck
    gpcAccess
    gpcDone

  GenericBmcTrace* = object
    pcs*: seq[seq[GenericPcState]]      ## [thread][step] program counters
    vars*: seq[seq[int]]                ## [variable][step] shared variable values
    locals*: seq[seq[int]]              ## [thread][step] thread-local registers
    owners*: seq[int]                   ## [step] which thread acted (-1 = none)
    steps*: int

  GenericBmcVerdict* = object
    propertyKind*: BmcPropertyKind
    violationDetected*: bool
    violationDetail*: string
    witness*: GenericBmcTrace
    exploredPaths*: int
    timedOut*: bool               ## True if BMC exploration exceeded wall-clock timeout
const
  defaultBitWidth* = 32
  defaultArrayLength* = 100
  maxGenericStepBound* = 15
  bmcWallClockTimeoutMs* = 5_000  ## 5-second safety net for BMC exploration
  bmcTimeoutCheckInterval* = 10   ## Check wall-clock every N steps (performance optimization)
func initBmcConfig*(
  property: BmcPropertyKind;
  threadCount: int = 2;
  variableCount: int = 1;
  stepBound: int = 10;
  bitWidth: int = defaultBitWidth;
  arrayLength: int = defaultArrayLength;
  timeoutMs: int = bmcWallClockTimeoutMs
): BmcConfig =
  BmcConfig(
    threadCount: threadCount,
    variableCount: variableCount,
    stepBound: min(stepBound, maxGenericStepBound),
    property: property,
    bitWidth: bitWidth,
    arrayLength: arrayLength,
    timeoutMs: timeoutMs
  )
func initGenericTrace(config: BmcConfig; initialValues: seq[int]): GenericBmcTrace =
  var pcs: seq[seq[GenericPcState]] = @[]
  var locals: seq[seq[int]] = @[]
  for t in 0 ..< config.threadCount:
    var threadPcs = newSeq[GenericPcState](config.stepBound + 1)
    threadPcs[0] = gpcInit
    pcs.add(threadPcs)
    var threadLocals = newSeq[int](config.stepBound + 1)
    locals.add(threadLocals)
  var vars: seq[seq[int]] = @[]
  for v in 0 ..< config.variableCount:
    var varSteps = newSeq[int](config.stepBound + 1)
    varSteps[0] = if v < initialValues.len: initialValues[v] else: 0
    vars.add(varSteps)
  GenericBmcTrace(
    pcs: pcs,
    vars: vars,
    locals: locals,
    owners: newSeq[int](config.stepBound),
    steps: 0
  )
func checkViolation(
  config: BmcConfig;
  trace: GenericBmcTrace;
  step: int
): Option[string] =
  ## Check if the current state violates the property.
  case config.property
  of bpkRaceCondition:
    # Race detection is handled by the specialized bmc_engine.nim
    none(string)
  of bpkIntegerOverflow:
    for v in 0 ..< config.variableCount:
      let val = trace.vars[v][step]
      let limit = 1 shl (config.bitWidth - 1)
      if val > limit - 1 or val < -limit:
        return some("integer overflow: var[" & $v & "]=" & $val & " exceeds " & $config.bitWidth & "-bit range")
    none(string)
  of bpkIndexOutOfBounds:
    for v in 0 ..< config.variableCount:
      let idx = trace.vars[v][step]
      if idx < 0 or idx >= config.arrayLength:
        return some("index out of bounds: index=" & $idx & " not in [0, " & $config.arrayLength & ")")
    none(string)
  of bpkNullDereference:
    for v in 0 ..< config.variableCount:
      let val = trace.vars[v][step]
      if val == 0:  # convention: 0 = null
        return some("null dereference: var[" & $v & "] is null (0)")
    none(string)
func advancePc(pc: GenericPcState): GenericPcState =
  case pc
  of gpcInit: gpcCompute
  of gpcCompute: gpcCheck
  of gpcCheck: gpcAccess
  of gpcAccess: gpcDone
  of gpcDone: gpcDone
func applyGenericTransition(
  trace: GenericBmcTrace;
  step: int;
  threadIdx: int;
  config: BmcConfig;
  delta: int
): GenericBmcTrace =
  result = trace
  result.owners[step] = threadIdx
  # Copy current state to next step
  for t in 0 ..< config.threadCount:
    result.pcs[t][step + 1] = trace.pcs[t][step]
  for v in 0 ..< config.variableCount:
    result.vars[v][step + 1] = trace.vars[v][step]
  for t in 0 ..< config.threadCount:
    result.locals[t][step + 1] = trace.locals[t][step]
  # Advance the acting thread
  let oldPc = trace.pcs[threadIdx][step]
  result.pcs[threadIdx][step + 1] = advancePc(oldPc)
  case oldPc
  of gpcInit:
    discard  # transition to compute
  of gpcCompute:
    result.locals[threadIdx][step + 1] = trace.vars[0][step]  # read shared var
  of gpcCheck:
    discard  # bounds/null check happens in checkViolation
  of gpcAccess:
    result.vars[0][step + 1] = trace.locals[threadIdx][step] + delta  # write
  of gpcDone:
    discard
  result.steps = step + 1
func genericExplore[C](
  clk: var C;
  step: int;
  trace: GenericBmcTrace;
  verdict: GenericBmcVerdict;
  config: BmcConfig;
  delta: int;
  deadlineNs: int64
): GenericBmcVerdict =
  result = verdict
  if result.violationDetected:
    return  # early exit on first violation

  # Wall-clock timeout guard (checked every N steps for performance)
  if step mod bmcTimeoutCheckInterval == 0:
    ## [SEE: nim_effect_system_quirks.md]
    {.cast(noSideEffect).}:
      if clk.monoNs() > deadlineNs:
        result.timedOut = true
        result.violationDetected = true
        result.violationDetail = "BMC wall-clock timeout (" & $config.timeoutMs & "ms) exceeded"
        return

  # Check violation at current step
  let violation = checkViolation(config, trace, step)
  if violation.isSome:
    result.violationDetected = true
    result.violationDetail = violation.get
    result.witness = trace
    return

  if step >= config.stepBound:
    inc result.exploredPaths
    return

  # Try each thread acting at this step
  for threadIdx in 0 ..< config.threadCount:
    if trace.pcs[threadIdx][step] == gpcDone:
      continue
    let next = applyGenericTransition(trace, step, threadIdx, config, delta)
    ## [SEE: nim_effect_system_quirks.md]
    {.cast(noSideEffect).}:
      clk.tick()
    result = genericExplore[C](clk, step + 1, next, result, config, delta, deadlineNs)
    if result.violationDetected:
      return

## Verify Generic Property — main entry point for generalized BMC.
func verifyGenericProperty*[C](
  clk: var C;
  config: BmcConfig;
  initialValues: seq[int];
  delta: int = 0
): GenericBmcVerdict {.raises: [].} =
  result.propertyKind = config.property
  let trace = initGenericTrace(config, initialValues)
  var deadlineNs: int64
  ## [SEE: nim_effect_system_quirks.md]
  {.cast(noSideEffect).}:
    deadlineNs = clk.monoNs() + config.timeoutMs * 1_000_000
  result = genericExplore[C](clk, 0, trace, result, config, delta, deadlineNs)

## Verify Integer Overflow — convenience wrapper.
func verifyIntegerOverflow*(
  initialValue: int;
  delta: int;
  bitWidth: int = defaultBitWidth
): GenericBmcVerdict {.raises: [].} =
  let config = initBmcConfig(bpkIntegerOverflow, bitWidth = bitWidth)
  var clk = SystemClock()
  verifyGenericProperty(clk, config, @[initialValue], delta)

## Verify Index Bounds — convenience wrapper.
func verifyIndexBounds*(
  indexValue: int;
  arrayLength: int = defaultArrayLength
): GenericBmcVerdict {.raises: [].} =
  let config = initBmcConfig(bpkIndexOutOfBounds, arrayLength = arrayLength)
  var clk = SystemClock()
  verifyGenericProperty(clk, config, @[indexValue], 0)

## Verify Null Dereference — convenience wrapper.
func verifyNullDereference*(
  pointerValue: int
): GenericBmcVerdict {.raises: [].} =
  let config = initBmcConfig(bpkNullDereference)
  var clk = SystemClock()
  verifyGenericProperty(clk, config, @[pointerValue], 0)

## Property kind to string — for reporting.
func propertyKindToString*(kind: BmcPropertyKind): string {.raises: [].} =
  case kind
  of bpkRaceCondition: "race_condition"
  of bpkIntegerOverflow: "integer_overflow"
  of bpkIndexOutOfBounds: "index_out_of_bounds"
  of bpkNullDereference: "null_dereference"

{.pop.}
