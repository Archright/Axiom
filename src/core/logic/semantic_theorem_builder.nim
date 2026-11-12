import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
{.push noSideEffect.}

## Component A — Pure Semantic Theorem Builder
##
## Static theorem name generation, tactic candidate construction,
## and Lean theorem source assembly for the semantic verification pipeline.
## Zero I/O.

{.push raises: [].}
{.push noSideEffect.}
import std/sequtils
import std/strutils

import core/contracts/universal_pipeline_contract
import core/proof/axiom_lemmas
import core/utils/text_utils
import core/logic/lean_diagnostic
import core/trusted/lean_util

import core/types/pipeline_core_types
export pipeline_core_types

## Build Semantic Lean Theorem Name is now in core/contracts/universal_pipeline_contract.

# Re-export from axiom_lemmas for backward compatibility.
# @axiom-hint: lean="depth >= 0" smt="(assert (>= depth 0))"
func semanticLemmaImportModule(): string {.raises: [], noSideEffect.} =
  axiom_lemmas.semanticLemmaImportModule()

# @axiom-hint: lean="leftName.length ≥ 0 ∧ rightName.length ≥ 0 ∧ throwsName.length ≥ 0" smt="(assert (and (>= (str.len leftName) 0) (>= (str.len rightName) 0) (>= (str.len throwsName) 0)))"
func buildSemanticCandidateInvariantExpr(
  payload: SemanticEqualityPayload;
  leftName: string;
  rightName: string;
  throwsName: string
): string {.raises: [].} =
  "candidateInvariant " & leftName & " " & rightName & " := " &
    leftName & " = " & rightName & " → " & throwsName & " " & leftName & " " & rightName & " = false"

## Build Semantic Candidate Invariant Hints.
func buildSemanticCandidateInvariantHints*(payload: SemanticEqualityPayload): seq[string] {.raises: [].} =
  result.add("equal enum values imply no throw")
  result.add("bounds-checked container access only returns Option.some inside valid range")
  result.add("disjoint memory regions preserve pointer alias isolation")
  if semanticProofGoalString(payload.proofGoal).strip().len > 0:
    result.add("semantic goal: " & semanticProofGoalString(payload.proofGoal))

## Build Semantic Proof Dependencies.
# @axiom-hint: lean="depth >= 0" smt="(assert (>= depth 0))"
func buildSemanticProofDependencies*(): seq[string] {.raises: [], noSideEffect.} =
  @[
    "BoundsCheck",
    "vectorRead_zero",
    "pointerSegmentRead_maps_to_vector",
    "disjoint_left",
    "pointerAliasIsolation"
  ]

## Build Semantic Proof Tactic Candidates.
# @axiom-hint: lean="candidateInvariants.length > 0 ∧ (result ≥ 0) ∧ (∀ (candidateInvariantsIdx : Fin candidateInvariants.size), (candidateInvariants.get candidateInvariantsIdx).length ≥ 0)" smt="(assert (and (> (str.len candidateInvariants) 0) (>= result 0) (forall ((candidateInvariantsIdx Int)) (=> (and (>= candidateInvariantsIdx 0) (< candidateInvariantsIdx (seq.len candidateInvariants))) (>= (str.len (seq.nth candidateInvariants candidateInvariantsIdx)) 0)))))"
func buildSemanticProofTacticCandidates*(
  payload: SemanticEqualityPayload;
  candidateInvariants: seq[string] = @[]
): seq[string] {.raises: [].} =
  let throwsName = sanitizeLeanIdentifier(semanticSymbolNameString(payload.throwsSymbol))
  result.add(
    "have _ : " & buildSemanticLeanTheoremName(payload) & "_smt_unsat_premise := hSmtUnsat\n" &
    "subst hEq\n" &
    "simp [" & throwsName & "]"
  )
  result.add("cases hEq\nsimp [" & throwsName & "]")
  result.add("subst hEq\nsimp [" & throwsName & "]")
  if candidateInvariants.len > 0:
    result.add(
      "have _ : " & buildSemanticLeanTheoremName(payload) & "_smt_unsat_premise := hSmtUnsat\n" &
      "subst hEq\n" &
      "simp [" & throwsName & "]"
    )
  result = result.deduplicate()

## I Semantic Replay Tactic Compatible.
# @axiom-hint: lean="tactic.length ≥ 0" smt="(assert (and (>= (str.len tactic) 0)))"
func isSemanticReplayTacticCompatible*(tactic: string): bool {.raises: [], noSideEffect.} =
  let tokens = tokenizeLowered(tactic)
  not ("simpa" in tokens and "invariant" in tokens and "using" in tokens and "nat" in tokens and "zero_le" in tokens and "run" in tokens and "steps" in tokens and "amount" in tokens and "initialbalance" in tokens)

# @axiom-hint: lean="blockText.length ≥ 0 ∧ indentPrefix.length ≥ 0" smt="(assert (and (>= (str.len blockText) 0) (>= (str.len indentPrefix) 0)))"
# @axiom-hint: lean="line.length = 0" smt="(assert (and (= (str.len line) 0)))"
func toLeanBlockLines(blockText: string; indentPrefix: string = "  "): seq[string] {.raises: [].} =
  for line in blockText.splitLines():
    if line.len == 0:
      result.add("")
    else:
      result.add(indentPrefix & line)

## Merge Lean Diagnostics.
# @axiom-hint: lean="result = primary ∧ alreadyPresent = true ∧ (secondary ≥ 0) ∧ (result ≥ 0) ∧ (alreadyPresent ≥ 0)" smt="(assert (and (= result primary) (= alreadyPresent true) (>= secondary 0) (>= result 0) (>= alreadyPresent 0)))"
func mergeLeanDiagnostics*(
  primary: seq[LeanDiagnostic];
  secondary: seq[LeanDiagnostic]
): seq[LeanDiagnostic] {.raises: [].} =
  result = primary
  for item in secondary:
    var alreadyPresent = false
    for existing in result:
      if existing.line == item.line and
         existing.character == item.character and
         existing.severity == item.severity and
         existing.message == item.message:
        alreadyPresent = true
        break
    if not alreadyPresent:
      result.add(item)

## Semantic Proof Tactic Line.
# @axiom-hint: lean="tacticLines.length = 0 ∧ 0 ∧ idx ∧ tacticLines.length = 0 → result = 0" smt="(assert (and (= (str.len tacticLines) 0) 0 idx (=> (= (str.len tacticLines) 0) (= result 0))))"
func semanticProofTacticLine*(source: string; tactic: string): int {.raises: [].} =
  let tacticLines = tactic.splitLines()
  if tacticLines.len == 0:
    return 0
  let firstTacticLine = tacticLines[0].strip()
  let sourceLines = source.splitLines()
  for idx, line in sourceLines.pairs():
    if line.strip() == firstTacticLine:
      return idx
  0

## Build Semantic Lean Theorem Source.
# @axiom-hint: lean="theoremTactic.length ≥ 0 ∧ candidateInvariants.size ≥ 0 ∧ (∀ (candidateInvariantsIdx : Fin candidateInvariants.size), (candidateInvariants.get candidateInvariantsIdx).length ≥ 0)" smt="(assert (and (>= (str.len theoremTactic) 0) (>= (seq.len candidateInvariants) 0) (forall ((candidateInvariantsIdx Int)) (=> (and (>= candidateInvariantsIdx 0) (< candidateInvariantsIdx (seq.len candidateInvariants))) (>= (str.len (seq.nth candidateInvariants candidateInvariantsIdx)) 0)))))"
# @axiom-hint: lean="candidateInvariants.length > 0 ∧ (result ≥ 0) ∧ (∀ (candidateInvariantsIdx : Fin candidateInvariants.size), (candidateInvariants.get candidateInvariantsIdx).length ≥ 0)" smt="(assert (and (> (str.len candidateInvariants) 0) (>= result 0) (forall ((candidateInvariantsIdx Int)) (=> (and (>= candidateInvariantsIdx 0) (< candidateInvariantsIdx (seq.len candidateInvariants))) (>= (str.len (seq.nth candidateInvariants candidateInvariantsIdx)) 0)))))"
func buildSemanticLeanTheoremSource*(
  payload: SemanticEqualityPayload;
  theoremTactic: string = "";
  candidateInvariants: seq[string] = @[]
): string {.raises: [].} =
  let theoremName = buildSemanticLeanTheoremName(payload)
  let enumName = semanticEnumTypeNameString(payload.enumTypeName)
  let leftName = sanitizeLeanIdentifier(semanticSymbolNameString(payload.leftSymbol))
  let rightName = sanitizeLeanIdentifier(semanticSymbolNameString(payload.rightSymbol))
  let throwsName = sanitizeLeanIdentifier(semanticSymbolNameString(payload.throwsSymbol))
  let premiseBinding = "hSmtUnsat"
  let equalityBinding = "hEq"
  let enumConstructors = payload.enumValues
    .mapIt("| " & sanitizeLeanIdentifier(semanticEnumLabelString(it)))
    .join("\n")
  let premiseName = theoremName & "_smt_unsat_premise"
  let candidateInvariantName = "candidateInvariant"
  let invariantHints =
    if candidateInvariants.len > 0: candidateInvariants
    else: buildSemanticCandidateInvariantHints(payload)
  let candidateInvariantExpr = buildSemanticCandidateInvariantExpr(payload, leftName, rightName, throwsName)
  let proofDependencies = buildSemanticProofDependencies()
  let tactic =
    if theoremTactic.strip().len > 0: minimizeProofTactic(theoremTactic)
    else: buildSemanticProofTacticCandidates(payload, invariantHints)[0]
  let minimalProofPath = minimizeProofPath(tactic)
  result = [
    "import Std",
    "import " & semanticLemmaImportModule(),
    "import ax_solve",
    "",
    "namespace AxiomHybrid",
    "",
    "open Axiom.Verification.Theorems",
    "",
    "inductive " & enumName & " where",
    enumConstructors,
    "deriving DecidableEq, Repr",
    "",
    "def " & throwsName & " (" & leftName & " " & rightName & " : " & enumName & ") : Bool :=",
    "  decide (" & leftName & " != " & rightName & ")",
    "",
    "axiom " & premiseName & " : Prop",
    "",
    "def semanticCandidateInvariantHints : List String := [" &
      invariantHints.mapIt("\"" & it.replace("\\", "\\\\").replace("\"", "\\\"") & "\"").join(", ") & "]",
    "",
    "def proofDependencies : List String := " & buildLeanStringList(proofDependencies),
    "",
    "def minimalProofPath : List String := " & buildLeanStringList(minimalProofPath),
    "",
    "def " & candidateInvariantName & " (" & leftName & " " & rightName & " : " & enumName & ") : Prop :=",
    "  " & candidateInvariantExpr.split(":= ", 1)[1],
    "",
    "example (" & leftName & " " & rightName & " : " & enumName & ") :",
    "  " & candidateInvariantName & " " & leftName & " " & rightName & " := by",
    "  intro hEqCandidate",
    "  subst hEqCandidate",
    "  simp [" & throwsName & "]",
    "",
    "example : BoundsCheck " & $(payload.enumValues.len + 1) & " 0 := by",
    "  simp [BoundsCheck]",
    "",
    "example : vectorRead ([" & leftName & "] : List " & enumName & ") 0 = some " & leftName & " := by",
    "  simpa using (vectorRead_zero " & leftName & " [])",
    "",
    "example : pointerSegmentRead ([" & leftName & "] : List " & enumName & ") 0 0 = vectorRead ([" &
      leftName & "] : List " & enumName & ") 0 := by",
    "  simpa using (pointerSegmentRead_maps_to_vector (memory := ([" & leftName &
      "] : List " & enumName & ")) (base := 0) (offset := 0))",
    "",
    "example : disjoint { base := 0, size := 1 } { base := 1, size := 1 } := by",
    "  exact disjoint_left _ _ (by simp)",
    "",
    "theorem " & theoremName & " (" & leftName & " " & rightName & " : " & enumName & ")",
    "  (" & equalityBinding & " : " & leftName & " = " & rightName & ")",
    "  (" & premiseBinding & " : " & premiseName & ") :",
    "  " & throwsName & " " & leftName & " " & rightName & " = false := by",
    toLeanBlockLines(tactic).join("\n"),
    "",
    "end AxiomHybrid"
  ].join("\n")


{.pop.}

{.pop.}
{.pop.}
{.pop.}
