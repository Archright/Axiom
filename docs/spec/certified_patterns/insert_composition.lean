-- Certified Pattern: Insert Composition Node
-- ============================================
-- CompCert-style proof that inserting an intermediate composition node
-- in a call chain preserves the overall computation.
--
-- Pattern: rpkInsertCompositionNode
-- Precondition: Call chain depth ≥ 3, no recursion in chain
-- Postcondition: Composed result equals original result
--
-- Key insight: Function composition is associative.
-- f(g(h(x))) = (f ∘ g)(h(x)) = f((g ∘ h)(x))
-- Inserting a named intermediate node is just re-association.

import Std

-- ============================================================================
-- Composition Model
-- ============================================================================

/-- Original deeply nested call chain -/
def deepChain (f g h : Int → Int) (x : Int) : Int :=
  f (g (h x))

/-- With intermediate composition node inserted -/
def composedChain (f g h : Int → Int) (x : Int) : Int :=
  let gh := fun x => g (h x)  -- intermediate composition node
  f (gh x)

-- ============================================================================
-- Core Theorem: Composition preserves result
-- ============================================================================

theorem composition_preserves_behavior
    (f g h : Int → Int) (x : Int) :
    deepChain f g h x = composedChain f g h x := by
  simp [deepChain, composedChain]

-- ============================================================================
-- Extended: Composition with 4 functions
-- ============================================================================

def deepChain4 (f g h k : Int → Int) (x : Int) : Int :=
  f (g (h (k x)))

def composedChain4 (f g h k : Int → Int) (x : Int) : Int :=
  let hk := fun x => h (k x)
  let ghk := fun x => g (hk x)
  f (ghk x)

theorem composition4_preserves
    (f g h k : Int → Int) (x : Int) :
    deepChain4 f g h k x = composedChain4 f g h k x := by
  simp [deepChain4, composedChain4]

-- ============================================================================
-- Anti-Vacuity Check
-- ============================================================================

-- NEGATIVE TEST: Should FAIL
-- theorem composition_false : False := by
--   sorry
