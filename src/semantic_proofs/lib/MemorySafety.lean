import Std

namespace Axiom.Verification.Theorems

def BoundsCheck (size index : Nat) : Prop :=
  index < size

def vectorRead : List α → Nat → Option α
  | [], _ => none
  | x :: _, 0 => some x
  | _ :: xs, Nat.succ index => vectorRead xs index

def pointerRead (memory : List α) (base offset : Nat) : Option α :=
  vectorRead memory (base + offset)

def pointerSegmentRead (memory : List α) (base offset : Nat) : Option α :=
  vectorRead (memory.drop base) offset

structure MemoryRegion where
  base : Nat
  size : Nat
  deriving Repr, DecidableEq

def regionContains (region : MemoryRegion) (addr : Nat) : Prop :=
  region.base <= addr ∧ addr < region.base + region.size

def disjoint (lhs rhs : MemoryRegion) : Prop :=
  lhs.base + lhs.size <= rhs.base ∨ rhs.base + rhs.size <= lhs.base

theorem vectorRead_zero (x : α) (xs : List α) :
  vectorRead (x :: xs) 0 = some x := by
  rfl

theorem vectorRead_succ (x : α) (xs : List α) (index : Nat) :
  vectorRead (x :: xs) (Nat.succ index) = vectorRead xs index := by
  rfl

theorem boundsCheck_allows_vector_read (xs : List α) (index : Nat)
  (h : BoundsCheck xs.length index) :
  ∃ value, vectorRead xs index = some value := by
  induction xs generalizing index with
  | nil =>
      cases h
  | cons x xs ih =>
      cases index with
      | zero =>
          exact ⟨x, rfl⟩
      | succ k =>
          simp [BoundsCheck, vectorRead] at h ⊢
          exact ih k h

theorem pointerSegmentRead_maps_to_vector (memory : List α) (base offset : Nat) :
  pointerSegmentRead memory base offset = vectorRead (memory.drop base) offset := by
  rfl

theorem boundsCheck_allows_pointer_segment_read (memory : List α) (base offset : Nat)
  (h : BoundsCheck (memory.drop base).length offset) :
  ∃ value, pointerSegmentRead memory base offset = some value := by
  simpa [pointerSegmentRead] using boundsCheck_allows_vector_read (memory.drop base) offset h

theorem disjoint_left (lhs rhs : MemoryRegion)
  (h : lhs.base + lhs.size <= rhs.base) :
  disjoint lhs rhs := by
  exact Or.inl h

theorem disjoint_right (lhs rhs : MemoryRegion)
  (h : rhs.base + rhs.size <= lhs.base) :
  disjoint lhs rhs := by
  exact Or.inr h

theorem disjoint_symm (lhs rhs : MemoryRegion) :
  disjoint lhs rhs -> disjoint rhs lhs := by
  intro h
  cases h with
  | inl hLeft =>
      exact Or.inr hLeft
  | inr hRight =>
      exact Or.inl hRight

theorem pointerAliasIsolation (lhs rhs : MemoryRegion)
  (h : disjoint lhs rhs) :
  disjoint rhs lhs := by
  exact disjoint_symm lhs rhs h

end Axiom.Verification.Theorems
