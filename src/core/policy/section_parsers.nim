import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## Section parser registry hub.
##
## Provides a table-driven dispatch system for architecture policy section parsing.
## Individual parser modules register their handlers via `registerSection`.
## The main `parseAssignmentLine` in architecture_policy_part1.nim uses
## `getHandler` to look up the registered handler for each section.

import std/tables
import core/policy/architecture_policy_types

type
  SectionParseProc* = proc(
    result: var ArchitecturePolicyParseResult;
    key: string;
    value: string;
    lineNo: int
  ) {.noSideEffect, raises: [].}

  SectionHandler* = object
    name*: string
    parse*: SectionParseProc
    isArray*: bool       ## true = uses parseStringArray + putArray dispatch
    informational*: bool ## true = discard all lines without validation

var sectionRegistry* = initTable[string, SectionHandler]()

proc registerSection*(handler: SectionHandler) {.raises: [].} =
  sectionRegistry[handler.name] = handler

proc getHandler*(section: string): SectionHandler {.raises: [].} =
  ## Lookup section handler from registry. Read-only after module init.
  sectionRegistry.getOrDefault(section, SectionHandler(name: ""))

proc isRegistered*(section: string): bool {.raises: [].} =
  ## Check if section is registered. Read-only after module init.
  section in sectionRegistry

proc validateRegistry*(): bool {.raises: [].} =
  ## Runtime validation: every known section must be registered.
  ## Called at module initialization in architecture_policy_part1.nim.
  ## Cannot use static: because sectionRegistry is populated at runtime.
  const knownSections = [
    "meta", "layer", "layer_edges", "module_roles", "ssot_types",
    "forbidden_calls", "forbidden_assignments", "allowed_assignment_owners",
    "dry", "surface_area", "canonical_computations", "interfaces", "opaque_types", "cohesion",
    "layer_limits", "external_packages", "forbidden_call_policies", "generated_modules", "module_overrides",
    "lcom_overrides", "tcc_overrides", "forbidden_call_patterns",
    "ocp_registries", "ocp_overrides", "forbidden_pragmas",
    "legacy_violations", "effect_hints", "effect_hints.functions",
    "debt_ceiling", "debt_metrics", "impure_procedures_whitelist",
    "gcsafe_approvals", "dag_enforcement", "facade_ratchet"
  ]
  for s in knownSections:
    if s notin sectionRegistry:
      return false
  true

{.pop.}
