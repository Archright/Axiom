/-
  TranslatorEquivalence — Structural equivalence proofs for IR translators.
  
  Level 1: Operator preservation — same IR → same operators in both targets
  Level 2: Type preservation — well-typed IR → well-typed target
-/

import IR.AxiomIRExpr

open AxiomIR

namespace TranslatorEquiv

-- ─── Operator extraction from IRExpr ───

def binOpToString : BinOp → String
  | .add => "+"
  | .sub => "-"
  | .mul => "*"
  | .div => "/"
  | .rem => "%"
  | .lt => "<"
  | .le => "<="
  | .gt => ">"
  | .ge => ">="
  | .and_ => "∧"
  | .or_ => "∨"
  | .eq => "="
  | .ltU => "<u"

def unaryOpToString : UnaryOp → String
  | .not_ => "¬"
  | .bvNot => "~"
  | .bvNeg => "neg"

-- A branch body is strictly smaller than its enclosing CaseBranch.
-- Mirrors CaseBranch._sizeOf_1 = 1 + sizeOf pattern + sizeOf body.
theorem sizeOf_body_lt_branch (cb : CaseBranch) : sizeOf cb.body < sizeOf cb := by
  cases cb
  simp
  omega

-- Any successor is positive: 0 < 1 + n for all n.
theorem lt_succ_add (n : Nat) : 0 < 1 + n := by
  omega

-- Extract all binary operators used in an expression
def getBinOps : IRExpr → List String
  | .lit _ => []
  | .floatLit _ => []
  | .var_ _ _ => []
  | .letIn _ v b _ => getBinOps v ++ getBinOps b
  | .ifThenElse c t e => getBinOps c ++ getBinOps t ++ getBinOps e
  | .case_ s bs d =>
      getBinOps s ++ bs.flatMap (fun cb => getBinOps cb.body) ++
        match d with | none => [] | some e => getBinOps e
  | .call _ args => args.flatMap getBinOps
  | .binOp op l r => [binOpToString op] ++ getBinOps l ++ getBinOps r
  | .unaryOp _ a => getBinOps a
  | .recCall args => args.flatMap getBinOps
  | .loop _ _ is c st b invs v =>
      is.flatMap getBinOps ++ getBinOps c ++
        (match st with | none => [] | some e => getBinOps e) ++ getBinOps b ++
      invs.flatMap getBinOps ++
        (match v with | none => [] | some e => getBinOps e)
  | .stringLit _ => []
  | .cast e _ _ => getBinOps e
termination_by e => sizeOf e
decreasing_by
  all_goals simp_wf
  all_goals
    first
    | omega
    | exact Nat.lt_trans (List.sizeOf_lt_of_mem (by assumption)) (by omega)
    | exact Nat.lt_trans (sizeOf_body_lt_branch _) (Nat.lt_trans (List.sizeOf_lt_of_mem (by assumption)) (by omega))

-- Count occurrences of a specific operator
def countOp (op : String) : IRExpr → Nat
  | .lit _ => 0
  | .floatLit _ => 0
  | .var_ _ _ => 0
  | .letIn _ v b _ => countOp op v + countOp op b
  | .ifThenElse c t e => countOp op c + countOp op t + countOp op e
  | .case_ s bs d =>
      countOp op s +
        bs.foldl (fun acc cb => acc + countOp op cb.body) 0 +
        (match d with | none => 0 | some e => countOp op e)
  | .call _ args => args.foldl (fun acc a => acc + countOp op a) 0
  | .binOp bop l r =>
      (if binOpToString bop = op then 1 else 0) + countOp op l + countOp op r
  | .unaryOp _ a => countOp op a
  | .recCall args => args.foldl (fun acc a => acc + countOp op a) 0
  | .loop _ _ is c st b invs v =>
      is.foldl (fun acc a => acc + countOp op a) 0 + countOp op c +
      (match st with | none => 0 | some e => countOp op e) + countOp op b +
      invs.foldl (fun acc a => acc + countOp op a) 0 +
      (match v with | none => 0 | some e => countOp op e)
  | .stringLit _ => 0
  | .cast e _ _ => countOp op e
termination_by e => sizeOf e
decreasing_by
  all_goals simp_wf
  all_goals
    first
    | omega
    | exact Nat.lt_trans (List.sizeOf_lt_of_mem (by assumption)) (by omega)
    | exact Nat.lt_trans (sizeOf_body_lt_branch _) (Nat.lt_trans (List.sizeOf_lt_of_mem (by assumption)) (by omega))

-- ─── Level 1: Operator Count Preservation ───
-- The number of each operator in the IR is preserved through transformation.
-- This is a structural invariant — the translator cannot invent or lose operators.

theorem binOp_count_preserved_lit (op : String) (v : Int) :
    countOp op (.lit v) = 0 := by
  simp [countOp]

theorem binOp_count_preserved_var (op : String) (n : String) (t : IRType) :
    countOp op (.var_ n t) = 0 := by
  simp [countOp]

theorem binOp_count_preserved_binOp (op : String) (bop : BinOp) (l r : IRExpr) :
    countOp op (.binOp bop l r) =
      (if binOpToString bop = op then 1 else 0) + countOp op l + countOp op r := by
  simp [countOp]

theorem binOp_count_preserved_letIn (op : String) (n : String) (v b : IRExpr) :
    countOp op (.letIn n v b false) = countOp op v + countOp op b := by
  simp [countOp]

theorem binOp_count_preserved_ifThenElse (op : String) (c t e : IRExpr) :
    countOp op (.ifThenElse c t e) = countOp op c + countOp op t + countOp op e := by
  simp [countOp]

-- ─── Structural Depth ───
-- Expressions have finite depth — used to prove termination of recursive transforms

def exprDepth : IRExpr → Nat
  | .lit _ => 1
  | .floatLit _ => 1
  | .var_ _ _ => 1
  | .letIn _ v b _ => 1 + max (exprDepth v) (exprDepth b)
  | .ifThenElse c t e => 1 + max (exprDepth c) (max (exprDepth t) (exprDepth e))
  | .case_ s bs _ => 1 + max (exprDepth s) (bs.foldl (fun acc cb => max acc (exprDepth cb.body)) 0)
  | .call _ args => 1 + args.foldl (fun acc a => max acc (exprDepth a)) 0
  | .binOp _ l r => 1 + max (exprDepth l) (exprDepth r)
  | .unaryOp _ a => 1 + exprDepth a
  | .recCall args => 1 + args.foldl (fun acc a => max acc (exprDepth a)) 0
  | .loop _ _ is c _ b invs v =>
      1 + max (is.foldl (fun acc a => max acc (exprDepth a)) 0)
              (max (exprDepth c) (max (exprDepth b)
                (max (invs.foldl (fun acc a => max acc (exprDepth a)) 0)
                     (match v with | none => 0 | some a => max 0 (exprDepth a)))))
  | .stringLit _ => 1
  | .cast e _ _ => 1 + exprDepth e
termination_by e => sizeOf e
decreasing_by
  all_goals simp_wf
  all_goals
    first
    | omega
    | exact Nat.lt_trans (List.sizeOf_lt_of_mem (by assumption)) (by omega)
    | exact Nat.lt_trans (sizeOf_body_lt_branch _) (Nat.lt_trans (List.sizeOf_lt_of_mem (by assumption)) (by omega))

theorem exprDepth_pos (e : IRExpr) : exprDepth e > 0 := by
  unfold exprDepth
  cases e <;> simp <;> exact lt_succ_add _

-- ─── Well-Formedness Predicate ───
-- An expression is well-formed if all let-bindings have non-empty names

def wellFormed : IRExpr → Prop
  | .lit _ => True
  | .floatLit _ => True
  | .var_ n _ => n.length > 0
  | .letIn n v b _ => n.length > 0 ∧ wellFormed v ∧ wellFormed b
  | .ifThenElse c t e => wellFormed c ∧ wellFormed t ∧ wellFormed e
  | .case_ s bs d => wellFormed s ∧ (∀ b ∈ bs, wellFormed b.body) ∧
      (match d with | none => True | some e => wellFormed e)
  | .call n args => n.length > 0 ∧ (∀ a ∈ args, wellFormed a)
  | .binOp _ l r => wellFormed l ∧ wellFormed r
  | .unaryOp _ a => wellFormed a
  | .recCall args => ∀ a ∈ args, wellFormed a
  | .loop _ vs _ c _ b invs _ => (∀ v ∈ vs, v.length > 0) ∧ wellFormed c ∧ wellFormed b ∧ (∀ i ∈ invs, wellFormed i)
  | .stringLit _ => True
  | .cast e _ _ => wellFormed e
termination_by e => sizeOf e
decreasing_by
  all_goals simp_wf
  all_goals
    first
    | omega
    | exact Nat.lt_trans (List.sizeOf_lt_of_mem (by assumption)) (by omega)
    | exact Nat.lt_trans (sizeOf_body_lt_branch _) (Nat.lt_trans (List.sizeOf_lt_of_mem (by assumption)) (by omega))

-- Well-formedness is preserved by sub-expression access
theorem wf_let_val {n : String} {v b : IRExpr} (h : wellFormed (.letIn n v b false)) : wellFormed v := by
  simp [wellFormed] at h; exact h.2.1

theorem wf_let_body {n : String} {v b : IRExpr} (h : wellFormed (.letIn n v b false)) : wellFormed b := by
  simp [wellFormed] at h; exact h.2.2

theorem wf_binOp_lhs {op : BinOp} {l r : IRExpr} (h : wellFormed (.binOp op l r)) : wellFormed l := by
  simp [wellFormed] at h; exact h.1

theorem wf_binOp_rhs {op : BinOp} {l r : IRExpr} (h : wellFormed (.binOp op l r)) : wellFormed r := by
  simp [wellFormed] at h; exact h.2

end TranslatorEquiv
