## CEGAR-BMC Bridge — connects CEGAR counterexample detection to BMC witness generation.
##
## When CEGAR finds a counterexample (cvCounterexample verdict), this bridge
## delegates to the generalized BMC engine to produce a concrete execution trace.
##
## Design: Phase 4 of ax prove architecture refactor.
## Implements the comment in cegar_engine.nim: "cegarCounterexample — delegate to BMC"

import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

import std/strutils
import core/bmc/bmc_generic
import core/utils/axiom_clock
import core/orchestrator/cegar_types
import core/orchestrator/cegar_bmc_types
from core/boundary/verification_interface import CegarResult, cvCounterexample
import verification/cegar_adapter
# axiomIoBoundary

func deriveBmcConfigFromCegar(sourceCode: string): BmcConfig {.raises: [].} =
  ## Derive BMC configuration from source code heuristics.
  let hasArrayAccess = sourceCode.find("[") >= 0 and sourceCode.find("]") >= 0
  let hasPointerCheck = sourceCode.find("nil") >= 0 or sourceCode.find("null") >= 0
  let hasArithmetic = sourceCode.find("*") >= 0 or sourceCode.find("div") >= 0

  if hasArrayAccess:
    initBmcConfig(bpkIndexOutOfBounds, arrayLength = 100)
  elif hasPointerCheck:
    initBmcConfig(bpkNullDereference)
  elif hasArithmetic:
    initBmcConfig(bpkIntegerOverflow, bitWidth = 32)
  else:
    initBmcConfig(bpkRaceCondition)

func formatWitness(trace: GenericBmcTrace; config: BmcConfig): string {.raises: [].} =
  ## Format a BMC trace as human-readable witness.
  result.add("BMC Witness (" & propertyKindToString(config.property) & ")\n")
  result.add("Steps: " & $trace.steps & "\n")
  for step in 0 ..< trace.steps:
    let threadIdx = trace.owners[step]
    result.add("  Step " & $step & ": thread[" & $threadIdx & "] ")
    for v in 0 ..< config.variableCount:
      result.add("var[" & $v & "]=" & $trace.vars[v][step] & " ")
    result.add("\n")

## Bridge CEGAR to BMC — when CEGAR finds a counterexample, generate concrete witness.
func bridgeCegarToBmc*(
  cegarResult: CegarResult;
  sourceCode: string;
  initialValues: seq[int] = @[];
  delta: int = 0
): CegarBmcResult {.raises: [].} =
  result.cegarVerdict = cegarResult.verdict.toEngineVerdict()

  # Only bridge if CEGAR found a counterexample
  if cegarResult.verdict != cvCounterexample:
    return

  let config = deriveBmcConfigFromCegar(sourceCode)
  result.propertyKind = config.property

  let effectiveValues = if initialValues.len > 0: initialValues else: @[100]
  var clk = deterministicClock(0, 0)
  result.bmcVerdict = verifyGenericProperty(clk, config, effectiveValues, delta)

  if result.bmcVerdict.violationDetected:
    result.concreteWitness = formatWitness(result.bmcVerdict.witness, config)
  else:
    result.concreteWitness = "BMC did not find concrete witness within step bound"

## Source-only bridge — bypasses CegarResult when only sourceCode is available.
func bridgeCegarToBmc*(
  sourceCode: string;
  initialValues: seq[int] = @[];
  delta: int = 0
): CegarBmcResult {.raises: [].} =
  let config = deriveBmcConfigFromCegar(sourceCode)
  result.cegarVerdict = cegarCounterexample
  result.propertyKind = config.property

  let effectiveValues = if initialValues.len > 0: initialValues else: @[100]
  var clk2 = deterministicClock(0, 0)
  result.bmcVerdict = verifyGenericProperty(clk2, config, effectiveValues, delta)

  if result.bmcVerdict.violationDetected:
    result.concreteWitness = formatWitness(result.bmcVerdict.witness, config)
  else:
    result.concreteWitness = "BMC did not find concrete witness within step bound"
{.pop.}
