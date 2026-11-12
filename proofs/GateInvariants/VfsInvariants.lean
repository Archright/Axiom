-- VfsInvariants.lean — Proofs about the Merkle VFS root hash.
--
-- The VFS root hash is computed by pairwise reduction of file content hashes.
-- This module proves structural properties of the reduction process.

set_option autoImplicit false

-- ============================================================================
-- §1  Pairwise Reduction
-- ============================================================================

/-- Pairwise combine: for each adjacent pair (h1, h2), produce (h1 ++ h2).
    For odd-length lists, the last element is promoted as-is. -/
def pairwiseCombine (hashes : List String) : List String :=
  match hashes with
  | [] => []
  | [h] => [h]
  | h1 :: h2 :: rest => (h1 ++ h2) :: pairwiseCombine rest

/-- Tight length bound: pairwiseCombine produces at most ⌈n/2⌉ elements.
    Encoded as `2 * result ≤ l.length + 1` to stay within omega's linear
    integer arithmetic. -/
private theorem pairwiseCombine_length_le : ∀ (l : List String),
    2 * (pairwiseCombine l).length ≤ l.length + 1
  | [] => by simp [pairwiseCombine]
  | [_] => by simp [pairwiseCombine]
  | _ :: _ :: rest => by
    simp [pairwiseCombine]
    have ih := pairwiseCombine_length_le rest
    omega

/-- PairwiseCombine reduces length: result has strictly fewer elements when
    input has ≥ 2 elements. -/
theorem pairwiseCombine_shorter (hashes : List String) :
    hashes.length ≥ 2 → (pairwiseCombine hashes).length < hashes.length := by
  intro hlen
  match hashes with
  | [] => simp at hlen
  | [_] => simp at hlen
  | h1 :: h2 :: rest =>
    simp [pairwiseCombine]
    have hpc := pairwiseCombine_length_le rest
    omega

-- ============================================================================
-- §2  Iterated Pairwise Reduction (VFS Root)
-- ============================================================================

/-- Compute VFS root by repeated pairwise reduction with explicit fuel. -/
def vfsRoot (hashes : List String) (fuel : Nat) : List String :=
  match fuel with
  | 0 => hashes
  | n + 1 =>
    match hashes with
    | [] => []
    | [_] => hashes
    | _ => vfsRoot (pairwiseCombine hashes) n

/-- VFS root of a single hash is that hash itself (fixed point). -/
theorem vfsRoot_single (h : String) (fuel : Nat) :
    vfsRoot [h] fuel = [h] := by
  match fuel with
  | 0 => simp [vfsRoot]
  | n + 1 => simp [vfsRoot]

/-- VFS root of an empty list is empty. -/
theorem vfsRoot_empty (fuel : Nat) :
    vfsRoot [] fuel = [] := by
  match fuel with
  | 0 => simp [vfsRoot]
  | n + 1 => simp [vfsRoot]

-- ============================================================================
-- §3  Injectivity of Single-Element Roots
-- ============================================================================

/-- Two distinct single-element lists remain distinct after any number of
    reduction rounds (since single elements are promoted as-is). -/
theorem vfsRoot_single_injective (h1 h2 : String) (fuel : Nat) :
    h1 ≠ h2 → vfsRoot [h1] fuel ≠ vfsRoot [h2] fuel := by
  intro hneq
  simp [vfsRoot_single]
  exact hneq

-- ============================================================================
-- §4  Convergence
-- ============================================================================

/-- Fuel bound: when fuel ≥ list length, vfsRoot reduces to at most one element.
    Proved by induction on fuel; each round the pairwise combine strict-length
    property (via pairwiseCombine_length_le) guarantees progress. -/
private theorem vfsRoot_length_le_fuel (hashes : List String) (fuel : Nat) :
    hashes.length ≤ fuel → (vfsRoot hashes fuel).length ≤ 1 := by
  intro hle
  induction fuel generalizing hashes with
  | zero =>
    simp [vfsRoot]; omega
  | succ n ih =>
    match hashes with
    | [] => simp [vfsRoot]
    | [_] => simp [vfsRoot]
    | h1 :: h2 :: rest =>
      simp only [vfsRoot]
      apply ih
      have hpc := pairwiseCombine_length_le (h1 :: h2 :: rest)
      simp only [List.length_cons] at hpc hle
      omega

/-- After enough rounds, any non-empty list reduces to at most one element.
    Proof: pairwiseCombine_length_le ensures each round reduces length,
    so after `hashes.length` rounds we reach ≤ 1. -/
theorem vfsRoot_converges (hashes : List String) (_hne : hashes ≠ []) :
    ∃ fuel, (vfsRoot hashes fuel).length ≤ 1 := by
  exact ⟨hashes.length, vfsRoot_length_le_fuel hashes hashes.length (by omega)⟩

/-- The VFS root hash is deterministic: same input always produces same output. -/
theorem vfsRoot_deterministic (hashes : List String) (fuel : Nat) :
    vfsRoot hashes fuel = vfsRoot hashes fuel := by
  rfl

-- ============================================================================
-- §5  PairwiseCombine Properties
-- ============================================================================

/-- Empty input produces empty output. -/
theorem pairwiseCombine_nil : pairwiseCombine [] = [] := by
  simp [pairwiseCombine]

/-- Single element is promoted as-is. -/
theorem pairwiseCombine_singleton (h : String) : pairwiseCombine [h] = [h] := by
  simp [pairwiseCombine]

/-- Two elements are combined into one. -/
theorem pairwiseCombine_pair (a b : String) :
    pairwiseCombine [a, b] = [a ++ b] := by
  simp [pairwiseCombine]
