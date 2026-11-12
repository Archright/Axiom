import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
{.push noSideEffect.}

## Axiom Lemmas Catalog (Hierarchical Lemma Abstraction)
##
## Reusable, pre-verified lemmas for common proof patterns.
## These lemmas are referenced by the semantic theorem builder and
## verification gates instead of being re-proved inline in every
## function certificate.  This reduces per-function Lean proof size
## and prevents state-space explosion during BMC.
##
## All entries are pure data — zero I/O, zero side effects.

import std/strutils
import std/options

# ---------------------------------------------------------------------------
# Lemma Category
# ---------------------------------------------------------------------------

type
  LemmaCategory* = enum
    lcLengthNonNeg      ## .len / .size ≥ 0
    lcIndexInBounds     ## 0 ≤ i < len(xs)
    lcArithmetic        ## Nat subtraction, monotonicity
    lcBoolExhaustive    ## b = true ∨ b = false
    lcStringOps         ## String concatenation length

# ---------------------------------------------------------------------------
# Lemma Mapping
# ---------------------------------------------------------------------------

type
  LemmaMapping* = object
    lemmaId*: string        ## Unique identifier (e.g. "axiom.seq.len_nonneg")
    nimPattern*: string     ## Nim source pattern this lemma applies to
    leanStatement*: string  ## Full Lean theorem statement
    smtPattern*: string     ## SMT-LIB assertion pattern
    category*: LemmaCategory
    verified*: bool

# ---------------------------------------------------------------------------
# Canonical Import Module for Semantic Lemmas
# ---------------------------------------------------------------------------

# @axiom-hint: lean="depth >= 0" smt="(assert (>= depth 0))"
func semanticLemmaImportModule*(): string {.raises: [], noSideEffect.} =
  "lib.MemorySafety"

# ---------------------------------------------------------------------------
# Lemma Catalog (SSOT)
# ---------------------------------------------------------------------------

const lemmaCatalog*: seq[LemmaMapping] = @[
  # ── lcLengthNonNeg ──────────────────────────────────────────────────
  LemmaMapping(
    lemmaId: "axiom.seq.len_nonneg",
    nimPattern: "len(xs)",
    leanStatement: "theorem seq_len_nonneg {α : Type} (xs : List α) : xs.length ≥ 0 := by simp",
    smtPattern: "(assert (>= (seq.len xs) 0))",
    category: lcLengthNonNeg,
    verified: true
  ),
  LemmaMapping(
    lemmaId: "axiom.string.len_nonneg",
    nimPattern: "s.len",
    leanStatement: "theorem string_len_nonneg (s : String) : s.length ≥ 0 := by simp",
    smtPattern: "(assert (>= (str.len s) 0))",
    category: lcLengthNonNeg,
    verified: true
  ),

  # ── lcIndexInBounds ─────────────────────────────────────────────────
  LemmaMapping(
    lemmaId: "axiom.index_in_bounds",
    nimPattern: "xs[i]",
    leanStatement: "theorem index_in_bounds {α : Type} (xs : List α) (i : Nat) : i < xs.length → xs.get? i ≠ none := by simp",
    smtPattern: "(assert (=> (and (>= i 0) (< i (seq.len xs))) (not (= (seq.nth xs i) invalid))))",
    category: lcIndexInBounds,
    verified: true
  ),

  # ── lcArithmetic ────────────────────────────────────────────────────
  LemmaMapping(
    lemmaId: "axiom.nat_sub_nonneg",
    nimPattern: "a - b",
    leanStatement: "theorem nat_sub_nonneg (a b : Nat) : a ≥ b → a - b ≥ 0 := by intro h; exact Nat.sub_nonneg h",
    smtPattern: "(assert (=> (>= a b) (>= (- a b) 0)))",
    category: lcArithmetic,
    verified: true
  ),

  # ── lcBoolExhaustive ────────────────────────────────────────────────
  LemmaMapping(
    lemmaId: "axiom.bool_cases",
    nimPattern: "b : bool",
    leanStatement: "theorem bool_cases (b : Bool) : b = true ∨ b = false := by cases b <;> simp",
    smtPattern: "(assert (or (= b true) (= b false)))",
    category: lcBoolExhaustive,
    verified: true
  ),

  # ── lcStringOps ─────────────────────────────────────────────────────
  LemmaMapping(
    lemmaId: "axiom.string_concat_len",
    nimPattern: "a & b",
    leanStatement: "theorem string_concat_len (a b : String) : (a ++ b).length = a.length + b.length := by simp",
    smtPattern: "(assert (= (str.len (str.++ a b)) (+ (str.len a) (str.len b))))",
    category: lcStringOps,
    verified: true
  )
]

# ---------------------------------------------------------------------------
# Lookup Functions
# ---------------------------------------------------------------------------

# @axiom-hint: lean="name.length ≥ 0" smt="(assert (and (>= (str.len name) 0)))"
# @axiom-hint: lean="(lemmaCatalog ≥ 0)" smt="(assert (and (>= lemmaCatalog 0)))"
func findLemmaByName*(name: string): Option[LemmaMapping] {.raises: [].} =
  for lemma in lemmaCatalog:
    if lemma.lemmaId == name:
      return some(lemma)
  none(LemmaMapping)

# @axiom-hint: lean="pattern.length ≥ 0" smt="(assert (and (>= (str.len pattern) 0)))"
# @axiom-hint: lean="(lemmaCatalog ≥ 0)" smt="(assert (and (>= lemmaCatalog 0)))"
func findLemmasForPattern*(pattern: string): seq[LemmaMapping] {.raises: [].} =
  for lemma in lemmaCatalog:
    if lemma.nimPattern in pattern or pattern in lemma.nimPattern:
      result.add(lemma)

# @axiom-hint: lean="depth >= 0" smt="(assert (and (>= depth 0)))"
# @axiom-hint: lean="(lemmaCatalog ≥ 0)" smt="(assert (and (>= lemmaCatalog 0)))"
func findLemmasByCategory*(cat: LemmaCategory): seq[LemmaMapping] {.raises: [].} =
  for lemma in lemmaCatalog:
    if lemma.category == cat:
      result.add(lemma)

{.pop.}

{.pop.}
