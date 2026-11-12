import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}
## Refactor Executor — executes RefactorTasks produced by the sieve→refactor bridge.
## S6 of the Sieve Refactoring Trigger plan.
##
## Maps SieveRuleKind to vulnerability kind strings and delegates
## to the refactoring engine. Wraps exceptions to maintain {.raises: [].}.

import core/types/refactor_task_types   # RefactorTask, RefactorResult, RefactorStatus, EscalationReason, SieveRuleKind
import core/types/obligation_evidence   # emptyEvidence, withLayer, leFailedUnknown
import core/diagnostics/refactoring_engine  # applyRefactoringTemplate
import core/results                      # Result type for z3ExecPersistent return
import verification/solver/z3_pool       # z3ExecPersistent (Phase A.4: Z3 model extraction)

proc ruleKindToVulnKind*(rule: SieveRuleKind): string {.raises: [].} =
  case rule
  of srkTopology: "vkGhostUpdate"
  of srkAstAnalysis: "vkNullPointerDereference"
  of srkUnsatCore: "vkBufferOverflow"
  of srkIoBoundary: "vkDeadlockRaceCondition"

proc executeRefactorTask*(
  task: RefactorTask
): RefactorResult {.raises: [].} =
  ## Execute a single refactor task, returning the result.
  case task.strategy
  of stratStructuralAST:
    let vulnKind = ruleKindToVulnKind(task.dominantRule)
    ## Phase A.4: Provide z3ModelQuery closure for Z3 model extraction.
    ## Wraps z3ExecPersistent to return raw Z3 output (including counterexample models).
    let z3ModelQuery = proc(query: string): string {.closure, gcsafe, raises: [CatchableError].} =
      var cd, td: string
      let res = z3ExecPersistent(query, timeoutMs = 30_000,
        canonicalEnvelopeDigest = cd, transportPayloadDigest = td)
      if res.isErr:
        raise newException(CatchableError, res.error())
      res.get()
    try:
      result = applyRefactoringTemplate(task.sourceCode, vulnKind, z3ModelQuery = z3ModelQuery)
    except CatchableError as e:
      result = RefactorResult(
        status: rsEscalated,
        escalateReason: erEnginePanic,
        contextLog: e.msg & "\n" & getStackTrace(),
        evidence: emptyEvidence().withLayer("Exception", leFailedUnknown)
      )
  of stratInvariantInference:
    ## Phase 2: invariant_pipeline removed during shadow merge.
    ## Fallback to static refactoring templates.
    let vulnKind = ruleKindToVulnKind(task.dominantRule)
    try:
      result = applyRefactoringTemplate(task.sourceCode, vulnKind)
    except CatchableError as e:
      result = RefactorResult(
        status: rsEscalated,
        escalateReason: erEnginePanic,
        contextLog: e.msg & "\n" & getStackTrace(),
        evidence: emptyEvidence().withLayer("Exception", leFailedUnknown)
      )

{.pop.}

