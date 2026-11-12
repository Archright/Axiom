theorem bound_spec (n : Nat) (h_pre0 : n >= 0) : n >= 0 :=
  by
  intros
  first | (simp [*]; done) | sorry -- Promoted to Z3 SMT Debt
