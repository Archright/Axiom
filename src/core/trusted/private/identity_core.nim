import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
import core/trusted/axiom_pragmas

## C19 — Identity Core: shared primitive types used across identity layers.
##
## This module contains ONLY types needed by more than one identity layer
## or by real consumers. It is NOT a junk drawer.

type
  RelationId* {.axiomDecision(
    id = "DECISION-0601",
    reason = "Primitive nominal type for relation identity shared by canonical and evidence layers",
    adr = "docs/spec/cfg_contract_specification.md",
    introduced = "v37").} = distinct string

func `==`*(a, b: RelationId): bool {.borrow.}

{.pop.}