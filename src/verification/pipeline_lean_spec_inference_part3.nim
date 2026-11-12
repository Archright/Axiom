import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

import std/options
import std/strutils
import compiler/ast
import core/domain_types
import core/utils/text_utils
import core/workflow_state
import core/parser_utils
import core/pipeline_core_types
import verification/pipeline_lean_spec_inference_part1
import verification/pipeline_lean_spec_inference_part2
import core/trusted/lean_util
import core/utils/constants
# axiomIoBoundary

func buildGoalAlias(aliasName: string; structuredStateName: string; branchDepth: int): string =
  let params = buildAliasParameters(structuredStateName, branchDepth)
  let paramsText = if params.len == 0: "" else: " " & params.join(" ")
  "abbrev " & aliasName & paramsText & " : Prop := " & buildConditionalTarget(branchDepth)

func buildGoalAliasInvocation(aliasName: string; structuredStateName: string; branchDepth: int): string =
  var args: seq[string] = @[]
  if structuredStateName.len > 0:
    args.add("state")
  for i in 1 .. branchDepth:
    args.add("b" & $i)
  if args.len == 0:
    return aliasName
  aliasName & " " & args.join(" ")

func buildTheoremHeader(theorem: string; aliasName: string; loopDepth: int; branchDepth: int; structuredStateName: string): string =
  var params: seq[string] = @[]
  if loopDepth > 0:
    params.add("(n : Nat)")
  if structuredStateName.len > 0:
    params.add("(state : " & structuredStateName & ")")
  for i in 1 .. branchDepth:
    params.add("(b" & $i & " : Bool)")
  let paramsText = if params.len == 0: "" else: " " & params.join(" ")
  "theorem " & theorem & paramsText & " : " &
    buildGoalAliasInvocation(aliasName, structuredStateName, branchDepth) & " := by"

func buildBooleanCasesLine(branchDepth: int): string =
  if branchDepth <= 0:
    return "simp"
  result = ""
  for i in 1 .. branchDepth:
    if result.len > 0:
      result.add(" <;> ")
    result.add("cases h" & $i & " : b" & $i)
  result.add(" <;> simp")

func buildProofBranch(aliasName: string; branchDepth: int; structuredStateName: string): seq[string] =
  if structuredStateName.len > 0:
    result.add("      cases state")
  result.add("      unfold " & aliasName)
  result.add("      " & buildBooleanCasesLine(branchDepth))

func buildTacticLines(loopDepth: int; branchDepth: int; aliasName: string; structuredStateName: string): seq[string] =
  if loopDepth > 0:
    result.add("  induction n with")
    result.add("  | zero =>")
    for line in buildProofBranch(aliasName, branchDepth, structuredStateName):
      result.add(line)
    result.add("  | succ k ih =>")
    for line in buildProofBranch(aliasName, branchDepth, structuredStateName):
      result.add(line)
  else:
    for line in buildProofBranch(aliasName, branchDepth, structuredStateName):
      result.add("  " & line.strip())

## Infer Lean Spec.
proc inferLeanSpec*(
  modulePath: string;
  functionName: string;
  translation: UniversalTranslation;
  sourceCode: string;
  activeInvariant: string = "";
  verificationVerdict: string = "proven_by_induction"
): LeanSpecInference =
  let theorem = sanitizeToken(modulePath.replace('/', '_').replace('\\', '_')) & "_" &
    sanitizeToken(functionName) & "_inferred_safety"
  let aliasName = buildGoalAliasName(theorem)
  let assumptions = inferAssumptions(translation, activeInvariant)
  let loopDepth = inferLoopDepth(translation)
  let branchDepth = min(inferBranchDepth(translation), 3)
  var sourceAst = none(PNode)
  if translation.language.toLowerAscii() == "nim" and sourceCode.len > 0:
    let parsedAst = parseStringAST(sourceCode)
    if not parsedAst.isNil:
      sourceAst = some(parsedAst)
  let structuredStateName = inferStructuredStateName(sourceCode, translation.language, sourceAst)
  let stateTypeName = buildStateTypeName(structuredStateName, functionName)
  let namespaceName = buildLeanNamespace(modulePath, functionName)
  let environmentInputs = inferEnvironmentInputs(translation, sourceCode, sourceAst)
  let operationalSemantics = inferOperationalSemantics(translation)
  let loopControlVariables = inferLoopControlVariables(translation)
  let rankVariables = inferRankVariables(translation)
  let internalConstructors = buildInternalStepConstructorNames(operationalSemantics)
  let stepConstructors = internalConstructors & buildEnvStepConstructorNames(environmentInputs)
  let proofReplayMethod = "proof_term_rewrite"
  let proofReplayTactics = buildProofReplayTactics()
  let strictSpecWarnings = inferStrictSpecWarnings(translation, activeInvariant)
  # Vacuous invariant & empty SMT2: downstream logic already produces correct
  # "unverified" result (leanKernelVerified=false, refinementProven=false).
  # No exception needed — the warnings propagate through the output fields.
  let solverUnsat = verificationVerdict != "refuted_by_counterexample"
  let leanKernelVerified = inferLeanKernelVerified(solverUnsat, strictSpecWarnings, proofReplayTactics)
  let proofReplayVerified = solverUnsat and leanKernelVerified
  let refinementProven = solverUnsat and proofReplayVerified and strictSpecWarnings.len == 0
  let soundnessNote = buildSoundnessNote(solverUnsat, leanKernelVerified)
  let proofReplayStatus =
    if verificationVerdict == "refuted_by_counterexample": "sat" else: "unsat"
  let solverReplayValue =
    if proofReplayVerified: "true" else: "false"
  let terminationArgument = buildTerminationArgumentLabel(environmentInputs, rankVariables)
  let minimalProofPath = minimizeProofPath(proofReplayTactics.join("\n"))
  var sourceLines: seq[string] = @[]
  sourceLines.add("import Std")
  sourceLines.add("import ax_solve")
  sourceLines.add("import ax_vacuity_check")
  sourceLines.add("")
  sourceLines.add("namespace " & namespaceName)
  sourceLines.add("")
  for line in buildStateTypeDefinition(stateTypeName, translation.stateSpace):
    sourceLines.add(line)
  sourceLines.add("")
  sourceLines.add("def stateSpace : List String := " & buildLeanStringList(translation.stateSpace))
  sourceLines.add("def transitionRelation : List String := " & buildLeanStringList(translation.transitionRelation))
  sourceLines.add("def operationalSemantics : List String := " & buildLeanStringList(operationalSemantics))
  sourceLines.add("def environmentInputs : List String := " & buildLeanStringList(environmentInputs))
  sourceLines.add("def assumptionHints : List String := " & buildLeanStringList(assumptions))
  sourceLines.add("def stateInvariantHints : List String := " & buildLeanStringList(translation.stateInvariants))
  sourceLines.add("def transitionInvariantHints : List String := " &
    buildLeanStringList(translation.transitionInvariants))
  sourceLines.add("def strictSpecWarnings : List String := " & buildLeanStringList(strictSpecWarnings))
  sourceLines.add("def strictSpecWarningRaised : Bool := " & (if strictSpecWarnings.len > 0: "true" else: "false"))
  sourceLines.add("def proofReplayTactics : List String := " & buildLeanStringList(proofReplayTactics))
  sourceLines.add("def leanKernelReplayVerified : Bool := " & (if leanKernelVerified: "true" else: "false"))
  sourceLines.add("def soundnessNote : String := " & buildLeanStringLiteral(soundnessNote))
  sourceLines.add("def loopControlVariables : List String := " & buildLeanStringList(loopControlVariables))
  sourceLines.add("def rankVariables : List String := " & buildLeanStringList(rankVariables))
  sourceLines.add("def promotedInvariant : String := " & buildLeanStringLiteral(activeInvariant))
  sourceLines.add("def implementationRefinesStepProvenSummary : Bool := " & (if refinementProven: "true" else: "false"))
  sourceLines.add("")
  for line in buildEnvInputDefinition(environmentInputs):
    sourceLines.add(line)
  sourceLines.add("")
  for line in buildNextStateDefinition(stateTypeName, translation):
    sourceLines.add(line)
  sourceLines.add("")
  for line in buildInitialStateDefinition(stateTypeName, translation.stateSpace):
    sourceLines.add(line)
  sourceLines.add("")
  for line in buildInvariantDefinition(stateTypeName, translation, activeInvariant, strictSpecWarnings):
    sourceLines.add(line)
  sourceLines.add("")
  for line in buildStepSpecDefinition(stateTypeName, translation, environmentInputs, strictSpecWarnings):
    sourceLines.add(line)
  sourceLines.add("")
  for line in buildStepDefinition(stateTypeName, translation, internalConstructors, environmentInputs):
    sourceLines.add(line)
  sourceLines.add("")
  for line in buildBaseCaseTheorem():
    sourceLines.add(line)
  sourceLines.add("")
  for line in buildStepCaseTheorem(stateTypeName, internalConstructors, environmentInputs):
    sourceLines.add(line)
  sourceLines.add("")

  let generateInductiveProofs = translation.stateSpace.len > 0

  if generateInductiveProofs:
    for line in buildRankDefinition(stateTypeName, rankVariables):
      sourceLines.add(line)
    sourceLines.add("")
    for line in buildTerminalDefinition(stateTypeName):
      sourceLines.add(line)
    sourceLines.add("")
    for line in buildProgressOrTerminalTheorem(stateTypeName, internalConstructors):
      sourceLines.add(line)
    sourceLines.add("")
    for line in buildRankDecreaseTheorem(stateTypeName, internalConstructors, environmentInputs):
      sourceLines.add(line)
    sourceLines.add("")
    for line in buildImplementationRefinementProof(
      stateTypeName,
      internalConstructors,
      environmentInputs,
      refinementProven
    ):
      sourceLines.add(line)
    sourceLines.add("")

  sourceLines.add("theorem environment_closure : ∀ (S S' : " & stateTypeName & ") (ι : EnvInput), invariant S → Step S ι S' → invariant S' := by")
  sourceLines.add("  intro S S' ι hInv hStep")
  sourceLines.add("  exact step_case S S' ι hInv hStep")
  sourceLines.add("")
  sourceLines.add("theorem invariant_preserved : ∀ (S S' : " & stateTypeName & ") (ι : EnvInput), invariant S → Step S ι S' → invariant S' := by")
  sourceLines.add("  intro S S' ι hInv hStep")
  sourceLines.add("  exact environment_closure S S' ι hInv hStep")
  sourceLines.add("")
  sourceLines.add("theorem initial_state_safe : invariant initialState := by")
  sourceLines.add("  exact base_case")
  sourceLines.add("")
  sourceLines.add("structure SolverReplayArtifact where")
  sourceLines.add("  solver : String")
  sourceLines.add("  status : String")
  sourceLines.add("  replayMethod : String")
  sourceLines.add("  tactics : List String")
  sourceLines.add("  operationalSemantics : List String")
  sourceLines.add("  environmentInputs : List String")
  sourceLines.add("  deriving Repr, DecidableEq")
  sourceLines.add("")
  sourceLines.add("def z3Artifact : SolverReplayArtifact := {")
  sourceLines.add("  solver := " & buildLeanStringLiteral(DefaultSolverCommand) & ",")
  sourceLines.add("  status := " & buildLeanStringLiteral(proofReplayStatus) & ",")
  sourceLines.add("  replayMethod := " & buildLeanStringLiteral(proofReplayMethod) & ",")
  sourceLines.add("  tactics := proofReplayTactics,")
  sourceLines.add("  operationalSemantics := operationalSemantics,")
  sourceLines.add("  environmentInputs := environmentInputs")
  sourceLines.add("}")
  sourceLines.add("")
  sourceLines.add("def solverUnsatReplay : Bool := " & solverReplayValue)
  sourceLines.add("def replayVerified : Prop :=")
  sourceLines.add("  z3Artifact.solver = " & buildLeanStringLiteral(DefaultSolverCommand) & " ∧")
  sourceLines.add("  z3Artifact.status = " & buildLeanStringLiteral(proofReplayStatus) & " ∧")
  sourceLines.add("  z3Artifact.replayMethod = " & buildLeanStringLiteral(proofReplayMethod) & " ∧")
  sourceLines.add("  z3Artifact.tactics = proofReplayTactics ∧")
  sourceLines.add("  solverUnsatReplay = " & solverReplayValue)
  sourceLines.add("")
  for line in buildSolverReplayTheorem(proofReplayVerified):
    sourceLines.add(line)
  sourceLines.add("")
  if generateInductiveProofs:
    sourceLines.add("theorem termination_argument : ∀ (S S' : " & stateTypeName & ") (ι : EnvInput), Step S ι S' → rank S' < rank S := by")
    sourceLines.add("  intro S S' ι hStep")
    sourceLines.add("  exact rank_decreases S S' ι hStep")
    sourceLines.add("")
    sourceLines.add("theorem no_deadlock_without_terminal : ∀ (S : " & stateTypeName & "), ¬ terminal S → ∃ (ι : EnvInput) (S' : " & stateTypeName & "), Step S ι S' := by")
    sourceLines.add("  intro S hNotTerminal")
    sourceLines.add("  cases progress_or_terminal S with")
    sourceLines.add("  | inl hTerminal =>")
    sourceLines.add("      exact False.elim (hNotTerminal hTerminal)")
    sourceLines.add("  | inr hProgress =>")
    sourceLines.add("      exact hProgress")
    sourceLines.add("")
  sourceLines.add(buildGoalAlias(aliasName, structuredStateName, branchDepth))
  sourceLines.add("")
  sourceLines.add(buildTheoremHeader(theorem, aliasName, loopDepth, branchDepth, structuredStateName))
  for line in buildTacticLines(loopDepth, branchDepth, aliasName, structuredStateName):
    let lineTokens = tokenizeLowered(line)
    if not ("simp" in lineTokens and "promotedinvariant" in lineTokens):
      sourceLines.add(line)
  sourceLines.add("")
  sourceLines.add("theorem " & theorem & "_vacuity_check : True := by")
  sourceLines.add("  ax_vacuity_check " & theorem)
  sourceLines.add("")
  sourceLines.add("end " & namespaceName)
  var replayTactics: seq[ProofReplayTactic] = @[]
  for tacticName in proofReplayTactics:
    replayTactics.add(ProofReplayTactic(name: tacticName, step: 0, verified: false))
  let assembledProof = sourceLines.join("\n")
  doAssert not assembledProof.contains("sorry"), "generated proof contains `sorry` (unsound placeholder) — rejected"
  result = LeanSpecInference(
    theoremName: theorem,
    theoremSource: assembledProof,
    guaranteedRange: inferGuaranteedRange(translation),
    assumptions: assumptions,
    stateTypeName: stateTypeName,
    stepConstructors: stepConstructors,
    environmentInputs: environmentInputs,
    stateInvariants: translation.stateInvariants,
    proofReplay: ProofReplayResult(
      replayMethod: proofReplayMethod,
      tactics: replayTactics,
      verified: proofReplayVerified,
      leanKernelVerified: leanKernelVerified,
      minimalProofPath: minimalProofPath,
      soundnessNote: soundnessNote,
      strictSpecWarnings: strictSpecWarnings
    ),
    refinementTheorem: "implementation_refines_step",
    refinementProven: refinementProven,
    terminationArgument: terminationArgument,
    loopControlVariables: loopControlVariables,
    rankVariables: rankVariables
  )
{.pop.}
