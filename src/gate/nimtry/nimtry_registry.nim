import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [].}

## Nimtry shared types — central hub for query modules.
## Extracted from nimtry_query.nim to break circular imports
## and enable module-level query registration per AGENTS.md §1.3a.

import gate/architecture_ast_facts
export architecture_ast_facts.ModuleFacts

import core/boundary/policy_types_boundary
export policy_types_boundary.ArchitecturePolicy

import gate/rule_patterns

type
  RuleTaxonomy* {.pure.} = enum
    ## Canonical rule taxonomy for nimtry findings (DEBT#274).
    ## Each finding MUST be categorized as exactly one:
    buildRule   = "build-rule"    ## Build/policy/invariant rules (SSOT, forbidden patterns)
    procPurity  = "proc-purity"   ## Proc-to-func conversion, effect/purity analysis
    structural  = "structural"    ## SoC/layer, SOLID, DRY, facade, test hygiene, feature universe

  CheckerProc* = proc(allFacts: seq[ModuleFacts]; policy: ArchitecturePolicy): seq[ArchitectureViolationArtifact] {.raises: [].}

  NimtryQuery* = object
    name*: string
    rule*: string
    severity*: string
    taxonomy*: RuleTaxonomy  ## DEBT#274: canonical rule taxonomy category
    checker*: CheckerProc

{.pop.}
