import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## Heal Hint Manager
## Pure state automata for hint validation lifecycle.
## NO I/O. NO SMT. NO Lean. NO file system access.

import std/options
import core/verified_axioms/verified_axioms_catalog_part1
import core/verified_axioms/verified_axioms_core
import core/verified_axioms/verified_axioms
import core/types/heal_types
import ../../core/trusted/axiom_pragmas

## axiom-smt: (assert ast_parse_failed_isolated)
## axiom-lean: ast_parse_failed_isolated
func acceptVerifiedAxiom*(manager: var HintManager; logLines: var seq[string]) {.axiomTryImpl.} =
  let verifiedAxiomMapping = axiomMatchesLeanProposition(manager.hint.leanProposition)
  manager.isVerifiedAxiom = verifiedAxiomMapping.isSome
  if manager.isVerifiedAxiom:
    let mapping = verifiedAxiomMapping.get()
    manager.verifiedAxiomId = mapping.axiomId
    manager.verifiedAxiomVersion = mapping.axiomVersion
    manager.verifiedAxiomHash = computeAxiomHash(mapping.axiomId, mapping.nimSignature, mapping.leanSignature)
    logLines.add("[VerifiedAxiom] Approved axiom trust layer accepted: " & manager.verifiedAxiomId)

{.pop.}
