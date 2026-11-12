import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## Helper parsing functions for architecture policy.
##
## Extracted from architecture_policy_parts/architecture_policy_part1.nim
## as a standalone importable module.
##
## Refactored (Phase 3.1/3.2): Giant case statement replaced with
## registry-based dispatch via section_parsers.nim.

import std/strutils
import std/sets
import core/policy/architecture_policy_types
import core/policy/parse_helpers

# Re-export parse_helpers for backward compatibility
export parse_helpers

# Import registry hub and all parser modules
import core/policy/section_parsers
import core/policy/parsers/parse_informational
import core/policy/parsers/parse_meta
import core/policy/parsers/parse_dry
import core/policy/parsers/parse_surface_area
import core/policy/parsers/parse_cohesion
import core/policy/parsers/parse_forbidden
import core/policy/parsers/parse_canonical
import core/policy/parsers/parse_interfaces
import core/policy/parsers/parse_layers
import core/policy/parsers/parse_ocp
import core/policy/parsers/parse_impure_procedures_whitelist

# Register all section handlers at module initialization
registerInformationalSections()
registerMetaSections()
registerDrySections()
registerSurfaceAreaSections()
registerCohesionSections()
registerForbiddenSections()
registerCanonicalSections()
registerInterfaceSections()
registerLayerSections()
registerOcpSections()
registerImpureProceduresWhitelistSection()

# Validate that all known sections are registered (runtime check).
# Note: static: doAssert cannot be used because sectionRegistry is
# populated at module initialization time, not compile time.
doAssert validateRegistry(), "section registry is incomplete at startup"

proc parseAssignmentLine*(
  result: var ArchitecturePolicyParseResult;
  seenKeys: var HashSet[string];
  section: string;
  rawLine: string;
  lineNo: int
) {.raises: [].} =
  # Look up registered handler
  let handler = getHandler(section)
  if handler.name.len == 0:
    result.addDiagnostic(lineNo, "unsupported section " & section)
    return
  if handler.informational:
    return

  # Common key=value parsing
  let eqIndex = rawLine.find('=')
  if eqIndex < 0:
    result.addDiagnostic(lineNo, "expected key = value assignment")
    return
  let key = quoteTrim(rawLine[0 ..< eqIndex]).strip()
  let value = rawLine[eqIndex + 1 .. ^1].strip()
  if key.len == 0:
    result.addDiagnostic(lineNo, "empty key")
    return
  let fullKey = section & "." & key
  if fullKey in seenKeys:
    result.addDiagnostic(lineNo, "duplicate key " & fullKey)
    return
  seenKeys.incl(fullKey)

  # Array sections — handle uniformly
  if handler.isArray:
    let parsed = parseStringArray(value)
    if not parsed.ok:
      result.addDiagnostic(lineNo, "expected string array for " & fullKey)
      return
    if section == "layer":
      for item in parsed.values:
        if not isValidLayerGlob(item):
          result.addDiagnostic(lineNo, "malformed glob " & item & " in " & fullKey)
    result.putArray(section, key, parsed.values)
    return

  # Dispatch to registered handler
  handler.parse(result, key, value, lineNo)

{.pop.}
