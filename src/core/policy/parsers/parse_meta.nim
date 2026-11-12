import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## Parser module for meta, ssot_types, external_packages, generated_modules sections.

import std/tables
import core/policy/section_parsers
import core/policy/parse_helpers
import core/policy/architecture_policy_types

func handleMeta(
  result: var ArchitecturePolicyParseResult;
  key: string; value: string; lineNo: int
) {.raises: [].} =
  if key == "version":
    result.policy.version = quoteTrim(value)
  elif key == "description":
    discard  # description is informational, not validated
  else:
    result.addDiagnostic(lineNo, "unknown meta key " & key)

func handleSsotTypes(
  result: var ArchitecturePolicyParseResult;
  key: string; value: string; lineNo: int
) {.raises: [].} =
  discard lineNo
  result.policy.ssotTypes[key] = quoteTrim(value)

func handleExternalPackages(
  result: var ArchitecturePolicyParseResult;
  key: string; value: string; lineNo: int
) {.raises: [].} =
  discard key
  let parsed = parseStringArray(value)
  if parsed.ok:
    result.policy.externalPackagePrefixes = sortedStrings(parsed.values)
  else:
    result.addDiagnostic(lineNo, "expected string array for external_packages")

func handleGeneratedModules(
  result: var ArchitecturePolicyParseResult;
  key: string; value: string; lineNo: int
) {.raises: [].} =
  discard lineNo
  result.policy.generatedModules[key] = quoteTrim(value)

proc registerMetaSections*() {.raises: [].} =
  registerSection(SectionHandler(
    name: "meta",
    parse: handleMeta,
    isArray: false,
    informational: false
  ))
  registerSection(SectionHandler(
    name: "ssot_types",
    parse: handleSsotTypes,
    isArray: false,
    informational: false
  ))
  registerSection(SectionHandler(
    name: "external_packages",
    parse: handleExternalPackages,
    isArray: false,
    informational: false
  ))
  registerSection(SectionHandler(
    name: "generated_modules",
    parse: handleGeneratedModules,
    isArray: false,
    informational: false
  ))
  registerSection(SectionHandler(
    name: "time_bounded_debt_500line",
    parse: nil,
    isArray: false,
    informational: true
  ))
  registerSection(SectionHandler(
    name: "memory_policy_markers",
    parse: nil,
    isArray: false,
    informational: true
  ))

{.pop.}
