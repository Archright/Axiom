import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## Parser module for canonical_computations section.

import std/strutils
import std/tables
import core/policy/section_parsers
import core/policy/parse_helpers
import core/policy/architecture_policy_types

func handleCanonicalComputations(
  result: var ArchitecturePolicyParseResult;
  key: string; value: string; lineNo: int
) {.raises: [].} =
  # Parse inline object format: { owner = "...", varType = "..." }
  let ownerStart = value.find("owner = \"")
  let varTypeStart = value.find("varType = \"")
  if ownerStart >= 0:
    let ownerQuoteStart = ownerStart + 9
    let ownerQuoteEnd = value.find("\"", ownerQuoteStart)
    let ownerVal = if ownerQuoteEnd >= 0: value[ownerQuoteStart ..< ownerQuoteEnd] else: ""
    let varTypeVal = if varTypeStart >= 0:
      let vtQuoteStart = varTypeStart + 11
      let vtQuoteEnd = value.find("\"", vtQuoteStart)
      if vtQuoteEnd >= 0: value[vtQuoteStart ..< vtQuoteEnd] else: ""
    else: ""
    result.policy.canonicalComputations[key] = CanonicalComputation(
      owner: ownerVal,
      pattern: key,
      varType: varTypeVal)
  else:
    # Fallback to array format
    let parsed = parseStringArray(value)
    if parsed.ok and parsed.values.len >= 2:
      result.policy.canonicalComputations[key] = CanonicalComputation(
        owner: parsed.values[0],
        pattern: parsed.values[1],
        varType: if parsed.values.len >= 3: parsed.values[2] else: "")
    else:
      result.addDiagnostic(lineNo, "expected { owner = \"...\", varType = \"...\" } for canonical_computations." & key)

proc registerCanonicalSections*() {.raises: [].} =
  registerSection(SectionHandler(
    name: "canonical_computations",
    parse: handleCanonicalComputations,
    isArray: false,
    informational: false
  ))

{.pop.}
