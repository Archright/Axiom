theorem rev_auto (xs : List Nat) : True :=
  by
  induction xs with
  | nil => trivial
  | cons head tail ih => simp [ih]
