theorem positive_spec (x : {x : Nat // (x > 0)}) : x.1 > 0 :=
  by
  intros
  first | (simp [*]; done) | sorry -- Promoted to Z3 SMT Debt
