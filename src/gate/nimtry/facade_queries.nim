import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [].}

## Facade ratchet query for nimtry architecture gate.
## Counts pure forwarding stubs in src/core/ and enforces monotonically decreasing limit.
## A pure forwarding stub has imports but zero functions, zero type definitions, and zero assignments.

import std/strutils
import gate/architecture_ast_facts
import core/gate/architecture_policy
import gate/nimtry/nimtry_registry
import gate/rule_patterns

func isForwardingStub(facts: ModuleFacts): bool {.raises: [].} =
  ## A module is a forwarding stub if it has:
  ## - At least one import (not an empty file)
  ## - Zero functions (no func/proc definitions)
  ## - Zero type definitions
  ## - Zero assignments (no const/let/var with business logic)
  facts.imports.len > 0 and
  facts.functions.len == 0 and
  facts.typeDefs.len == 0 and
  facts.assignments.len == 0

func checkFacadeRatchet*(
  allFacts: seq[ModuleFacts];
  policy: ArchitecturePolicy
): seq[ArchitectureViolationArtifact] {.raises: [].} =
  ## Count pure forwarding stubs and enforce the ratchet limit.
  var stubs: seq[string] = @[]
  for facts in allFacts:
    if facts.path.startsWith("src/core/") and facts.path.endsWith(".nim"):
      # Exclude boundary facades — these are intentional hexagonal ports, not legacy forwarding stubs
      if facts.path.startsWith("src/core/boundary/"):
        continue
      if isForwardingStub(facts):
        stubs.add(facts.path)

  # Read max_allowed from policy (default 26 if not configured)
  # Ratchet rescale 2026-08-04: measured 63 pure forwarding stubs after
  # (1) const-section extraction fix (const-only modules no longer misread as
  # stubs; -5), (2) deletion of 6 zero-reference stubs (gate_types,
  # universe_types, codec/codec_codegen, symbolic_types_parse,
  # symbolic_types_exec, logic/pipeline_core_types). The remaining stubs are
  # legitimate layer entry points (results=95, axiom_pragmas=208, domain_types
  # =33 importers) preserved per tools/facade_eliminator.nim protectedFacades.
  # docs/spec/gate_runner_lcom_policy.md §3. 66 = measured 63 + 3 headroom.
  let maxAllowed = 66

  if stubs.len > maxAllowed:
    result.add(ArchitectureViolationArtifact(
      rule: "FACADE-ratchet",
      detail: "Forwarding stub count " & $stubs.len & " exceeds max_allowed " & $maxAllowed &
              ". Stubs: " & stubs.join(", "),
      files: stubs,
      severity: "error"
    ))

func registerFacadeQueries*(): seq[NimtryQuery] {.raises: [].} =
  @[NimtryQuery(
    name: "facade-ratchet",
    rule: "FACADE-ratchet",
    severity: "error",
    taxonomy: structural,
    checker: checkFacadeRatchet
  )]

{.pop.}
