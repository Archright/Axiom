import Std
import lib.MemorySafety

namespace AxiomHybrid.OtherFunc

open Axiom.Verification.Theorems

inductive UniValueVType where
| vnull
| vstr
deriving DecidableEq, Repr

def returnssemanticerror (typ expected : UniValueVType) : Bool :=
  decide (typ != expected)

axiom univalue_cpp_otherfunc_equal_values_do_not_throw_smt_unsat_premise : Prop

def semanticCandidateInvariantHints : List String := ["equal enum values imply no throw", "bounds-checked container access only returns Option.some inside valid range", "disjoint memory regions preserve pointer alias isolation", "semantic goal: equal_values_do_not_throw"]

def proofDependencies : List String := ["BoundsCheck", "vectorRead_zero", "pointerSegmentRead_maps_to_vector", "disjoint_left", "pointerAliasIsolation"]

def minimalProofPath : List String := ["subst hEq", "simp [returnssemanticerror]"]

def candidateInvariant (typ expected : UniValueVType) : Prop :=
  typ = expected → returnssemanticerror typ expected = false

example (typ expected : UniValueVType) :
  candidateInvariant typ expected := by
  intro hEqCandidate
  subst hEqCandidate
  simp [returnssemanticerror]

example : BoundsCheck 3 0 := by
  simp [BoundsCheck]

example : vectorRead ([typ] : List UniValueVType) 0 = some typ := by
  simpa using (vectorRead_zero typ [])

example : pointerSegmentRead ([typ] : List UniValueVType) 0 0 = vectorRead ([typ] : List UniValueVType) 0 := by
  simpa using (pointerSegmentRead_maps_to_vector (memory := ([typ] : List UniValueVType)) (base := 0) (offset := 0))

example : disjoint { base := 0, size := 1 } { base := 1, size := 1 } := by
  exact disjoint_left _ _ (by simp)

theorem univalue_cpp_otherfunc_equal_values_do_not_throw (typ expected : UniValueVType)
  (hEq : typ = expected)
  (hSmtUnsat : univalue_cpp_otherfunc_equal_values_do_not_throw_smt_unsat_premise) :
  returnssemanticerror typ expected = false := by
  have _ : univalue_cpp_otherfunc_equal_values_do_not_throw_smt_unsat_premise := hSmtUnsat
  subst hEq
  simp [returnssemanticerror]

end AxiomHybrid.OtherFunc
