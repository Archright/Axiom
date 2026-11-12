import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## Parser module for cohesion, lcom_overrides, tcc_overrides sections.

import std/strutils
import std/tables
import core/types/results
import core/parsers/safe_parsers
import core/policy/section_parsers
import core/policy/parse_helpers
import core/policy/architecture_policy_types

func handleCohesion(
  result: var ArchitecturePolicyParseResult;
  key: string; value: string; lineNo: int
) {.raises: [].} =
  if key == "max_lcom" or key == "lcomThreshold":
    let sfR = safeParseFloat(value.strip())
    let fval = if sfR.isOk: sfR.get else: -1.0
    if fval < 0.0: result.addDiagnostic(lineNo, "expected float for cohesion." & key)
    else: result.policy.cohesion.maxLcom = fval
  elif key == "min_tcc" or key == "tccThreshold":
    let sfR = safeParseFloat(value.strip())
    let fval = if sfR.isOk: sfR.get else: -1.0
    if fval < 0.0: result.addDiagnostic(lineNo, "expected float for cohesion." & key)
    else: result.policy.cohesion.minTcc = fval
  else:
    result.addDiagnostic(lineNo, "unknown cohesion key " & key)

func handleLcomOverrides(
  result: var ArchitecturePolicyParseResult;
  key: string; value: string; lineNo: int
) {.raises: [].} =
  let sfR = safeParseFloat(value.strip())
  let fval = if sfR.isOk: sfR.get else: -1.0
  if fval < 0.0:
    result.addDiagnostic(lineNo, "expected float for lcom_overrides." & key)
  else:
    result.policy.cohesion.lcomOverrides[key] = fval

func handleTccOverrides(
  result: var ArchitecturePolicyParseResult;
  key: string; value: string; lineNo: int
) {.raises: [].} =
  let sfR = safeParseFloat(value.strip())
  let fval = if sfR.isOk: sfR.get else: -1.0
  if fval < 0.0:
    result.addDiagnostic(lineNo, "expected float for tcc_overrides." & key)
  else:
    result.policy.cohesion.tccOverrides[key] = fval

proc registerCohesionSections*() {.raises: [].} =
  registerSection(SectionHandler(
    name: "cohesion",
    parse: handleCohesion,
    isArray: false,
    informational: false
  ))
  registerSection(SectionHandler(
    name: "lcom_overrides",
    parse: handleLcomOverrides,
    isArray: false,
    informational: false
  ))
  registerSection(SectionHandler(
    name: "tcc_overrides",
    parse: handleTccOverrides,
    isArray: false,
    informational: false
  ))

{.pop.}
