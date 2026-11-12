import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
{.push noSideEffect.}

## Refinement Types
## Phase 6: Proof-Driven Type System.
## Variables are not mere int/string; they carry SMT predicates as part of their type.
## A variable of type Int{v | v >= 0} needs no separate proof that v >= 0 —
## the type itself is the evidence.

import std/tables
import core/symbolic/symbolic_types_expr
import core/types/symbolic_types_lean
import core/types/domain_types
export domain_types.BaseTypeKind
export domain_types.RefinementType
export domain_types.LiquidTypeEnv

# ---------------------------------------------------------------------------
# Constructors
# ---------------------------------------------------------------------------

## Rt Int.
func rtInt*(pred: SymSExpr): RefinementType {.inline.} =
  RefinementType(base: btInt, predicate: pred)

## Rt Nat.
# @axiom-hint: lean="depth >= 0" smt="(assert (>= depth 0))"
func rtNat*(): RefinementType {.inline.} =
  RefinementType(base: btNat, predicate: sGe(sVar("v"), sConst(0)))

## Rt Bool.
func rtBool*(pred: SymSExpr = sTrue()): RefinementType {.inline.} =
  RefinementType(base: btBool, predicate: pred)

## Rt Unknown.
# @axiom-hint: lean="depth >= 0" smt="(assert (>= depth 0))"
func rtUnknown*(): RefinementType {.inline.} =
  RefinementType(base: btUnknown, predicate: sTrue())

# ---------------------------------------------------------------------------
# Pretty Printing
# ---------------------------------------------------------------------------

## Base Type To String.
# @axiom-hint: lean="btInt ∧ btNat ∧ btBool ∧ btString ∧ btUnknown" smt="(assert (and btInt btNat btBool btString btUnknown))"
func baseTypeToString*(base: BaseTypeKind): string {.noSideEffect.} =
  case base
  of btInt: "Int"
  of btNat: "Nat"
  of btBool: "Bool"
  of btString: "String"
  of btUnknown: "?"

## Refinement Type To String.
func refinementTypeToString*(rt: RefinementType): string {.raises: [].} =
  let predStr = sExprToString(rt.predicate)
  if predStr == "true":
    baseTypeToString(rt.base)
  else:
    baseTypeToString(rt.base) & "{v | " & predStr & "}"

# ---------------------------------------------------------------------------
# SMT Assertion Generation
# ---------------------------------------------------------------------------

## Substitute Var In Predicate.
# @axiom-hint: lean="seVar ∧ seConst ∧ seTrue ∧ seFalse ∧ seAdd ∧ seSub ∧ seMul ∧ seDiv ∧ seMod ∧ seEq ∧ seNe ∧ seLt ∧ seLe ∧ seGt ∧ seGe ∧ seAnd ∧ seOr ∧ seNot" smt="(assert (and seVar seConst seTrue seFalse seAdd seSub seMul seDiv seMod seEq seNe seLt seLe seGt seGe seAnd seOr seNot))"
func substituteVarInPredicate*(pred: SymSExpr; varName: string): SymSExpr {.raises: [].} =
  ## Replaces every occurrence of variable "v" in the predicate with varName.
  if pred.isNil:
    return nil
  case pred.kind
  of seVar:
    if pred.name == "v":
      return sVar(varName)
    else:
      return sVar(pred.name)
  of seConst:
    return sConst(pred.intValue)
  of seTrue:
    return sTrue()
  of seFalse:
    return sFalse()
  of seAdd:
    return sAdd(substituteVarInPredicate(pred.lhs, varName), substituteVarInPredicate(pred.rhs, varName))
  of seSub:
    return sSub(substituteVarInPredicate(pred.lhs, varName), substituteVarInPredicate(pred.rhs, varName))
  of seMul:
    return sMul(substituteVarInPredicate(pred.lhs, varName), substituteVarInPredicate(pred.rhs, varName))
  of seDiv:
    return SymSExpr(kind: seDiv, lhs: substituteVarInPredicate(pred.lhs, varName), rhs: substituteVarInPredicate(pred.rhs, varName))
  of seMod:
    return SymSExpr(kind: seMod, lhs: substituteVarInPredicate(pred.lhs, varName), rhs: substituteVarInPredicate(pred.rhs, varName))
  of seEq:
    return sEq(substituteVarInPredicate(pred.lhs, varName), substituteVarInPredicate(pred.rhs, varName))
  of seNe:
    return SymSExpr(kind: seNe, lhs: substituteVarInPredicate(pred.lhs, varName), rhs: substituteVarInPredicate(pred.rhs, varName))
  of seLt:
    return sLt(substituteVarInPredicate(pred.lhs, varName), substituteVarInPredicate(pred.rhs, varName))
  of seLe:
    return sLe(substituteVarInPredicate(pred.lhs, varName), substituteVarInPredicate(pred.rhs, varName))
  of seGt:
    return SymSExpr(kind: seGt, lhs: substituteVarInPredicate(pred.lhs, varName), rhs: substituteVarInPredicate(pred.rhs, varName))
  of seGe:
    return sGe(substituteVarInPredicate(pred.lhs, varName), substituteVarInPredicate(pred.rhs, varName))
  of seAnd:
    return sAnd(substituteVarInPredicate(pred.lhs, varName), substituteVarInPredicate(pred.rhs, varName))
  of seOr:
    return SymSExpr(kind: seOr, lhs: substituteVarInPredicate(pred.lhs, varName), rhs: substituteVarInPredicate(pred.rhs, varName))
  of seNot:
    return sNot(substituteVarInPredicate(pred.lhs, varName))
  else:
    # Generic deep-copy for new ADT/collection/abstract variants.
    # Preserves kind, name, and recursively substitutes lhs/rhs.
    new(result)
    result.kind = pred.kind
    result.name = pred.name
    result.intValue = pred.intValue
    if pred.lhs != nil:
      result.lhs = substituteVarInPredicate(pred.lhs, varName)
    if pred.rhs != nil:
      result.rhs = substituteVarInPredicate(pred.rhs, varName)

## Refinement Type To Smt Assert.
# @axiom-hint: lean="(result ≥ 0)" smt="(assert (and (>= result 0)))"
func refinementTypeToSmtAssert*(varName: string; rt: RefinementType): string {.raises: [].} =
  ## Converts a refinement type for variable varName into an SMT-LIB2 assertion.
  ## e.g., Int{v | v >= 0} for "i" → "(assert (>= i 0))"
  if rt.predicate.isNil or rt.predicate.kind == seTrue:
    return ""
  let substituted = substituteVarInPredicate(rt.predicate, varName)
  result = "(assert " & sExprToString(substituted) & ")"

# ---------------------------------------------------------------------------
# Lean 4 Subtype Generation
# ---------------------------------------------------------------------------

## Refinement Type To Lean Subtype.
# @axiom-hint: lean="btInt ∧ btNat ∧ btBool ∧ btString ∧ btUnknown ∧ baseStr ∧ (result ≥ 0)" smt="(assert (and btInt btNat btBool btString btUnknown baseStr (>= result 0)))"
func refinementTypeToLeanSubtype*(rt: RefinementType; varName: string): string {.raises: [].} =
  ## Converts a refinement type to Lean 4 Subtype notation.
  ## Int{v | v >= 0} for "i" → "{ i : Int // i >= 0 }"
  let baseStr = case rt.base
  of btInt: "Int"
  of btNat: "Nat"
  of btBool: "Bool"
  of btString: "String"
  of btUnknown: "?"
  if rt.predicate.isNil or rt.predicate.kind == seTrue:
    return baseStr
  let substituted = substituteVarInPredicate(rt.predicate, varName)
  let predStr = sExprToLean(substituted)
  result = "{ " & varName & " : " & baseStr & " // " & predStr & " }"

# ---------------------------------------------------------------------------
# Refinement Weakening / Widening
# ---------------------------------------------------------------------------

## Weaken Refinement.
# @axiom-hint: lean="depth >= 0" smt="(assert (and (>= depth 0)))"
func weakenRefinement*(rt: RefinementType; newPred: SymSExpr): RefinementType {.inline.} =
  ## Replaces the predicate with a weaker (more permissive) one.
  ## Used when liquid inference widens a type after mutation.
  RefinementType(base: rt.base, predicate: newPred)

## I Nat Refinement.
func isNatRefinement*(rt: RefinementType): bool {.noSideEffect.} =
  ## Checks if the refinement is equivalent to Nat (>= 0).
  if rt.predicate.isNil:
    return false
  if rt.predicate.kind == seGe:
    if rt.predicate.lhs != nil and rt.predicate.lhs.kind == seVar and rt.predicate.lhs.name == "v":
      if rt.predicate.rhs != nil and rt.predicate.rhs.kind == seConst and rt.predicate.rhs.intValue == 0:
        return true
  false

# ---------------------------------------------------------------------------
# Liquid Type Environment Utilities
# ---------------------------------------------------------------------------

## Env To Smt Asserts.
# @axiom-hint: lean="assertStr.length > 0 ∧ (env ≥ 0) ∧ (result ≥ 0)" smt="(assert (and (> (str.len assertStr) 0) (>= env 0) (>= result 0)))"
func envToSmtAsserts*(env: LiquidTypeEnv): seq[string] {.raises: [].} =
  ## Converts an entire liquid type environment to SMT assertions.
  result = @[]
  for varName, rt in env:
    let assertStr = refinementTypeToSmtAssert(varName, rt)
    if assertStr.len > 0:
      result.add(assertStr)

## Env To Lean Subtypes.
# @axiom-hint: lean="(env ≥ 0) ∧ (result ≥ 0)" smt="(assert (and (>= env 0) (>= result 0)))"
func envToLeanSubtypes*(env: LiquidTypeEnv): seq[tuple[varName: string; leanType: string]] {.raises: [].} =
  ## Converts an entire liquid type environment to Lean subtype declarations.
  result = @[]
  for varName, rt in env:
    result.add((varName, refinementTypeToLeanSubtype(rt, varName)))


{.pop.}

{.pop.}
