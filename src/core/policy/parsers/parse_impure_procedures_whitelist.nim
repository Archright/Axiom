import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## Parser module for impure_procedures_whitelist section.

import core/policy/section_parsers

proc registerImpureProceduresWhitelistSection*() {.raises: [].} =
  registerSection(SectionHandler(
    name: "impure_procedures_whitelist",
    parse: nil,
    isArray: true,
    informational: false
  ))

{.pop.}
