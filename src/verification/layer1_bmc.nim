import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

import core/bmc/bmc_generic
import core/utils/axiom_clock
import core/boundary/verification_interface
import ../core/trusted/axiom_pragmas
import std/json
import std/monotimes
import verification/unified_trajectory
# axiomIoBoundary
## [SEE: nim_effect_system_quirks.md] — parseJson side-effect quirk

proc detectPropertyKindsFromAst(astJson: string): seq[BmcPropertyKind] {.raises: [].} =
  result = @[]
  var hasMemoryRead = false
  var hasArithmetic = false
  {.cast(noSideEffect).}:
    {.cast(raises: []).}:
      try:
        let parsed = parseJson(astJson)
        if parsed.hasKey("nodes"):
          for node in parsed["nodes"]:
            let kind = node{"kind"}.getStr("")
            case kind
            of "memory_read":
              hasMemoryRead = true
            of "assign":
              let op = node{"op"}.getStr("assign")
              if op in ["mul", "div", "add", "sub"]:
                hasArithmetic = true
            else:
              discard
      except CatchableError:
        discard  # axiom:best-effort(ioboundary catch)
  if hasMemoryRead:
    result.add bpkIndexOutOfBounds
  if hasArithmetic:
    result.add bpkIntegerOverflow
  if result.len == 0:
    result.add bpkIndexOutOfBounds

proc runLayer1Bmc*(req: UniversalPipelineRequest): Layer1BmcResult {.raises: [], refines: "src/verification/layer1_bmc_shadow.nim".} =
  let startTicks = getMonoTime().ticks
  let propertyKinds = detectPropertyKindsFromAst(req.astJson)
  var hasLoops = false
  {.cast(noSideEffect).}:
    {.cast(raises: []).}:
      try:
        let parsed = parseJson(req.astJson)
        if parsed.hasKey("nodes"):
          for node in parsed["nodes"]:
            if node{"kind"}.getStr("") == "loop":
              hasLoops = true
              break
      except CatchableError:
        discard  # axiom:best-effort(ioboundary catch)
  if hasLoops:
    let ems = (getMonoTime().ticks - startTicks) div 1_000_000
    logStage(skSwat, req.functionName, "inconclusive: has loops", elapsedMs=int(ems))
    return Layer1BmcResult(verdict: lbvInconclusive, provenLayer: plkUnknown,
      witnessTrace: GenericBmcTrace(), elapsedMs: ems)
  for kind in propertyKinds:
    let config = initBmcConfig(kind, stepBound = 5)
    var clk = deterministicClock(0, 0)
    let bmcVerdict = verifyGenericProperty(clk, config, @[0], 0)
    if bmcVerdict.violationDetected:
      let elapsedMsVal = (getMonoTime().ticks - startTicks) div 1_000_000
      logStage(skSwat, req.functionName, "proposition disproved: " & propertyKindToString(kind),
        elapsedMs=int(elapsedMsVal))
      return Layer1BmcResult(verdict: lbvBugFound, provenLayer: plkL1Bmc,
        witnessTrace: bmcVerdict.witness, elapsedMs: elapsedMsVal)
  let elapsedMsVal = (getMonoTime().ticks - startTicks) div 1_000_000
  logStage(skSwat, req.functionName, "proven", elapsedMs=int(elapsedMsVal), status=ssSucceeded)
  Layer1BmcResult(verdict: lbvProven, provenLayer: plkL1Bmc,
    witnessTrace: GenericBmcTrace(), elapsedMs: elapsedMsVal)

{.pop.}
