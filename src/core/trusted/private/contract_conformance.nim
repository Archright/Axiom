import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
import std/sequtils
import core/trusted/axiom_pragmas
import core/trusted/verification_model_types
import core/trusted/private/semantic_contract
import core/trusted/private/transition_formula_builder

func conformsKernelInstance*(contract: SemanticContract; kernel: TransitionFormulaBuilder; model: VerificationModel; freshBase: var int): bool {.axiomDecision(
      id = "DECISION-0501",
      reason = "L1 blocking: kernel must conform to normative contract; a divergence is a soundness bug",
      adr = "docs/spec/cfg_contract_specification.md",
      introduced = "v32"), raises: [].} =
  for tr in model.semantic.transitions:
    let f = buildTransitionFormula(kernel, tr, freshBase)
    if not contractSatisfiesAllLaws(contract, f, kernel.stateNames):
      return false
  true

func verifyContractKernelConformance*(model: VerificationModel; contract: SemanticContract = makeSemanticContract()): bool {.axiomDecision(
      id = "DECISION-0502",
      reason = "L1 blocking: kernel must conform to normative contract; a divergence is a soundness bug",
      adr = "docs/spec/cfg_contract_specification.md",
      introduced = "v32"), raises: [].} =
  let kernel = newTransitionFormulaBuilder(model.semantic.states.mapIt(it.name))
  var freshBase = 0
  conformsKernelInstance(contract, kernel, model, freshBase)

{.pop.}