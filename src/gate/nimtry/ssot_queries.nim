import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [].}

## SSOT (Single Source of Truth) queries — type placement enforcement and forbidden assignment detection.

import std/strutils
import std/tables
import std/algorithm
import gate/architecture_ast_facts
import core/gate/architecture_policy
import gate/rule_patterns
import gate/nimtry/nimtry_registry

# ---------------------------------------------------------------------------
# Query checkers
# ---------------------------------------------------------------------------

func checkSsotTypePlacementWrapper*(
  allFacts: seq[ModuleFacts];
  policy: ArchitecturePolicy
): seq[ArchitectureViolationArtifact] {.raises: [].} =
  for facts in allFacts:
    checkSsotTypePlacement(result, policy, facts)

func checkForbiddenAssignmentsWrapper*(
  allFacts: seq[ModuleFacts];
  policy: ArchitecturePolicy
): seq[ArchitectureViolationArtifact] {.raises: [].} =
  for facts in allFacts:
    checkForbiddenAssignments(result, policy, facts)

func checkRatioOwnerWrapper*(
  allFacts: seq[ModuleFacts];
  policy: ArchitecturePolicy
): seq[ArchitectureViolationArtifact] {.raises: [].} =
  for facts in allFacts:
    checkRatioOwnerViolations(result, policy, facts)

func registerSsotQueries*(queries: var seq[NimtryQuery]) {.raises: [].} =
  # ── SSOT queries ─────────────────────────────────────────────────────
  # SSOT: Type placement enforcement (from core_rules)
  queries.add(NimtryQuery(
    name: "ssot-type-placement",
    rule: "SSOT",
    severity: "error",
    taxonomy: buildRule,
    checker: checkSsotTypePlacementWrapper
  ))

  # SSOT: Forbidden assignment detection (from core_rules)
  queries.add(NimtryQuery(
    name: "ssot-forbidden-assignments",
    rule: "SSOT",
    severity: "error",
    taxonomy: buildRule,
    checker: checkForbiddenAssignmentsWrapper
  ))

  # SSOT: Ratio construction ownership (no ad-hoc verified/total math in CLI)
  queries.add(NimtryQuery(
    name: "ssot-ratio-owner",
    rule: "SSOT",
    severity: "error",
    taxonomy: buildRule,
    checker: checkRatioOwnerWrapper
  ))

  # SSOT: Type duplication detection across modules
  queries.add(NimtryQuery(
    name: "ssot-type-duplication",
    rule: "SSOT",
    severity: "warning",
    taxonomy: buildRule,
    checker: proc(allFacts: seq[ModuleFacts]; policy: ArchitecturePolicy): seq[ArchitectureViolationArtifact] {.raises: [].} =
      # Collect all type definitions across modules
      var typeToFiles: Table[string, seq[string]]
      for m in allFacts:
        for td in m.typeDefs:
          let key = td.name
          var acc = typeToFiles.getOrDefault(key)
          if m.path notin acc:
            acc.add(m.path)
          typeToFiles[key] = acc
      # Report types defined in 2+ files
      # NOTE: fileList must be SORTED before fingerprinting — violation
      # fingerprints use files[0], and Table iteration order is
      # non-deterministic (cache presence changes module processing order).
      # Unsorted lists made the same violation look "new" on fresh-CI vs
      # cached-local (DEBT: CI check-arch 43 false-new SSOT failures).
      for typeName, fileList in typeToFiles:
        if fileList.len > 1:
          var sortedFiles = fileList
          algorithm.sort(sortedFiles)
          result.add(ArchitectureViolationArtifact(
            rule: "SSOT-type-duplication",
            detail: "Type '" & typeName & "' defined in " & $sortedFiles.len & " files: " & sortedFiles.join(", "),
            files: sortedFiles,
            severity: "warning",
          ))
  ))


{.pop.}
