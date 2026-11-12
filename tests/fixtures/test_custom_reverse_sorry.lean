/- Intentional sorry for vacuity check testing -/
inductive MyList (α : Type) where
  | nil : MyList α
  | cons : α → MyList α → MyList α

@[simp] def my_concat {α : Type} (xs ys : MyList α) : MyList α :=
  match xs with
  | MyList.nil => ys
  | MyList.cons h t => MyList.cons h (my_concat t ys)

theorem my_concat_assoc {α : Type} (xs ys zs : MyList α) :
    my_concat (my_concat xs ys) zs = my_concat xs (my_concat ys zs) :=
  /- AXIOM_PROOF_BEGIN -/
  sorry
  /- AXIOM_PROOF_END -/
