-- Axiom Standard Prelude
-- Maps Nim concepts to Lean 4 foundations for deterministic verification.

namespace AxiomPrelude

abbrev NimInt := Int
abbrev NimNat := Nat
abbrev NimString := String
def NimBool := Bool
def NimChar := Char

def NimSeq (α : Type) := List α
def NimArray (α : Type) (n : Nat) := { a : Array α // a.size = n }

def NimOption (α : Type) := Option α

inductive NimExcept (ε α : Type)
  | ok : α → NimExcept ε α
  | err : ε → NimExcept ε α

namespace NimExcept
  def isOk {ε α} : NimExcept ε α → Bool
    | ok _ => true
    | err _ => false
end NimExcept

axiom external_io_isolated : Prop
axiom external_io_isolated_true : external_io_isolated
axiom ast_parse_failed_isolated : Prop
axiom ast_parse_failed_isolated_true : ast_parse_failed_isolated

theorem NimInt_nonneg (n : Nat) : (n : NimInt) ≥ 0 := by
  exact Int.natCast_nonneg n

theorem NimSeq_length_nonneg {α} (s : NimSeq α) : s.length ≥ 0 := by
  exact Nat.zero_le s.length

end AxiomPrelude
