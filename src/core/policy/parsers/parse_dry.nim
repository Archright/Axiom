import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## Parser module for dry section.

import core/policy/section_parsers
import core/policy/parse_helpers
import core/policy/architecture_policy_types

func handleDry(
  result: var ArchitecturePolicyParseResult;
  key: string; value: string; lineNo: int
) {.raises: [].} =
  if key == "function_clone_min_ast_nodes":
    let parsed = parseNatural(value)
    if not parsed.ok:
      result.addDiagnostic(lineNo, "expected natural number for dry." & key)
    else:
      result.policy.dry.functionCloneMinAstNodes = parsed.value
  elif key == "alpha_equivalence":
    let parsed = parseBoolValue(value)
    if not parsed.ok:
      result.addDiagnostic(lineNo, "expected boolean for dry." & key)
    else:
      result.policy.dry.alphaEquivalence = parsed.value
  elif key == "boilerplate_node_count_threshold":
    let parsed = parseNatural(value)
    if not parsed.ok:
      result.addDiagnostic(lineNo, "expected natural number for dry." & key)
    else:
      result.policy.dry.boilerplateNodeCountThreshold = parsed.value
  else:
    result.addDiagnostic(lineNo, "unknown dry key " & key)

proc registerDrySections*() {.raises: [].} =
  registerSection(SectionHandler(
    name: "dry",
    parse: handleDry,
    isArray: false,
    informational: false
  ))

{.pop.}
