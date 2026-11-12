import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}
## Sieve→Refactor Bridge — converts sieve verdicts into refactor tasks.
## S2 of the Sieve Refactoring Trigger plan.
##
## Maps Subjective Logic opinions to refactoring strategies and
## bridges sieve rule results to refactor task types.

import std/json
import std/options
import std/sets
import core/sorter/sorter_core_index_base  # SorterNodeId
import core/types/refactor_task_types      # RefactorTask, RefactorStrategy, SieveRuleKind
import core/types/obligation_evidence      # ObligationEvidence, Z3Model, DerivationGraph
import core/types/hubs/refactoring_hub     # RefactoringTemplate
import sieve/sieve_types                   # SieveVerdict, RuleResult, SieveSourceKind

proc selectStrategy*(belief, uncertainty: float): RefactorStrategy {.raises: [].} =
  ## Select refactoring strategy based on Subjective Logic opinion.
  ## b > u → stratStructuralAST (deterministic)
  ## u >= b → stratInvariantInference (AI-based, Phase 2)
  if belief > uncertainty:
    stratStructuralAST
  else:
    stratInvariantInference

proc mapRuleKind*(ruleSource: SieveSourceKind): SieveRuleKind {.raises: [].} =
  ## Map sieve rule source kind to SieveRuleKind.
  ## Adjusted from string-based to enum-based since RuleResult.source
  ## is SieveSourceKind, not string.
  case ruleSource
  of rsTopology: srkTopology
  of rsAstAnalysis: srkAstAnalysis
  of rsUnsatCore: srkUnsatCore
  of rsIOEffect: srkIoBoundary

proc templatesForRuleKind*(rule: SieveRuleKind): seq[RefactoringTemplate] {.raises: [].} =
  ## Map SieveRuleKind to candidate refactoring templates.
  ## Each rule kind maps to patterns whose preconditions it is most
  ## likely to satisfy, based on the evidence source semantics:
  ##
  ##   srkTopology    — dependency depth, coupling → composition/isolation
  ##   srkAstAnalysis — structural side effects, nonlinear ops → purity/linearization
  ##   srkUnsatCore   — Z3 mathematical evidence → linearization/extraction
  ##   srkIoBoundary  — filesystem effects → interface isolation, invariants
  case rule
  of srkTopology:
    @[
      RefactoringTemplate(
        signal: rskDeepDependency,
        pattern: rpkInsertCompositionNode,
        description: "Insert intermediate composition node to reduce dependency depth",
        nimHint: "Split call chain into intermediate helpers",
        priority: 8
      ),
      RefactoringTemplate(
        signal: rskHighCoupling,
        pattern: rpkIsolateInterface,
        description: "Separate boundary contract to reduce coupling",
        nimHint: "Extract interface boundary from coupled module",
        priority: 7
      )
    ]
  of srkAstAnalysis:
    @[
      RefactoringTemplate(
        signal: rskQuantifierExcess,
        pattern: rpkExtractPureFunction,
        description: "Extract pure computation from quantified scope",
        nimHint: "Pull side-effect-free logic into a standalone func",
        priority: 9
      ),
      RefactoringTemplate(
        signal: rskNonLinearArithmetic,
        pattern: rpkLinearizeVariables,
        description: "Replace nonlinear constraints with linear auxiliary variables",
        nimHint: "Introduce aux vars to linearize nonlinear terms",
        priority: 8
      )
    ]
  of srkUnsatCore:
    @[
      RefactoringTemplate(
        signal: rskNonLinearArithmetic,
        pattern: rpkLinearizeVariables,
        description: "Linearize variables flagged by unsat core analysis",
        nimHint: "Substitute linear aux vars for nonlinear Z3 counterexample terms",
        priority: 9
      ),
      RefactoringTemplate(
        signal: rskQuantifierExcess,
        pattern: rpkExtractPureFunction,
        description: "Extract pure function to reduce quantifier scope",
        nimHint: "Narrow quantified region by extracting pure core",
        priority: 7
      )
    ]
  of srkIoBoundary:
    @[
      RefactoringTemplate(
        signal: rskHighCoupling,
        pattern: rpkIsolateInterface,
        description: "Isolate I/O boundary to separate effect from logic",
        nimHint: "Move I/O calls behind an interface boundary proc",
        priority: 9
      ),
      RefactoringTemplate(
        signal: rskMissingLoopInvariant,
        pattern: rpkAddLoopInvariant,
        description: "Add loop invariant to stabilize I/O loop verification",
        nimHint: "Annotate loop with invariant covering I/O state",
        priority: 6
      ),
      RefactoringTemplate(
        signal: rskMissingDecreaseMeasure,
        pattern: rpkAddDecreaseMeasure,
        description: "Add termination measure for recursive I/O processing",
        nimHint: "Define well-founded measure on recursive I/O structure",
        priority: 6
      )
    ]

proc sieveVerdictToRefactorTask*(
  nodeId: SorterNodeId;
  modulePath, functionName, sourceCode: string;
  sieveVerdict: SieveVerdict;
  maxAttempts: int = 3
): RefactorTask {.raises: [].} =
  ## Convert a sieve PRE-SIEVED verdict into a RefactorTask.
  let strategy = selectStrategy(sieveVerdict.combinedOpinion.b, sieveVerdict.combinedOpinion.u)

  # Find dominant rule from applied rules
  var dominantRule = srkTopology
  var warnings: seq[string] = @[]
  for rule in sieveVerdict.appliedRules:
    warnings.add(rule.verdict)
    dominantRule = mapRuleKind(rule.source)

  # Populate templates from dominant rule kind so the executor and
  # pattern guard have candidates to evaluate against preconditions.
  let templates = templatesForRuleKind(dominantRule)

  RefactorTask(
    nodeId: nodeId,
    modulePath: modulePath,
    functionName: functionName,
    sourceCode: sourceCode,
    currentEntropy: sieveVerdict.probabilityScore,
    strategy: strategy,
    dominantRule: dominantRule,
    ruleWarnings: warnings,
    templates: templates,
    attempt: 0,
    maxAttempts: maxAttempts,
    belief: sieveVerdict.combinedOpinion.b,
    uncertainty: sieveVerdict.combinedOpinion.u
  )

func bridgeToObligation*(metadata: JsonNode; derivation: string; unsatVars: seq[string]): ObligationEvidence {.raises: [].} =
  ## Bridge sieve metadata, derivation tree, and unsat core vars
  ## into a structured ObligationEvidence record.
  ObligationEvidence(
    z3Model: none(Z3Model),
    leanGoals: @[],
    unsatCoreVars: unsatVars,
    smtlib2Query: "",
    layerTrace: @[],
    derivationGraph: DerivationGraph(nodes: initHashSet[string](), edges: initHashSet[(string, string)]()),
    solverMeta: if metadata.isNil: newJObject() else: metadata,
    stepCount: 0,
    elapsedMs: 0
  )

{.pop.}

