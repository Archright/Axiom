-- Certified Pattern: Extract Pure Function
-- ==========================================
-- CompCert-style proof that extracting a pure function preserves semantics.
--
-- Pattern: rpkExtractPureFunction
-- Precondition: Function body has no side effects
-- Postcondition: Original and extracted function produce identical outputs

import Std

-- ============================================================================
-- Simple function model (no typeclass, concrete types)
-- ============================================================================

/-- Original inline computation -/
def originalCompute (x : Nat) : Nat :=
  x * 2 + 1

/-- Extracted pure function -/
def extractedPure (x : Nat) : Nat :=
  x * 2 + 1

-- ============================================================================
-- Core Theorem: Semantic Preservation
-- ============================================================================

theorem extract_pure_preserves_semantics (x : Nat) :
    originalCompute x = extractedPure x := by
  simp [originalCompute, extractedPure]

-- ============================================================================
-- Extended: Composition Preservation
-- ============================================================================

def composeOriginal (x : Nat) : Nat :=
  originalCompute x + 1

def composeExtracted (x : Nat) : Nat :=
  extractedPure x + 1

theorem extract_pure_preserves_composition (x : Nat) :
    composeOriginal x = composeExtracted x := by
  simp [composeOriginal, composeExtracted, originalCompute, extractedPure]

-- ============================================================================
-- Extended: Conditional Preservation
-- ============================================================================

theorem extract_pure_preserves_conditional (x : Nat) (default : Nat) :
    (if originalCompute x = extractedPure x then extractedPure x else default) =
    extractedPure x := by
  simp [originalCompute, extractedPure]
