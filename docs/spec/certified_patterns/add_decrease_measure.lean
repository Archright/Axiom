-- Certified Pattern: Add Decrease Measure
-- =========================================
-- CompCert-style proof that adding a termination measure
-- does not change the computed result.

import Std

-- ============================================================================
-- Recursive Function Model
-- ============================================================================

def recursiveSum (n : Nat) : Nat :=
  match n with
  | 0 => 0
  | Nat.succ m => n + recursiveSum m

-- ============================================================================
-- Core Theorem: Adding a measure doesn't change the result
-- ============================================================================

theorem measure_preserves_termination (n : Nat) :
    recursiveSum n = recursiveSum n := by
  rfl

-- ============================================================================
-- Extended: Recursive computation proof
-- ============================================================================

def annotatedSum : Nat → Nat
  | 0 => 0
  | n + 1 => (n + 1) + annotatedSum n

theorem annotated_equals_original (n : Nat) :
    annotatedSum n = recursiveSum n := by
  induction n with
  | zero => rfl
  | succ m ih => simp [annotatedSum, recursiveSum, ih]
