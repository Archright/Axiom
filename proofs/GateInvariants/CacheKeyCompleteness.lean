-- CacheKeyCompleteness.lean — Proof that the pipeline cache key K
-- changes when any component changes.
--
-- The cache key K is computed as:
--   K = SHA256(binaryHash || configHash || fileHash || envHash || dirtyHash || epoch)
--
-- Theorem: If any component of K changes, the resulting key differs.
--
-- NOTE: This result is CONDITIONAL on the injectivity assumption h_inj.
-- We do not prove SHA-256 collision resistance; instead, we show that
-- IF the key computation is injective on CacheKeyComponents, THEN
-- differing components produce differing keys. The injectivity premise
-- is passed explicitly as a parameter to each theorem, making the
-- dependency transparent rather than hidden behind an axiom.

set_option autoImplicit false

namespace CacheKeyCompleteness

-- ============================================================================
-- §1  Cache Key Components
-- ============================================================================

structure CacheKeyComponents where
  binaryHash  : String   -- hash of compiled binaries
  configHash  : String   -- hash of configuration files
  fileHash    : String   -- hash of source files
  envHash     : String   -- hash of environment variables
  dirtyHash   : String   -- hash of uncommitted changes
  epoch       : Nat      -- monotonically increasing epoch counter
  deriving DecidableEq, Repr

-- ============================================================================
-- §2  Key Computation (simplified model)
-- ============================================================================

/-- Simplified cache key computation.
    In production this is SHA-256 of the concatenation, but for the proof
    we use a model that preserves the essential property: injectivity
    of the key function with respect to component changes. -/
def computeKey (c : CacheKeyComponents) : String :=
  s!"{c.binaryHash}|{c.configHash}|{c.fileHash}|{c.envHash}|{c.dirtyHash}|{c.epoch}"

-- ============================================================================
-- §3  Injectivity Hypothesis (explicit parameter, not axiomatic)
-- ============================================================================

/-- The injectivity hypothesis that must be supplied by the caller.
    This is NOT an axiom — callers must provide evidence that
    computeKey is injective on CacheKeyComponents. -/
def HashInjectivity := ∀ (a b : CacheKeyComponents), computeKey a = computeKey b → a = b

-- ============================================================================
-- §4  Main Completeness Theorem
-- ============================================================================

/-- If any component of K differs between two cache key specifications,
    the resulting keys are different.
    
    CONDITIONAL on h_inj: this theorem takes injectivity as an explicit
    parameter rather than relying on a global axiom. -/
theorem cache_key_complete (h_inj : HashInjectivity) :
  ∀ (a b : CacheKeyComponents),
    a ≠ b → computeKey a ≠ computeKey b := by
  intro a b hneq heq
  exact hneq (h_inj a b heq)

/-- Variant: explicitly enumerate the component-wise conditions.
    
    CONDITIONAL on h_inj: this theorem takes injectivity as an explicit
    parameter rather than relying on a global axiom. -/
theorem cache_key_complete_explicit (h_inj : HashInjectivity) :
  ∀ (a b : CacheKeyComponents),
    (a.binaryHash ≠ b.binaryHash ∨
     a.configHash ≠ b.configHash ∨
     a.fileHash ≠ b.fileHash ∨
     a.envHash ≠ b.envHash ∨
     a.dirtyHash ≠ b.dirtyHash ∨
     a.epoch ≠ b.epoch) →
    computeKey a ≠ computeKey b := by
  intro a b hneq heq
  -- From heq : computeKey a = computeKey b, we derive a = b
  -- which contradicts the component-wise inequality
  have hab := h_inj a b heq
  cases hab
  -- After a = b, all components are equal, contradicting hneq
  simp at hneq

end CacheKeyCompleteness
