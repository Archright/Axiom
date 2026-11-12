/-
  Denotation — Tier 1 kernel-inside semantic closure (certification-continuity Phase 3.5).

  Hand-written Lean denotation of the Axiom Core IR over the certified
  (bounded) subset, INDEPENDENT of the Nim renderers:
    - `evalIR`      : Int-valued denotation (Bool results embedded as 0/1).
    - `renderInt`   : Lean-side mirror of the canonical Nim renderer's Int
                      rendering (lowerIRExprToLean) — literals, vars via env,
                      +, -, *, div (Int.tdiv), unary -, if-then-else.
    - `renderIR`    : Lean-side mirror of the canonical Nim renderer's
                      Bool/Prop rendering — <, ≤, >, ≥, =, ∧, ∨, ¬,
                      if-then-else (Bool-valued; the Nim renderer emits Props,
                      this mirror is Bool and the theorem relates `= true`).
    - `Certified`   : structural membership predicate — the certified subset.
                      IRExpr kinds outside the subset have NO Certified proof
                      (explicit failure), and `certifiedSubset` returns false.
    - `render_eq_eval` : kernel-checked soundness theorem — on the certified
                      subset the two Lean-side definitions agree:
                        .int  : renderInt env ir = evalIR env ir
                        .bool : renderIR env ir = true ↔ evalIR env ir ≠ 0
                      Proved by induction on Certified with simp/omega only —
                      NO native_decide, NO sorry, NO trustCompiler. The theorem
                      is honest: it claims agreement of the two hand-written
                      Lean definitions on the certified subset, nothing more
                      (contract §2 wording).

  Nim-semantics scoping of the arithmetic (this file claims only
  renderer ≡ denotation; the Nim relationship holds where Nim itself is
  total, which is exactly what the obligation taxonomy discharges):
    - `mul` is denoted by unbounded Int `*`. Nim `int` is 64-bit signed and
      raises OverflowDefect beyond that width (checked builds); the no-overflow
      obligation (obligation_semantics.md §3.8) plus `preConditions` bound the
      domain, and on the domain the Int values coincide with the BitVec-64
      mirror `evalBv` below (proved, per subject, in the bridge section).
    - `div` is denoted by `Int.tdiv` — truncation toward zero, matching Nim's
      `div` (Lean's `/` floors; they differ on negative operands). Nim raises
      DivByZeroDefect at divisor 0; `tdiv` is total (Lean defines `tdiv x 0 = 0`),
      so the agreement theorem stays unconditional while the divisor ≠ 0 side
      condition is the divSafety obligation (§3.1), not modeled here.
    - `rem` is denoted by `Int.emod` (`%`) — Lean's remainder is nonnegative
      for any nonzero divisor. Nim's `mod` truncates toward zero (sign of the
      dividend); the two coincide when the dividend is nonnegative
      (`Int.tmod_eq_emod_of_nonneg` — no divisor condition), which is the
      rem-domain obligation the renderer's identity segment names
      (`rem=lean-emod/nim-mod/coincident-nonneg-dividend-domain`). Nim raises
      DivByZeroDefect at divisor 0; `emod` is total (`a % 0 = a`), so the
      agreement theorem stays unconditional while the divisor ≠ 0 side
      condition is the divSafety obligation (§3.1), not modeled here. The
      BitVec-64 mirror `evalBv` denotes `rem` by `BitVec.srem`, which equals
      Nim's truncated `mod` at width 64 for every sign combination.

  INV-4: this file is hand-written; ir_def.nim must NOT generate it.
-/

import IR.AxiomIRExpr

open AxiomIR

namespace AxiomDenotation

-- Sort of a certified IR expression: Int-valued or Bool-valued.
inductive IRSort where
  | int | bool

-- ─── Renderers (Lean-side mirrors of the canonical Nim renderer) ───
-- Mutual: Int rendering needs the Bool rendering for if-conditions, and the
-- Bool rendering needs Int rendering for comparison operands.

mutual
  def renderInt (env : String → Int) : IRExpr → Int
    | .lit v => v
    | .var_ name _ => env name
    | .binOp .add l r => renderInt env l + renderInt env r
    | .binOp .sub l r => renderInt env l - renderInt env r
    | .binOp .mul l r => renderInt env l * renderInt env r
    | .binOp .div l r => (renderInt env l).tdiv (renderInt env r)
    | .binOp .rem l r => renderInt env l % renderInt env r
    | .unaryOp .bvNeg a => -renderInt env a
    | .ifThenElse c t e => if renderIR env c then renderInt env t else renderInt env e
    | _ => 0

  def renderIR (env : String → Int) : IRExpr → Bool
    | .binOp .lt l r => decide (renderInt env l < renderInt env r)
    | .binOp .le l r => decide (renderInt env l ≤ renderInt env r)
    | .binOp .gt l r => decide (renderInt env l > renderInt env r)
    | .binOp .ge l r => decide (renderInt env l ≥ renderInt env r)
    | .binOp .eq l r => decide (renderInt env l = renderInt env r)
    | .binOp .ltU l r => decide (renderInt env l < renderInt env r)
    | .binOp .and_ l r => renderIR env l && renderIR env r
    | .binOp .or_ l r => renderIR env l || renderIR env r
    | .unaryOp .not_ a => !renderIR env a
    | .ifThenElse c t e => if renderIR env c then renderIR env t else renderIR env e
    | _ => false
end

-- ─── Denotation ───
-- Int-valued semantics over the certified subset. Bool results are embedded
-- as 1 (true) / 0 (false) — the same embedding ir_to_lean uses for
-- opCastToBv64 (Bool → 1/0). Kinds outside the subset return 0 (fail-closed
-- default); they are excluded from the soundness theorem by `Certified`.
def evalIR (env : String → Int) : IRExpr → Int
  | .lit v => v
  | .var_ name _ => env name
  | .binOp .add l r => evalIR env l + evalIR env r
  | .binOp .sub l r => evalIR env l - evalIR env r
  | .binOp .mul l r => evalIR env l * evalIR env r
  | .binOp .div l r => (evalIR env l).tdiv (evalIR env r)
  | .binOp .rem l r => evalIR env l % evalIR env r
  | .binOp .lt l r => if evalIR env l < evalIR env r then 1 else 0
  | .binOp .le l r => if evalIR env l ≤ evalIR env r then 1 else 0
  | .binOp .gt l r => if evalIR env l > evalIR env r then 1 else 0
  | .binOp .ge l r => if evalIR env l ≥ evalIR env r then 1 else 0
  | .binOp .eq l r => if evalIR env l = evalIR env r then 1 else 0
  | .binOp .ltU l r => if evalIR env l < evalIR env r then 1 else 0
  | .binOp .and_ l r => if evalIR env l ≠ 0 ∧ evalIR env r ≠ 0 then 1 else 0
  | .binOp .or_ l r => if evalIR env l ≠ 0 ∨ evalIR env r ≠ 0 then 1 else 0
  | .unaryOp .not_ a => if evalIR env a = 0 then 1 else 0
  | .unaryOp .bvNeg a => -evalIR env a
  | .ifThenElse c t e => if evalIR env c ≠ 0 then evalIR env t else evalIR env e
  | _ => 0

-- ─── Certified subset membership ───
-- Structural predicate: exactly the certified forms (Int literals, vars,
-- +, -, unary -, comparisons, ∧, ∨, ¬, if-then-else). Any other IRExpr kind
-- has no `Certified` proof — explicit failure for out-of-subset kinds.
inductive Certified : IRExpr → IRSort → Prop where
  | lit (v : Int) : Certified (.lit v) .int
  | var_ (n : String) (t : IRType) : Certified (.var_ n t) .int
  | add {l r : IRExpr} : Certified l .int → Certified r .int → Certified (.binOp .add l r) .int
  | sub {l r : IRExpr} : Certified l .int → Certified r .int → Certified (.binOp .sub l r) .int
  | mul {l r : IRExpr} : Certified l .int → Certified r .int → Certified (.binOp .mul l r) .int
  | div {l r : IRExpr} : Certified l .int → Certified r .int → Certified (.binOp .div l r) .int
  | rem {l r : IRExpr} : Certified l .int → Certified r .int → Certified (.binOp .rem l r) .int
  | neg {a : IRExpr} : Certified a .int → Certified (.unaryOp .bvNeg a) .int
  | lt {l r : IRExpr} : Certified l .int → Certified r .int → Certified (.binOp .lt l r) .bool
  | le {l r : IRExpr} : Certified l .int → Certified r .int → Certified (.binOp .le l r) .bool
  | gt {l r : IRExpr} : Certified l .int → Certified r .int → Certified (.binOp .gt l r) .bool
  | ge {l r : IRExpr} : Certified l .int → Certified r .int → Certified (.binOp .ge l r) .bool
  | eq {l r : IRExpr} : Certified l .int → Certified r .int → Certified (.binOp .eq l r) .bool
  | ltU {l r : IRExpr} : Certified l .int → Certified r .int → Certified (.binOp .ltU l r) .bool
  | and_ {l r : IRExpr} : Certified l .bool → Certified r .bool → Certified (.binOp .and_ l r) .bool
  | or_ {l r : IRExpr} : Certified l .bool → Certified r .bool → Certified (.binOp .or_ l r) .bool
  | not_ {a : IRExpr} : Certified a .bool → Certified (.unaryOp .not_ a) .bool
  | ite {s : IRSort} {c t e : IRExpr} : Certified c .bool → Certified t s → Certified e s → Certified (.ifThenElse c t e) s

-- Decidable membership check (for #eval / tests). `Certified` is the
-- canonical predicate; this Bool function is its decidable companion.
def certifiedSubset : IRExpr → IRSort → Bool
  | .lit _, .int => true
  | .var_ _ _, .int => true
  | .binOp .add l r, .int => certifiedSubset l .int && certifiedSubset r .int
  | .binOp .sub l r, .int => certifiedSubset l .int && certifiedSubset r .int
  | .binOp .mul l r, .int => certifiedSubset l .int && certifiedSubset r .int
  | .binOp .div l r, .int => certifiedSubset l .int && certifiedSubset r .int
  | .binOp .rem l r, .int => certifiedSubset l .int && certifiedSubset r .int
  | .unaryOp .bvNeg a, .int => certifiedSubset a .int
  | .binOp .lt l r, .bool => certifiedSubset l .int && certifiedSubset r .int
  | .binOp .le l r, .bool => certifiedSubset l .int && certifiedSubset r .int
  | .binOp .gt l r, .bool => certifiedSubset l .int && certifiedSubset r .int
  | .binOp .ge l r, .bool => certifiedSubset l .int && certifiedSubset r .int
  | .binOp .eq l r, .bool => certifiedSubset l .int && certifiedSubset r .int
  | .binOp .ltU l r, .bool => certifiedSubset l .int && certifiedSubset r .int
  | .binOp .and_ l r, .bool => certifiedSubset l .bool && certifiedSubset r .bool
  | .binOp .or_ l r, .bool => certifiedSubset l .bool && certifiedSubset r .bool
  | .unaryOp .not_ a, .bool => certifiedSubset a .bool
  | .ifThenElse c t e, s => certifiedSubset c .bool && certifiedSubset t s && certifiedSubset e s
  | _, _ => false

-- ─── Soundness theorem ───
-- `render_eq_eval` : on the certified subset, the Lean-side rendering and the
-- denotation agree (Int: equality; Bool: rendered-true iff denotation ≠ 0).
-- Proved by induction on `Certified` with simp/omega only — kernel-checked,
-- allowlist-clean (see `#print axioms`).

theorem bool_eq_false_iff_not_eq_true (b : Bool) : (b = false ↔ ¬ b = true) := by
  cases b <;> simp

def renderSound (env : String → Int) (ir : IRExpr) (s : IRSort) : Prop :=
  match s with
  | .int => renderInt env ir = evalIR env ir
  | .bool => (renderIR env ir = true ↔ evalIR env ir ≠ 0)

theorem render_eq_eval {env : String → Int} {ir : IRExpr} {s : IRSort}
    (h : Certified ir s) : renderSound env ir s := by
  induction h with
  | lit v => simp [renderSound, renderInt, evalIR]
  | var_ n t => simp [renderSound, renderInt, evalIR]
  | add hl hr ihl ihr =>
      simp [renderSound] at ihl ihr
      simp [renderSound, renderInt, evalIR, ihl, ihr]
  | sub hl hr ihl ihr =>
      simp [renderSound] at ihl ihr
      simp [renderSound, renderInt, evalIR, ihl, ihr]
  | mul hl hr ihl ihr =>
      simp [renderSound] at ihl ihr
      simp [renderSound, renderInt, evalIR, ihl, ihr]
  | div hl hr ihl ihr =>
      simp [renderSound] at ihl ihr
      simp [renderSound, renderInt, evalIR, ihl, ihr]
  | rem hl hr ihl ihr =>
      simp [renderSound] at ihl ihr
      simp [renderSound, renderInt, evalIR, ihl, ihr]
  | neg ha iha =>
      simp [renderSound] at iha
      simp [renderSound, renderInt, evalIR, iha]
  | lt hl hr ihl ihr =>
      simp [renderSound] at ihl ihr
      simp [renderSound, renderIR, evalIR, ihl, ihr]
  | le hl hr ihl ihr =>
      simp [renderSound] at ihl ihr
      simp [renderSound, renderIR, evalIR, ihl, ihr]
  | gt hl hr ihl ihr =>
      simp [renderSound] at ihl ihr
      simp [renderSound, renderIR, evalIR, ihl, ihr]
  | ge hl hr ihl ihr =>
      simp [renderSound] at ihl ihr
      simp [renderSound, renderIR, evalIR, ihl, ihr]
  | eq hl hr ihl ihr =>
      simp [renderSound] at ihl ihr
      simp [renderSound, renderIR, evalIR, ihl, ihr]
  | ltU hl hr ihl ihr =>
      simp [renderSound] at ihl ihr
      simp [renderSound, renderIR, evalIR, ihl, ihr]
  | and_ hl hr ihl ihr =>
      simp [renderSound] at ihl ihr
      simp [renderSound, renderIR, evalIR, ihl, ihr]
  | or_ hl hr ihl ihr =>
      rename_i l r
      simp [renderSound] at ihl ihr
      simp [renderSound, renderIR, evalIR, ihl, ihr]
      by_cases hA : evalIR env l = 0 <;> by_cases hB : evalIR env r = 0 <;> simp [hA, hB]
  | not_ ha iha =>
      simp [renderSound] at iha
      simp [renderSound, renderIR, evalIR, bool_eq_false_iff_not_eq_true, iha]
  | ite hc ht he ihc iht ihe =>
      rename_i s c t e
      cases s
      · simp [renderSound] at ihc iht ihe
        simp [renderSound, renderInt, evalIR, iht, ihe]
        by_cases hb : renderIR env c = true
        · have hP : evalIR env c ≠ 0 := ihc.mp hb
          simp [hb, hP]
        · have hP : evalIR env c = 0 := by
            by_cases hc0 : evalIR env c = 0
            · exact hc0
            · exfalso
              exact hb (ihc.mpr hc0)
          simp [hb, hP]
      · simp [renderSound] at ihc iht ihe
        simp [renderSound, renderIR, evalIR, iht, ihe]
        by_cases hb : renderIR env c = true
        · have hP : evalIR env c ≠ 0 := ihc.mp hb
          simp [hb, hP]
        · have hP : evalIR env c = 0 := by
            by_cases hc0 : evalIR env c = 0
            · exact hc0
            · exfalso
              exact hb (ihc.mpr hc0)
          simp [hb, hP]

-- ─── Corollaries ───
-- The two sorts, exposed as standalone theorems for the acceptance tests.

theorem renderInt_eq_eval {env : String → Int} {ir : IRExpr} (h : Certified ir .int) :
    renderInt env ir = evalIR env ir := by
  exact render_eq_eval (ir := ir) h

theorem renderIR_eq_eval {env : String → Int} {ir : IRExpr} (h : Certified ir .bool) :
    (renderIR env ir = true ↔ evalIR env ir ≠ 0) := by
  exact render_eq_eval (ir := ir) h

-- `Certified` membership implies the decidable check agrees.
theorem certified_certifiedSubset {ir : IRExpr} {s : IRSort} (h : Certified ir s) :
    certifiedSubset ir s = true := by
  induction h <;> simp [certifiedSubset, *]

-- ─── BitVec-64 mirror of the canonical BitVec renderer (ir_to_lean.nim §C) ───
-- Scope: the Int-sorted arithmetic subset of `Certified` — lit, var, +, -, *,
-- div (BitVec.sdiv, truncating like Nim div), rem (BitVec.srem, truncated
-- like Nim mod at every sign combination, w=64), unary -. Comparisons and the
-- Bool sort are outside the evalBv bridge scope (the BitVec renderer maps
-- them to Bool-valued predicates — signed for .lt..-.ge, unsigned `BitVec.ult`
-- for .ltU — a different sort); the .ltU Int-order denotation is instead
-- justified by the `ult_ofInt_domain_eq` domain bridge below.
-- +, -, * wrap at 64 bits exactly like Nim `-d:danger`; the bridge theorems
-- below show the domain precondition rules the wrap out for the subject.

def evalBv (env : String → Int) : IRExpr → BitVec 64
  | .lit v => BitVec.ofInt 64 v
  | .var_ name _ => BitVec.ofInt 64 (env name)
  | .binOp .add l r => evalBv env l + evalBv env r
  | .binOp .sub l r => evalBv env l - evalBv env r
  | .binOp .mul l r => evalBv env l * evalBv env r
  | .binOp .div l r => BitVec.sdiv (evalBv env l) (evalBv env r)
  | .binOp .rem l r => BitVec.srem (evalBv env l) (evalBv env r)
  | .unaryOp .bvNeg a => -evalBv env a
  | _ => 0#64

-- ─── Subject bridge: stew/base36.nim sizing functions ───
-- The IR bodies below are the shapes lowered from nim-stew/stew/base36.nim
--   encodedLength : (length * 277) div 179 + 1
--   decodedLength : (length * 179) div 277
-- Byte-level binding of these trees to the Nim source is Tier-2's extraction
-- agreement (src/verification/extraction_agreement.nim), not assumed here.
-- The domain literal IS the width commitment: base36MaxInput is the largest n
-- with n * 277 ≤ int64Max (int64Max mod 277 = 225), for 64-bit Nim int. The
-- same construction gives 7752648 at 32-bit width and 118 at 16-bit.

private theorem pow63_nat : ((2 : Nat) ^ 63 : Nat) = 9223372036854775808 := rfl
private theorem pow64_nat : ((2 : Nat) ^ 64 : Nat) = 18446744073709551616 := rfl
private theorem pow64_int : (((2 : Nat) ^ 64 : Nat) : Int) = 18446744073709551616 := rfl

private theorem toNat_ofInt64_eq (a : Int) (ha : 0 ≤ a) (hfit : a ≤ 9223372036854775807) :
    (BitVec.ofInt 64 a).toNat = a.toNat := by
  rw [BitVec.toNat_ofInt, Int.emod_eq_of_lt ha (by rw [pow64_int]; omega)]

private theorem toNat_udiv' (x y : BitVec 64) : (x.udiv y).toNat = x.toNat / y.toNat := by
  show (x / y).toNat = x.toNat / y.toNat
  rw [BitVec.toNat_udiv]

/-- boLtU identity bridge: `BitVec.ult` IS the unsigned Nat order — the core
definition is itself `decide (x.toNat < y.toNat)`. Axiom-free (rfl). -/
theorem bitvec_ult_eq_nat_lt (x y : BitVec 64) :
    x.ult y = decide (x.toNat < y.toNat) := rfl

/-- boLtU domain bridge: on the u64 unsigned domain (0 ≤ a, b ≤ 2^64 - 1,
attached outside `Certified` by the producer via aoTypeDerived preConditions),
the unsigned BitVec order and the Int mathematical order agree — the
Int-order denotation of `.ltU` (evalIR/renderIR) is justified against the
emitted `BitVec.ult` (leanBvUlt) exactly there. -/
theorem ult_ofInt_domain_eq (a b : Int)
    (ha : 0 ≤ a) (ha' : a ≤ 18446744073709551615)
    (hb : 0 ≤ b) (hb' : b ≤ 18446744073709551615) :
    (BitVec.ofInt 64 a).ult (BitVec.ofInt 64 b) = decide (a < b) := by
  show decide ((BitVec.ofInt 64 a).toNat < (BitVec.ofInt 64 b).toNat) = decide (a < b)
  rw [BitVec.toNat_ofInt, BitVec.toNat_ofInt]
  rw [Int.emod_eq_of_lt ha (by rw [pow64_int]; omega)]
  rw [Int.emod_eq_of_lt hb (by rw [pow64_int]; omega)]
  exact decide_eq_decide.mpr ⟨fun h => by omega, fun h => by omega⟩

private theorem bv_add_toInt (x y : BitVec 64) (hy : y.toNat = 1)
    (h : x.toNat + 1 < 9223372036854775808) :
    (x + y).toInt = x.toInt + 1 := by
  have hx : x.msb = false := BitVec.msb_eq_false_iff_two_mul_lt.mpr (by
    rw [pow64_nat]; omega)
  have hy0 : y.msb = false := BitVec.msb_eq_false_iff_two_mul_lt.mpr (by
    rw [hy, pow64_nat]; omega)
  have hsum : (x + y).toNat = x.toNat + 1 := by
    rw [BitVec.toNat_add, hy]
    apply Nat.mod_eq_of_lt
    rw [pow64_nat]; omega
  have hr : (x + y).msb = false := BitVec.msb_eq_false_iff_two_mul_lt.mpr (by
    rw [hsum, pow64_nat]; omega)
  rw [BitVec.toInt_eq_toNat_of_msb hr, hsum, BitVec.toInt_eq_toNat_of_msb hx,
    Int.natCast_add, Int.natCast_one]

/-- On nonnegative in-range operands the BitVec-64 rendering of
    `(a * b) sdiv c` computes the unbounded-Int product then truncating
    division at the `toNat` level — the wrap that would diverge from the Int
    denotation is excluded by `habfit`, the no-overflow obligation. -/
private theorem bv_mul_sdiv_toNat (a b c : Int)
    (ha : 0 ≤ a) (hafit : a ≤ 9223372036854775807)
    (hb : 0 ≤ b) (hbfit : b ≤ 9223372036854775807)
    (habfit : a * b ≤ 9223372036854775807)
    (hc : 0 < c) (hcfit : c ≤ 9223372036854775807) :
    ((BitVec.ofInt 64 a * BitVec.ofInt 64 b).sdiv (BitVec.ofInt 64 c)).toNat
      = (a * b).toNat / c.toNat := by
  have hab0 : (0 : Int) ≤ a * b := Int.mul_nonneg ha hb
  have hmul : ((BitVec.ofInt 64 a) * (BitVec.ofInt 64 b)).toNat = (a * b).toNat := by
    rw [BitVec.toNat_mul, toNat_ofInt64_eq a ha hafit, toNat_ofInt64_eq b hb hbfit]
    have h1 : (((a.toNat * b.toNat : Nat) : Int)) = a * b := by
      rw [Int.natCast_mul, Int.toNat_of_nonneg ha, Int.toNat_of_nonneg hb]
    have h2 : (((a * b).toNat : Nat) : Int) = a * b := Int.toNat_of_nonneg hab0
    have heq : (a * b).toNat = a.toNat * b.toNat := by omega
    rw [heq, pow64_nat]
    apply Nat.mod_eq_of_lt
    omega
  have hmsbP : ((BitVec.ofInt 64 a) * (BitVec.ofInt 64 b)).msb = false :=
    BitVec.msb_eq_false_iff_two_mul_lt.mpr (by
      rw [hmul, pow64_nat]
      have h1 : (((a * b).toNat : Nat) : Int) = a * b := Int.toNat_of_nonneg hab0
      omega)
  have hmsbD : (BitVec.ofInt 64 c).msb = false :=
    BitVec.msb_eq_false_iff_two_mul_lt.mpr (by
      rw [toNat_ofInt64_eq c (by omega) hcfit, pow64_nat]
      have h1 : (c.toNat : Int) = c := Int.toNat_of_nonneg (by omega)
      omega)
  rw [BitVec.sdiv_eq]
  simp only [hmsbP, hmsbD]
  rw [toNat_udiv', hmul, toNat_ofInt64_eq c (by omega) hcfit]

/-- The Int-denotation bridge: where the no-overflow obligation holds, the
    BitVec-64 rendering and the Int denotation compute the same value. -/
private theorem bv_mul_sdiv_toInt (a b c : Int)
    (ha : 0 ≤ a) (hafit : a ≤ 9223372036854775807)
    (hb : 0 ≤ b) (hbfit : b ≤ 9223372036854775807)
    (habfit : a * b ≤ 9223372036854775807)
    (hc : 0 < c) (hcfit : c ≤ 9223372036854775807) :
    ((BitVec.ofInt 64 a * BitVec.ofInt 64 b).sdiv (BitVec.ofInt 64 c)).toInt
      = (a * b).tdiv c := by
  have hab0 : (0 : Int) ≤ a * b := Int.mul_nonneg ha hb
  have hnc : (c.toNat : Int) = c := Int.toNat_of_nonneg (by omega)
  have hq : ((BitVec.ofInt 64 a * BitVec.ofInt 64 b).sdiv (BitVec.ofInt 64 c)).toNat
      = (a * b).toNat / c.toNat := bv_mul_sdiv_toNat a b c ha hafit hb hbfit habfit hc hcfit
  have hmsbQ : ((BitVec.ofInt 64 a * BitVec.ofInt 64 b).sdiv (BitVec.ofInt 64 c)).msb
      = false := BitVec.msb_eq_false_iff_two_mul_lt.mpr (by
    rw [hq, pow64_nat]
    have h1 : (((a * b).toNat : Nat) : Int) = a * b := Int.toNat_of_nonneg hab0
    have h2 : ((a * b).toNat / c.toNat : Nat) ≤ (a * b).toNat := Nat.div_le_self _ _
    omega)
  rw [BitVec.toInt_eq_toNat_of_msb hmsbQ, hq, Int.tdiv_eq_ediv_of_nonneg hab0,
    Int.natCast_ediv, Int.toNat_of_nonneg hab0, hnc]

def base36EncIR : IRExpr :=
  .binOp .add (.binOp .div (.binOp .mul (.var_ "length" .bitVec64) (.lit 277)) (.lit 179)) (.lit 1)

def base36DecIR : IRExpr :=
  .binOp .div (.binOp .mul (.var_ "length" .bitVec64) (.lit 179)) (.lit 277)

def encLen (n : Int) : Int := evalIR (fun _ => n) base36EncIR
def decLen (e : Int) : Int := evalIR (fun _ => e) base36DecIR

def base36MaxInput : Int := 33297371974204966
def int64Max : Int := 9223372036854775807

theorem encLen_eq (n : Int) : encLen n = (n * 277).tdiv 179 + 1 := rfl
theorem decLen_eq (e : Int) : decLen e = (e * 179).tdiv 277 := rfl

/-- Roundtrip on the width-committed domain: the encoded length re-decodes
    exactly. All operands are nonnegative on the domain, so Nim's truncating
    `div` (denoted `Int.tdiv`) is exercised, never the negative-operand
    floor/truncate divergence. -/
theorem base36_roundtrip (n : Int) (hn : 0 ≤ n ∧ n ≤ base36MaxInput) :
    decLen (encLen n) = n := by
  simp only [decLen_eq, encLen_eq]
  have h1 : (0 : Int) ≤ n * 277 := by omega
  rw [Int.tdiv_eq_ediv_of_nonneg h1]
  have h3 : (0 : Int) ≤ ((n * 277) / 179 + 1) * 179 := by omega
  rw [Int.tdiv_eq_ediv_of_nonneg h3]
  omega

/-- `encodedLength ≥ 1` on the domain — the slice's positivity claim. -/
theorem encLen_pos (n : Int) (hn : 0 ≤ n) : 1 ≤ encLen n := by
  simp only [encLen_eq]
  have h1 : (0 : Int) ≤ n * 277 := by omega
  rw [Int.tdiv_eq_ediv_of_nonneg h1]
  omega

/-- No-overflow for `encodedLength`'s `length * 277`: the Int denotation stays
    within Nim's checked 64-bit int on the domain (margin 225 at the boundary). -/
theorem encLen_mul_no_overflow (n : Int) (hn : 0 ≤ n ∧ n ≤ base36MaxInput) :
    n * 277 ≤ int64Max := by
  have hn1 : n ≤ 33297371974204966 := hn.2
  simp only [int64Max]
  omega

/-- No-overflow for `decodedLength`'s `encodedLength(length) * 179` — the
    binding constraint (margin 61 at the boundary; `int64Max mod 277 = 225`). -/
theorem decLen_mul_no_overflow (n : Int) (hn : 0 ≤ n ∧ n ≤ base36MaxInput) :
    encLen n * 179 ≤ int64Max := by
  have hn1 : n ≤ 33297371974204966 := hn.2
  simp only [encLen_eq, int64Max]
  have h1 : (0 : Int) ≤ n * 277 := by omega
  rw [Int.tdiv_eq_ediv_of_nonneg h1]
  omega

/-- The domain is exactly tight: the next integer overflows Nim's checked
    64-bit int at `length * 277` (OverflowDefect), so inputs beyond
    `base36MaxInput` must be rejected by the precondition — the roundtrip is
    not provable there, and wrapping semantics would not preserve it either. -/
theorem base36_domain_tight : (base36MaxInput + 1) * 277 > int64Max := by
  simp only [base36MaxInput, int64Max]
  omega

/-- BitVec-64 bridge for `encodedLength`: the rendered BitVec-64 function
    computes the Int denotation exactly on the domain (read back via `toInt`). -/
theorem evalBv_enc_toInt (n : Int) (hn : 0 ≤ n ∧ n ≤ base36MaxInput) :
    (evalBv (fun _ => n) base36EncIR).toInt = encLen n := by
  have hn1 : n ≤ 33297371974204966 := hn.2
  simp only [evalBv, base36EncIR, encLen_eq]
  have hsmall : ((BitVec.ofInt 64 n * BitVec.ofInt 64 277).sdiv (BitVec.ofInt 64 179)).toNat
      + 1 < 9223372036854775808 := by
    have h179 : ((179 : Int).toNat : Nat) = 179 := rfl
    have h1 : ((BitVec.ofInt 64 n * BitVec.ofInt 64 277).sdiv (BitVec.ofInt 64 179)).toNat
        = (n * 277).toNat / (179 : Int).toNat :=
      bv_mul_sdiv_toNat n 277 179 hn.1 (by omega) (by omega) (by omega) (by omega)
        (by omega) (by omega)
    rw [h1, h179, ← pow63_nat]
    have h2 : ((n * 277).toNat : Int) = n * 277 := Int.toNat_of_nonneg (by omega)
    omega
  rw [bv_add_toInt _ _ rfl hsmall, bv_mul_sdiv_toInt n 277 179 hn.1 (by omega) (by omega)
    (by omega) (by omega) (by omega) (by omega)]

/-- BitVec-64 bridge for `decodedLength` at an in-range intermediate value. -/
theorem evalBv_dec_toInt (v : Int) (hv0 : 0 ≤ v) (hvfit : v * 179 ≤ 9223372036854775807) :
    (evalBv (fun _ => v) base36DecIR).toInt = decLen v := by
  simp only [evalBv, base36DecIR, decLen_eq]
  exact bv_mul_sdiv_toInt v 179 277 hv0 (by omega) (by omega) (by omega) hvfit
    (by omega) (by omega)

/-- End-to-end BitVec-64 composition: run the rendered `encodedLength` as a
    BitVec-64 function, read the result back through `toInt`, feed it to the
    rendered `decodedLength`, read back — the value is `n`. This is the
    kernel-checked statement that the two renderers (BitVec-64 and Int) do not
    silently disagree on the subject. -/
theorem evalBv_roundtrip (n : Int) (hn : 0 ≤ n ∧ n ≤ base36MaxInput) :
    (evalBv (fun _ => (evalBv (fun _ => n) base36EncIR).toInt) base36DecIR).toInt = n := by
  have hv0 : (0 : Int) ≤ encLen n := by
    have := encLen_pos n hn.1; omega
  have hvfit : encLen n * 179 ≤ 9223372036854775807 := decLen_mul_no_overflow n hn
  rw [evalBv_enc_toInt n hn, evalBv_dec_toInt (encLen n) hv0 hvfit, base36_roundtrip n hn]

end AxiomDenotation
