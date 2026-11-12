import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [].}

## Nimtry unified query registry hub — dispatches all nimtry queries.
##
## Query order: SoC → SOLID → SSOT → DRY → SAFETY → HYGIENE

import gate/nimtry/nimtry_registry
import gate/rule_patterns
import gate/nimtry/call_graph
import gate/nimtry/interface_auditor
import gate/nimtry/soc_queries
import gate/nimtry/solid_queries
import gate/nimtry/ssot_queries
import gate/nimtry/dry_queries
import gate/nimtry/forbidden_patterns
import gate/nimtry/purity_queries
import gate/nimtry/test_hygiene
import gate/nimtry/feature_universe
import gate/nimtry/effect_queries
import gate/nimtry/facade_queries
from core/trusted/axiom_pragmas_lite import axiomEffect, AxiomEffectKind, IOEffect, Pure
from core/trusted/effect_bridge import AxiomIOEffect

export rule_patterns.ArchitectureViolationArtifact

func registerNimtryQueries*(): seq[NimtryQuery] {.raises: [].} =
  registerSocQueries(result)
  registerSolidQueries(result)
  registerSsotQueries(result)
  registerDryQueries(result)
  registerSafetyQueries(result)
  registerPurityQueries(result)
  registerHygieneQueries(result)
  registerFeatureQueries(result)
  for q in registerEffectQueries():
    result.add(q)
  for q in registerFacadeQueries():
    result.add(q)

proc runAllQueries*(
  allFacts: seq[ModuleFacts];
  policy: ArchitecturePolicy
): seq[ArchitectureViolationArtifact] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Run all registered nimtry queries and aggregate violations.
  let queries = registerNimtryQueries()
  for query in queries:
    let queryViolations = query.checker(allFacts, policy)
    for v in queryViolations:
      result.add(ArchitectureViolationArtifact(
        rule: v.rule,
        detail: "[" & query.name & "] " & v.detail,
        files: v.files,
        severity: query.severity))

{.pop.}
