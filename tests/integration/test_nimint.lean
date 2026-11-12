-- tests/integration/test_nimint.lean
-- Integration test for NimInt type mapping and Int.natCast_nonneg fix.
-- This file is prepended with prelude.lean content by the Nim test runner.
-- The prelude wraps definitions in `namespace AxiomPrelude`, so we open it.

open AxiomPrelude

-- Test 1: Verify the prelude-defined NimInt_nonneg theorem exists and is provable
theorem test_prelude_NimInt_nonneg : ∀ (n : Nat), (n : NimInt) ≥ 0 := by
  intro n
  exact NimInt_nonneg n

-- Test 2: Verify NimInt is an abbreviation for Int
theorem test_nimint_is_int : NimInt = Int := by
  rfl

-- Test 3: Verify NimNat is an abbreviation for Nat
theorem test_nimnat_is_nat : NimNat = Nat := by
  rfl

-- Test 4: NimSeq_length_nonneg from prelude is accessible
theorem test_seq_length_nonneg {α} (s : NimSeq α) : s.length ≥ 0 := by
  exact NimSeq_length_nonneg s
