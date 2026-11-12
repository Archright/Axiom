import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## Parser module for all informational sections.
## These sections contain multi-line arrays/objects that cannot be parsed as
## simple key = value assignments. All lines are discarded without validation.

import core/policy/section_parsers

proc registerInformationalSections*() {.raises: [].} =
  ## Register all informational sections (informational = true).
  for sectionName in [
    "effect_hints", "effect_hints.functions", "debt_ceiling",
    "debt_metrics", "impure_procedures_whitelist",
    "gcsafe_approvals", "dag_enforcement", "legacy_violations",
    "facade_ratchet", "forbidden_call_patterns"
  ]:
    registerSection(SectionHandler(
      name: sectionName,
      parse: nil,
      isArray: false,
      informational: true
    ))

{.pop.}
