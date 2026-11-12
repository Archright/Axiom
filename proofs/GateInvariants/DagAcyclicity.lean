-- DagAcyclicity.lean — Proof that the gate dependency DAG is acyclic.
--
-- Strategy: Exhibit a topological ordering (the `rank` function from GateData)
-- and prove that every edge strictly decreases rank. Since natural numbers
-- are well-founded, no infinite descending chain exists, hence no cycle.

import GateInvariants.GateData

set_option autoImplicit false

-- ============================================================================
-- §1  Reachability (transitive closure of the dependency relation)
-- ============================================================================

inductive Reachable : GateId → GateId → Prop where
  | step   : ∀ {a b}, dependsOn a b → Reachable a b
  | trans  : ∀ {a b c}, Reachable a b → Reachable b c → Reachable a c

-- ============================================================================
-- §2  Every edge strictly decreases rank
-- ============================================================================

/-- Boolean witness: all 13 edges respect the topological rank ordering.
    Verified computationally via native_decide. -/
private theorem edges_respect_rank_witness :
    edges.all (fun (a, b) => decide (rank a > rank b)) = true := by
  native_decide

/-- Formal: every edge (a, b) in the edge list satisfies rank a > rank b.
    Bridge from the boolean witness via List.all_eq_true. -/
theorem edge_rank_decrease :
    ∀ (a b : GateId), (a, b) ∈ edges → rank a > rank b := by
  intro a b h
  have hw := edges_respect_rank_witness
  simp only [List.all_eq_true] at hw
  exact of_decide_eq_true (hw (a, b) h)

-- ============================================================================
-- §3  Reachability preserves rank decrease
-- ============================================================================

/-- If a is reachable from b, then rank a > rank b. -/
theorem reachable_decreases_rank :
    ∀ {a b : GateId}, Reachable a b → rank a > rank b := by
  intro a b h
  induction h with
  | step h_step =>
    exact edge_rank_decrease _ _ h_step
  | trans _ _ ih₁ ih₂ =>
    -- ih₁ : rank a > rank b  (i.e. rank b < rank a)
    -- ih₂ : rank b > rank c  (i.e. rank c < rank b)
    -- goal : rank a > rank c  (i.e. rank c < rank a)
    exact Nat.lt_trans ih₂ ih₁

-- ============================================================================
-- §4  Main Acyclicity Theorem
-- ============================================================================

/-- No gate can reach itself in the dependency graph.
    Proof: if Reachable g g, then rank g > rank g, contradicting Nat.lt_irrefl. -/
theorem dag_acyclic :
    ∀ (g : GateId), ¬Reachable g g := by
  intro g h
  exact absurd (reachable_decreases_rank h) (Nat.lt_irrefl (rank g))
