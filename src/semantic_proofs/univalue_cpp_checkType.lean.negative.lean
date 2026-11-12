import Std
import lib.MemorySafety

namespace AxiomHybrid

open Axiom.Verification.Theorems

inductive UniValueVType where
| vnull
| vobj
deriving DecidableEq, Repr

def throwsruntimeerror (typ expected : UniValueVType) : Bool :=
  decide (typ != expected)

axiom univalue_cpp_checktype_equal_values_do_not_throw_smt_unsat_premise : Prop

def semanticCandidateInvariantHints : List String := ["equal enum values imply no throw", "bounds-checked container access only returns Option.some inside valid range", "disjoint memory regions preserve pointer alias isolation", "semantic goal: equal_values_do_not_throw"]

def proofDependencies : List String := ["BoundsCheck", "vectorRead_zero", "pointerSegmentRead_maps_to_vector", "disjoint_left", "pointerAliasIsolation"]

def minimalProofPath : List String := ["subst hEq", "simp [throwsruntimeerror]"]

def candidateInvariant (typ expected : UniValueVType) : Prop :=
  typ = expected → throwsruntimeerror typ expected = false

example (typ expected : UniValueVType) : False := by
  intro hEqCandidate
  subst hEqCandidate
  simp [throwsruntimeerror]

example : BoundsCheck 3 0 := by
  simp [BoundsCheck]

example : vectorRead ([typ] : List UniValueVType) 0 = some typ := by
  simpa using (vectorRead_zero typ [])

example : pointerSegmentRead ([typ] : List UniValueVType) 0 0 = vectorRead ([typ] : List UniValueVType) 0 := by
  simpa using (pointerSegmentRead_maps_to_vector (memory := ([typ] : List UniValueVType)) (base := 0) (offset := 0))

example : disjoint { base := 0, size := 1 } { base := 1, size := 1 } := by
  exact disjoint_left _ _ (by simp)

theorem univalue_cpp_checktype_equal_values_do_not_throw (typ expected : UniValueVType)
  (hEq : typ = expected)
  (hSmtUnsat : univalue_cpp_checktype_equal_values_do_not_throw_smt_unsat_premise) :
  throwsruntimeerror typ expected = false := by
  subst hEq
  simp [throwsruntimeerror]

end AxiomHybrid