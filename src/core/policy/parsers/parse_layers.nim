import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## Parser module for layer, layer_edges, module_roles sections.
## layer has a custom parser (accepts both array and single-value).
## layer_edges and module_roles are isArray sections.

import core/policy/section_parsers
import core/policy/parse_helpers
import core/policy/architecture_policy_types

func parseLayerSection*(
  result: var ArchitecturePolicyParseResult;
  key: string; value: string; lineNo: int
) {.raises: [].} =
  ## layer section: accepts both ["a", "b"] array and single "value" format.
  let parsed = parseStringArray(value)
  if parsed.ok:
    for item in parsed.values:
      if not isValidLayerGlob(item):
        result.addDiagnostic(lineNo, "malformed glob " & item & " in layer." & key)
    result.putArray("layer", key, parsed.values)
  else:
    result.putArray("layer", key, @[quoteTrim(value)])

proc registerLayerSections*() {.raises: [].} =
  ## Register layer-related sections.
  registerSection(SectionHandler(
    name: "layer",
    parse: parseLayerSection,
    isArray: false,
    informational: false
  ))
  registerSection(SectionHandler(
    name: "layer_edges",
    parse: nil,
    isArray: true,
    informational: false
  ))
  registerSection(SectionHandler(
    name: "module_roles",
    parse: nil,
    isArray: true,
    informational: false
  ))

{.pop.}
