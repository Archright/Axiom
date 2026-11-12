import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## Parser module for interfaces, opaque_types sections.

import std/strutils
import std/tables
import core/policy/section_parsers
import core/policy/parse_helpers
import core/policy/architecture_policy_types

func handleInterfaces(
  result: var ArchitecturePolicyParseResult;
  key: string; value: string; lineNo: int
) {.raises: [].} =
  # Parse inline object format: { file = "...", requiredPragmas = [...] }
  let fileStart = value.find("file = \"")
  let pragmasStart = value.find("requiredPragmas = [")
  if fileStart >= 0:
    let fileQuoteStart = fileStart + 8
    let fileQuoteEnd = value.find("\"", fileQuoteStart)
    let fileVal = if fileQuoteEnd >= 0: value[fileQuoteStart ..< fileQuoteEnd] else: "auto"
    var reqPragmas: seq[string] = @[]
    if pragmasStart >= 0:
      let pragmasBracketStart = pragmasStart + 18
      let pragmasBracketEnd = value.find("]", pragmasBracketStart)
      if pragmasBracketEnd >= 0:
        let pragmasStr = value[pragmasBracketStart ..< pragmasBracketEnd]
        let parsed = parseStringArray("[" & pragmasStr & "]")
        if parsed.ok: reqPragmas = parsed.values
    result.policy.interfaces[key] = InterfaceContract(
      file: fileVal,
      requiredPragmas: reqPragmas,
      allowedRaises: @[])
  else:
    # Fallback to array format
    let parsed = parseStringArray(value)
    if parsed.ok and parsed.values.len >= 1:
      let reqPragmas = if parsed.values.len >= 2: parsed.values[1..^1] else: @[]
      result.policy.interfaces[key] = InterfaceContract(
        file: parsed.values[0],
        requiredPragmas: reqPragmas,
        allowedRaises: @[])
    else:
      result.addDiagnostic(lineNo, "expected { file = \"...\", requiredPragmas = [...] } for interfaces." & key)

func handleOpaqueTypes(
  result: var ArchitecturePolicyParseResult;
  key: string; value: string; lineNo: int
) {.raises: [].} =
  # Parse inline object format: { owner = "..." }
  let ownerStart = value.find("owner = \"")
  if ownerStart >= 0:
    let ownerQuoteStart = ownerStart + 9
    let ownerQuoteEnd = value.find("\"", ownerQuoteStart)
    let ownerVal = if ownerQuoteEnd >= 0: value[ownerQuoteStart ..< ownerQuoteEnd] else: ""
    result.policy.opaqueTypes[key] = OpaqueType(
      constructorModule: ownerVal,
      consumerLayers: @[])
  else:
    # Fallback to array format
    let parsed = parseStringArray(value)
    if parsed.ok and parsed.values.len >= 1:
      let layers = if parsed.values.len >= 2: parsed.values[1..^1] else: @[]
      result.policy.opaqueTypes[key] = OpaqueType(
        constructorModule: parsed.values[0],
        consumerLayers: layers)
    else:
      result.addDiagnostic(lineNo, "expected { owner = \"...\" } for opaque_types." & key)

proc registerInterfaceSections*() {.raises: [].} =
  registerSection(SectionHandler(
    name: "interfaces",
    parse: handleInterfaces,
    isArray: false,
    informational: false
  ))
  registerSection(SectionHandler(
    name: "opaque_types",
    parse: handleOpaqueTypes,
    isArray: false,
    informational: false
  ))

{.pop.}
