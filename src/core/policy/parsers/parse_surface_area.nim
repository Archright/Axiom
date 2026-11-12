import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## Parser module for surface_area, layer_limits, module_overrides sections.

import std/strutils
import std/tables
import core/types/results
import core/parsers/safe_parsers
import core/policy/section_parsers
import core/policy/parse_helpers
import core/policy/architecture_policy_types

func handleSurfaceArea(
  result: var ArchitecturePolicyParseResult;
  key: string; value: string; lineNo: int
) {.raises: [].} =
  if key == "max_imports" or key == "maxLines" or key == "maxImports" or key == "defaultMaxImports":
    let parsed = parseNatural(value)
    if not parsed.ok: result.addDiagnostic(lineNo, "expected natural number")
    else: result.policy.surfaceArea.defaultMaxImports = parsed.value
  elif key == "max_exported_functions" or key == "maxExportedFunctions" or key == "maxLines" or key == "defaultMaxExportedFunctions":
    let parsed = parseNatural(value)
    if not parsed.ok: result.addDiagnostic(lineNo, "expected natural number")
    else: result.policy.surfaceArea.defaultMaxExportedFunctions = parsed.value
  elif key == "max_function_lines" or key == "maxFunctionLines":
    let parsed = parseNatural(value)
    if not parsed.ok: result.addDiagnostic(lineNo, "expected natural number")
    else: result.policy.surfaceArea.maxFunctionLines = parsed.value
  else:
    result.addDiagnostic(lineNo, "unknown surface_area key " & key)

func handleLayerLimits(
  result: var ArchitecturePolicyParseResult;
  key: string; value: string; lineNo: int
) {.raises: [].} =
  discard lineNo
  # Parse inline object format: { maxImports = N, maxExportedFunctions = M }
  let miStart = value.find("maxImports = ")
  let meStart = value.find("maxExportedFunctions = ")
  var maxImports = 15
  var maxExported = 15
  if miStart >= 0:
    let numStart = miStart + 13  # "maxImports = " is 13 chars
    var numStr = ""
    for i in numStart ..< value.len:
      if value[i] in {'0'..'9'}:
        numStr.add(value[i])
      elif value[i] != ' ':
        break
    if numStr.len > 0:
      let parsed = safeParseInt(numStr)
      if parsed.isOk: maxImports = parsed.get
  if meStart >= 0:
    let numStart = meStart + 23  # "maxExportedFunctions = " is 23 chars
    var numStr = ""
    for i in numStart ..< value.len:
      if value[i] in {'0'..'9'}:
        numStr.add(value[i])
      elif value[i] != ' ':
        break
    if numStr.len > 0:
      let parsed = safeParseInt(numStr)
      if parsed.isOk: maxExported = parsed.get
  result.policy.surfaceArea.layerLimits[key] = LayerLimit(
    maxImports: maxImports,
    maxExportedFunctions: maxExported)

func handleModuleOverrides(
  result: var ArchitecturePolicyParseResult;
  key: string; value: string; lineNo: int
) {.raises: [].} =
  discard lineNo
  # Parse inline object format: { maxExportedFunctions = N, reason = "..." }
  let meStart = value.find("maxExportedFunctions = ")
  var maxExported = 15
  if meStart >= 0:
    let numStart = meStart + 23
    var numStr = ""
    for i in numStart ..< value.len:
      if value[i] in {'0'..'9'}:
        numStr.add(value[i])
      elif value[i] != ' ':
        break
    if numStr.len > 0:
      let parsed = safeParseInt(numStr)
      if parsed.isOk: maxExported = parsed.get
  result.policy.surfaceArea.moduleOverrides[key] = LayerLimit(
    maxImports: -1,  # -1 means "use layer default"
    maxExportedFunctions: maxExported)

proc registerSurfaceAreaSections*() {.raises: [].} =
  registerSection(SectionHandler(
    name: "surface_area",
    parse: handleSurfaceArea,
    isArray: false,
    informational: false
  ))
  registerSection(SectionHandler(
    name: "layer_limits",
    parse: handleLayerLimits,
    isArray: false,
    informational: false
  ))
  registerSection(SectionHandler(
    name: "module_overrides",
    parse: handleModuleOverrides,
    isArray: false,
    informational: false
  ))

{.pop.}
