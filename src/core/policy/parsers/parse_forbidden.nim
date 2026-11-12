import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## Parser module for forbidden_calls, forbidden_assignments, allowed_assignment_owners,
## forbidden_call_policies, forbidden_pragmas, forbidden_call_patterns sections.

import std/strutils
import std/tables
import core/policy/section_parsers
import core/policy/parse_helpers
import core/policy/architecture_policy_types

func handleForbiddenCalls(
  result: var ArchitecturePolicyParseResult;
  key: string; value: string; lineNo: int
) {.raises: [].} =
  # Parse inline object format: { owner = "...", allowedCallers = [...] }
  let ownerStart = value.find("owner = \"")
  let callersStart = value.find("allowedCallers = [")
  if ownerStart >= 0:
    let ownerQuoteStart = ownerStart + 9
    let ownerQuoteEnd = value.find("\"", ownerQuoteStart)
    let ownerVal = if ownerQuoteEnd >= 0: value[ownerQuoteStart ..< ownerQuoteEnd] else: ""
    var callers: seq[string] = @[]
    if callersStart >= 0:
      let callersBracketStart = callersStart + 17
      let callersBracketEnd = value.find("]", callersBracketStart)
      if callersBracketEnd >= 0:
        let callersStr = value[callersBracketStart ..< callersBracketEnd]
        let parsed = parseStringArray("[" & callersStr & "]")
        if parsed.ok: callers = parsed.values
    result.policy.forbiddenCalls[key] = callers
    discard ownerVal
  else:
    # Fallback to array format
    let parsed = parseStringArray(value)
    if parsed.ok:
      result.policy.forbiddenCalls[key] = parsed.values
    else:
      result.addDiagnostic(lineNo, "expected { owner = \"...\", allowedCallers = [...] } for forbidden_calls." & key)

func handleForbiddenCallPolicies(
  result: var ArchitecturePolicyParseResult;
  key: string; value: string; lineNo: int
) {.raises: [].} =
  discard lineNo
  # Parse inline object format: { ownerRole = "...", allowedCallers = [...] }
  let roleStart = value.find("ownerRole = \"")
  let callersStart = value.find("allowedCallers = [")
  var ownerRole = ""
  var allowedCallers: seq[string] = @[]
  if roleStart >= 0:
    let quoteStart = roleStart + 13
    let quoteEnd = value.find("\"", quoteStart)
    if quoteEnd >= 0:
      ownerRole = value[quoteStart ..< quoteEnd]
  if callersStart >= 0:
    let bracketStart = callersStart + 17
    let bracketEnd = value.find("]", bracketStart)
    if bracketEnd >= 0:
      let inside = value[bracketStart ..< bracketEnd]
      for item in inside.split(','):
        let trimmed = item.strip()
        if trimmed.len > 0:
          allowedCallers.add(trimmed)
  result.policy.forbiddenCallPolicies[key] = ForbiddenCallPolicy(
    calleeName: key,
    ownerRole: ownerRole,
    allowedCallers: allowedCallers)

func handleForbiddenPragmas(
  result: var ArchitecturePolicyParseResult;
  key: string; value: string; lineNo: int
) {.raises: [].} =
  discard lineNo
  # Parse inline object format: { caller_pattern = "...", allowed_callers = [...] }
  let patternStart = value.find("caller_pattern = \"")
  let callersStart = value.find("allowed_callers = [")
  var callerPattern = ""
  var allowedCallers: seq[string] = @[]
  if patternStart >= 0:
    let quoteStart = patternStart + 18
    let quoteEnd = value.find("\"", quoteStart)
    if quoteEnd >= 0:
      callerPattern = value[quoteStart ..< quoteEnd]
  if callersStart >= 0:
    let bracketStart = callersStart + 19
    let bracketEnd = value.find("]", bracketStart)
    if bracketEnd >= 0:
      let inside = value[bracketStart ..< bracketEnd]
      for item in inside.split(','):
        let trimmedItem = item.strip().strip(chars = {'"', '[', ']'}).strip()
        if trimmedItem.len > 0:
          allowedCallers.add(trimmedItem)
  if callerPattern.len > 0 and allowedCallers.len > 0:
    result.policy.forbiddenPragmaPatterns[key] = ForbiddenPragmaPattern(
      pragmaName: key,
      callerPattern: callerPattern,
      allowedCallers: allowedCallers)

proc registerForbiddenSections*() {.raises: [].} =
  registerSection(SectionHandler(
    name: "forbidden_calls",
    parse: handleForbiddenCalls,
    isArray: false,
    informational: false
  ))
  registerSection(SectionHandler(
    name: "forbidden_assignments",
    parse: nil,
    isArray: true,
    informational: false
  ))
  registerSection(SectionHandler(
    name: "allowed_assignment_owners",
    parse: nil,
    isArray: true,
    informational: false
  ))
  registerSection(SectionHandler(
    name: "forbidden_call_policies",
    parse: handleForbiddenCallPolicies,
    isArray: false,
    informational: false
  ))
  registerSection(SectionHandler(
    name: "forbidden_pragmas",
    parse: handleForbiddenPragmas,
    isArray: false,
    informational: false
  ))
  registerSection(SectionHandler(
    name: "forbidden_call_patterns",
    parse: nil,
    isArray: false,
    informational: true
  ))

{.pop.}
