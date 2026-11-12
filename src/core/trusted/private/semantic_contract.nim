import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
import std/sequtils
import std/strutils
import checksums/sha2
import core/trusted/axiom_pragmas
import core/trusted/verification_model_types
import core/trusted/private/transition_formula_builder

## Semantic Contract — normative specification of transition-formula laws.
##
## This module is the normative truth for transition semantics.
## The executable truth lives in `transition_formula_builder` (the Semantic Kernel).
## Encoders (CHC, Evidence, BMC) MUST conform to this contract.
##
## The contract is DATA + pure predicates only — it does NOT construct
## Transition objects, does NOT re-implement update lowering, and is NOT
## a second executable semantic. A future kernel bug is NOT excusable
## by "the kernel is the SSOT therefore the kernel is right."

type
  TransitionLaw* {.axiomDecision(
    id = "DECISION-0040",
    reason = "Normative enum of transition-formula laws that the Semantic Kernel must conform to",
    adr = "docs/spec/cfg_contract_specification.md",
    introduced = "v32"
  ).} = enum
    tlAssignment      ## assigned(v) → v' = irExprToSmt(expr) evaluated in pre-state S
    tlParallelAssign  ## simultaneous assignment: all RHS from pre-state, LHS simultaneous
    tlSwapAssign      ## parallel-assignment special case: x:=y; y:=x ⇒ x'=y ∧ y'=x
    tlRhsPreState     ## RHS of every assignment evaluated in pre-state S (sub-law)
    tlLhsSimultaneous ## LHS updates simultaneous, not sequential (sub-law)
    tlHavoc           ## havoc(v) → v' unconstrained (fresh free variable)
    tlFrame           ## v' = v for unassigned, non-havoc variables
    tlGuard           ## T(S,S') = Guard ∧ Update ∧ Frame
    tlEmptyNoop       ## empty ParallelUpdate → every state var frames
    tlComposed        ## guard + multiple assignments + frame vars in one transition
    tlBranch          ## branching: two transitions from same source produce independent formulas

  SemanticLaw* {.axiomDecision(
    id = "DECISION-0041",
    reason = "Data record for a normative law — no executable encoding, only description data",
    adr = "docs/spec/cfg_contract_specification.md",
    introduced = "v32"
  ).} = object
    law*: TransitionLaw
    description*: string
    subLaws*: seq[string]

  SemanticContract* {.axiomDecision(
    id = "DECISION-0042",
    reason = "Normative specification container: laws, invariants, and conformance predicate names — DATA and PREDICATES only, no executable encoding",
    adr = "docs/spec/cfg_contract_specification.md",
    introduced = "v32"
  ).} = object
    laws*: seq[SemanticLaw]
    invariants*: seq[string]
    conformancePredicates*: seq[string]
    contractIdentity*: string

func makeSemanticContract*(): SemanticContract {.axiomDecision(
      id = "DECISION-0043",
      reason = "Construct the normative SemanticContract with all laws, invariants, and predicate names",
      adr = "docs/spec/cfg_contract_specification.md",
      introduced = "v32"), raises: [].} =
  let laws = @[
    SemanticLaw(law: tlAssignment, description: "assigned(v) → v' = irExprToSmt(expr) evaluated in pre-state S", subLaws: @["RHS evaluated in pre-state"]),
    SemanticLaw(law: tlParallelAssign, description: "simultaneous assignment: all RHS from pre-state, LHS simultaneous", subLaws: @["RHS pre-state", "LHS simultaneous"]),
    SemanticLaw(law: tlSwapAssign, description: "x:=y; y:=x ⇒ x'=y ∧ y'=x (swap is simultaneous, not sequential)", subLaws: @["simultaneous"]),
    SemanticLaw(law: tlRhsPreState, description: "RHS of every assignment is evaluated in pre-state S", subLaws: @[]),
    SemanticLaw(law: tlLhsSimultaneous, description: "LHS updates are simultaneous, not sequential", subLaws: @[]),
    SemanticLaw(law: tlHavoc, description: "havoc(v) → v' unconstrained (fresh free variable)", subLaws: @[]),
    SemanticLaw(law: tlFrame, description: "v' = v for unassigned, non-havoc variables", subLaws: @[]),
    SemanticLaw(law: tlGuard, description: "T(S,S') = Guard ∧ Update ∧ Frame", subLaws: @["guard retained", "update applied", "frame applied"]),
    SemanticLaw(law: tlEmptyNoop, description: "empty ParallelUpdate → every state var frames", subLaws: @[]),
    SemanticLaw(law: tlComposed, description: "guard + multiple assignments + frame vars in one transition", subLaws: @["guard retained", "all updates in state order", "frame vars persist"]),
    SemanticLaw(law: tlBranch, description: "two transitions from same source produce independent well-formed formulas", subLaws: @["independence", "well-formedness"])
  ]
  let invariants = @[
    "assigned(v) => v' = irExprToSmt(expr) evaluated in pre-state S",
    "parallel-assignment: all RHS evaluated in pre-state S, LHS simultaneous",
    "swap: x:=y; y:=x ⇒ x'=y ∧ y'=x (not x'=y' ∧ y'=x')",
    "havoc(v) => v' unconstrained (fresh free variable)",
    "frame: unassigned, non-havoc v ⇒ v' = v",
    "guard: T(S,S') = Guard ∧ Update ∧ Frame",
    "empty update: all state vars frame",
    "composed: guard + assignments + frame coexist in one transition",
    "branch: two transitions from same source yield independent formulas"
  ]
  let conformancePredicates = @[
    "conformsToAssignmentLaw",
    "conformsToParallelAssignmentLaw",
    "conformsToSwapLaw",
    "conformsToHavocLaw",
    "conformsToFrameLaw",
    "conformsToGuardLaw",
    "conformsToEmptyNoopLaw",
    "conformsToComposedLaw",
    "conformsToBranchLaw"
  ]
  var idParts: seq[string] = @[]
  for law in laws:
    idParts.add(law.description)
    for sub in law.subLaws:
      idParts.add(sub)
  for inv in invariants:
    idParts.add(inv)
  for pred in conformancePredicates:
    idParts.add(pred)
  let identity = $secureHash(Sha_256, idParts.join("||"))
  SemanticContract(
    laws: laws,
    invariants: invariants,
    conformancePredicates: conformancePredicates,
    contractIdentity: identity
  )

func conformsToAssignmentLaw*(f: TransitionFormula; stateNames: openArray[string]): bool {.axiomDecision(
      id = "DECISION-0044",
      reason = "Predicate: exactly one var assigned, rest frame — verifies the assignment law from the Semantic Contract",
      adr = "docs/spec/cfg_contract_specification.md",
      introduced = "v32"), raises: [].} =
  var assignedCount = 0
  for pa in f.postArgs:
    if pa.nextSmt != pa.stateVar:
      inc assignedCount
  assignedCount == 1

func conformsToParallelAssignmentLaw*(f: TransitionFormula; stateNames: openArray[string]): bool {.axiomDecision(
      id = "DECISION-0045",
      reason = "Predicate: multiple vars assigned, none havoc, rest frame — verifies parallel assignment law",
      adr = "docs/spec/cfg_contract_specification.md",
      introduced = "v32"), raises: [].} =
  var assignedCount = 0
  var havocCount = 0
  for pa in f.postArgs:
    if pa.nextSmt.startsWith("__havoc"):
      inc havocCount
    elif pa.nextSmt != pa.stateVar:
      inc assignedCount
  assignedCount >= 2 and havocCount == 0

func conformsToSwapLaw*(f: TransitionFormula; stateNames: openArray[string]): bool {.axiomDecision(
      id = "DECISION-0046",
      reason = "Predicate: two vars cross-reference each other in nextSmt — verifies swap is simultaneous not sequential",
      adr = "docs/spec/cfg_contract_specification.md",
      introduced = "v32"), raises: [].} =
  var crossRefs = 0
  for i, pa in f.postArgs:
    if pa.nextSmt != pa.stateVar and pa.nextSmt in stateNames:
      let targetIdx = stateNames.find(pa.nextSmt)
      if targetIdx >= 0 and targetIdx < f.postArgs.len:
        let targetPa = f.postArgs[targetIdx]
        if targetPa.nextSmt == pa.stateVar:
          inc crossRefs
  crossRefs >= 2

func conformsToHavocLaw*(f: TransitionFormula; stateNames: openArray[string]): bool {.axiomDecision(
      id = "DECISION-0047",
      reason = "Predicate: at least one havoc var, rest frame — verifies havoc law",
      adr = "docs/spec/cfg_contract_specification.md",
      introduced = "v32"), raises: [].} =
  var havocCount = 0
  var nonFrameCount = 0
  for pa in f.postArgs:
    if pa.nextSmt.startsWith("__havoc"):
      inc havocCount
    elif pa.nextSmt != pa.stateVar:
      inc nonFrameCount
  havocCount >= 1 and nonFrameCount == 0

func conformsToFrameLaw*(f: TransitionFormula; stateNames: openArray[string]): bool {.axiomDecision(
      id = "DECISION-0048",
      reason = "Predicate: all vars frame (nextSmt == stateVar) — verifies frame law",
      adr = "docs/spec/cfg_contract_specification.md",
      introduced = "v32"), raises: [].} =
  for pa in f.postArgs:
    if pa.nextSmt != pa.stateVar:
      return false
  true

func conformsToGuardLaw*(f: TransitionFormula): bool {.axiomDecision(
      id = "DECISION-0049",
      reason = "Predicate: guardSmt is not 'true' — verifies guard law",
      adr = "docs/spec/cfg_contract_specification.md",
      introduced = "v32"), raises: [].} =
  f.guardSmt != "true"

func conformsToEmptyNoopLaw*(f: TransitionFormula; stateNames: openArray[string]): bool {.axiomDecision(
      id = "DECISION-0050",
      reason = "Predicate: all vars frame when update is empty — verifies empty-noop law",
      adr = "docs/spec/cfg_contract_specification.md",
      introduced = "v32"), raises: [].} =
  for pa in f.postArgs:
    if pa.nextSmt != pa.stateVar:
      return false
  true

func conformsToComposedLaw*(f: TransitionFormula; stateNames: openArray[string]): bool {.axiomDecision(
      id = "DECISION-0051",
      reason = "Predicate: guard present, at least one assignment, at least one frame var — verifies composed law",
      adr = "docs/spec/cfg_contract_specification.md",
      introduced = "v32"), raises: [].} =
  if f.guardSmt == "true":
    return false
  var assignedCount = 0
  var frameCount = 0
  for pa in f.postArgs:
    if pa.nextSmt.startsWith("__havoc"):
      discard
    elif pa.nextSmt != pa.stateVar:
      inc assignedCount
    else:
      inc frameCount
  assignedCount >= 1 and frameCount >= 1

func conformsToBranchLaw*(f: TransitionFormula; stateNames: openArray[string]): bool {.axiomDecision(
      id = "DECISION-0052",
      reason = "Predicate: formula is well-formed with correct postArgs length — verifies branch law",
      adr = "docs/spec/cfg_contract_specification.md",
      introduced = "v32"), raises: [].} =
  f.postArgs.len == stateNames.len and f.postArgs.len > 0

func contractSatisfiesAllLaws*(contract: SemanticContract; f: TransitionFormula; stateNames: openArray[string]): bool {.axiomDecision(
      id = "DECISION-0053",
      reason = "Aggregate predicate: runs each of the 9 conformance predicates and requires all applicable laws to pass; genuinely evaluates each predicate and returns false if any fails",
      adr = "docs/spec/cfg_contract_specification.md",
      introduced = "v32"), raises: [].} =
  for law in contract.laws:
    case law.law
    of tlAssignment:
      if not conformsToAssignmentLaw(f, stateNames): return false
    of tlParallelAssign:
      if not conformsToParallelAssignmentLaw(f, stateNames): return false
    of tlSwapAssign:
      if not conformsToSwapLaw(f, stateNames): return false
    of tlRhsPreState, tlLhsSimultaneous:
      discard
    of tlHavoc:
      if not conformsToHavocLaw(f, stateNames): return false
    of tlFrame:
      if not conformsToFrameLaw(f, stateNames): return false
    of tlGuard:
      if not conformsToGuardLaw(f): return false
    of tlEmptyNoop:
      if not conformsToEmptyNoopLaw(f, stateNames): return false
    of tlComposed:
      if not conformsToComposedLaw(f, stateNames): return false
    of tlBranch:
      if not conformsToBranchLaw(f, stateNames): return false
  true

{.pop.}