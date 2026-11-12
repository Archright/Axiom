import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## Parser module for ocp_registries, ocp_overrides sections.
## Both are informational — handled by solid_queries.nim via direct lock-file read.

import core/policy/section_parsers

proc registerOcpSections*() {.raises: [].} =
  registerSection(SectionHandler(
    name: "ocp_registries",
    parse: nil,
    isArray: false,
    informational: true
  ))
  registerSection(SectionHandler(
    name: "ocp_overrides",
    parse: nil,
    isArray: false,
    informational: true
  ))

{.pop.}
