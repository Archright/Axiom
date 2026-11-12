-- Certified Pattern: Linearize Variables
-- ========================================
-- CompCert-style proof that replacing non-linear arithmetic with linear
-- auxiliary variables preserves the computed result.
--
-- Pattern: rpkLinearizeVariables
-- Precondition: Non-linear arithmetic exists, no division by variable
-- Postcondition: Linearized computation produces identical output
--
-- Key insight: Introducing auxiliary variables for non-linear terms
-- is a structural transformation that doesn't change the computation.
-- It simply names intermediate results.

import Std

-- ============================================================================
-- Linearization Model
-- A non-linear expression like `a * b + c` can be linearized by
-- introducing `ab := a * b`, then computing `ab + c`.
-- The result is identical.
-- ============================================================================

/-- Original non-linear computation -/
def nonlinearCompute (a b c : Int) : Int :=
  a * b + c

/-- Linearized computation with auxiliary variable -/
def linearizedCompute (a b c : Int) : Int :=
  let ab := a * b  -- auxiliary variable for the non-linear term
  ab + c

-- ============================================================================
-- Core Theorem: Linearization preserves result
-- ============================================================================

theorem linearize_preserves_equivalence (a b c : Int) :
    nonlinearCompute a b c = linearizedCompute a b c := by
  simp [nonlinearCompute, linearizedCompute]

-- ============================================================================
-- Extended: Linearization with multiple non-linear terms
-- ============================================================================

def nonlinearMulti (a b c d : Int) : Int :=
  a * b + c * d

def linearizedMulti (a b c d : Int) : Int :=
  let ab := a * b
  let cd := c * d
  ab + cd

theorem linearize_multi_preserves (a b c d : Int) :
    nonlinearMulti a b c d = linearizedMulti a b c d := by
  simp [nonlinearMulti, linearizedMulti]

-- ============================================================================
-- Extended: Linearization preserves inequality constraints
-- ============================================================================

theorem linearize_preserves_ordering (a b c d : Int)
    (h : a * b < c * d) :
    linearizedCompute a b 0 < linearizedCompute c d 0 := by
  simp [linearizedCompute]
  exact h
