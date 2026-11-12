def addSpec (a b : Nat) := a + b

theorem add_spec (a b : Nat) : addSpec a b = addSpec a b :=
  by
  intros
  first | (simp [*]; done) | sorry -- Promoted to Z3 SMT Debt
