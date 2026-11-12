## smt_sort.nim — Compile-time SMT sort tracking via phantom types.
##
## Purpose: Prevent (and bv64 bool) sort mismatch at compile time.
## Instead of string-based runtime coercion, the Nim compiler rejects
## mixed-sort expressions before they reach Z3.
##
## Design: SmtExpr[T] where T is BoolSort or Bv64Sort.
## Bool operators (and, or, not, =>) require both operands to be BoolSort.
## To combine BV64 and Bool, explicit coerceToBool() is required — the
## compiler forces this call, making it impossible to accidentally emit
## mixed-sort conjunctions.

import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

import std/strutils

type
  BoolSort* = object
    ## Phantom type: SMT Bool sort

  Bv64Sort* = object
    ## Phantom type: SMT (_ BitVec 64) sort

  SmtExpr*[T] = object
    ## Compile-time sort-tracked SMT expression wrapper.
    ## T is a phantom type parameter — the compiler enforces sort consistency.
    raw*: string

# ── Constructors ─────────────────────────────────────────────

func bvLit*(val: int64): SmtExpr[Bv64Sort] {.inline.} =
  ## Create a bitvector literal. Uses hex format for SMT-LIB2.
  SmtExpr[Bv64Sort](raw: "#x" & val.toHex(16))

func bvVar*(name: string): SmtExpr[Bv64Sort] {.inline.} =
  ## Create a named bitvector variable reference.
  SmtExpr[Bv64Sort](raw: name)

func boolLit*(val: bool): SmtExpr[BoolSort] {.inline.} =
  ## Create a boolean literal.
  SmtExpr[BoolSort](raw: if val: "true" else: "false")

func boolVar*(name: string): SmtExpr[BoolSort] {.inline.} =
  ## Create a named boolean variable reference.
  SmtExpr[BoolSort](raw: name)

func fromRaw*[T](s: string): SmtExpr[T] {.inline.} =
  ## Wrap an existing SMT string into a typed expression.
  ## Use at boundaries where the sort is known by construction
  ## (e.g., irExprToSmt output for a typed IRExpr).
  SmtExpr[T](raw: s)

# ── Boolean connectives ──────────────────────────────────────
# These ONLY accept BoolSort operands. Passing Bv64Sort is a compile error.

func smtAnd*(a, b: SmtExpr[BoolSort]): SmtExpr[BoolSort] {.inline.} =
  ## (and Bool Bool) → Bool
  SmtExpr[BoolSort](raw: "(and " & a.raw & " " & b.raw & ")")

func smtOr*(a, b: SmtExpr[BoolSort]): SmtExpr[BoolSort] {.inline.} =
  ## (or Bool Bool) → Bool
  SmtExpr[BoolSort](raw: "(or " & a.raw & " " & b.raw & ")")

func smtNot*(a: SmtExpr[BoolSort]): SmtExpr[BoolSort] {.inline.} =
  ## (not Bool) → Bool
  SmtExpr[BoolSort](raw: "(not " & a.raw & ")")

func smtImplies*(a, b: SmtExpr[BoolSort]): SmtExpr[BoolSort] {.inline.} =
  ## (=> Bool Bool) → Bool
  SmtExpr[BoolSort](raw: "(=> " & a.raw & " " & b.raw & ")")

func smtConjunction*(exprs: openArray[SmtExpr[BoolSort]]): SmtExpr[BoolSort] =
  ## Build (and e1 e2 ... en) from an array. Returns boolLit(true) if empty.
  if exprs.len == 0:
    return boolLit(true)
  if exprs.len == 1:
    return exprs[0]
  var parts: seq[string] = @[]
  for e in exprs:
    parts.add(e.raw)
  SmtExpr[BoolSort](raw: "(and " & parts.join(" ") & ")")

func smtDisjunction*(exprs: openArray[SmtExpr[BoolSort]]): SmtExpr[BoolSort] =
  ## Build (or e1 e2 ... en) from an array. Returns boolLit(false) if empty.
  if exprs.len == 0:
    return boolLit(false)
  if exprs.len == 1:
    return exprs[0]
  var parts: seq[string] = @[]
  for e in exprs:
    parts.add(e.raw)
  SmtExpr[BoolSort](raw: "(or " & parts.join(" ") & ")")

# ── Comparison operators: Bv64 → Bool ────────────────────────

func smtBvEq*(a, b: SmtExpr[Bv64Sort]): SmtExpr[BoolSort] {.inline.} =
  ## (= Bv64 Bv64) → Bool
  SmtExpr[BoolSort](raw: "(= " & a.raw & " " & b.raw & ")")

func smtBvDistinct*(a, b: SmtExpr[Bv64Sort]): SmtExpr[BoolSort] {.inline.} =
  ## (distinct Bv64 Bv64) → Bool
  SmtExpr[BoolSort](raw: "(distinct " & a.raw & " " & b.raw & ")")

func smtBvLt*(a, b: SmtExpr[Bv64Sort]): SmtExpr[BoolSort] {.inline.} =
  ## (bvslt Bv64 Bv64) → Bool — signed less-than
  SmtExpr[BoolSort](raw: "(bvslt " & a.raw & " " & b.raw & ")")

func smtBvLe*(a, b: SmtExpr[Bv64Sort]): SmtExpr[BoolSort] {.inline.} =
  ## (bvsle Bv64 Bv64) → Bool — signed less-or-equal
  SmtExpr[BoolSort](raw: "(bvsle " & a.raw & " " & b.raw & ")")

func smtBvGt*(a, b: SmtExpr[Bv64Sort]): SmtExpr[BoolSort] {.inline.} =
  ## (bvsgt Bv64 Bv64) → Bool — signed greater-than
  SmtExpr[BoolSort](raw: "(bvsgt " & a.raw & " " & b.raw & ")")

func smtBvGe*(a, b: SmtExpr[Bv64Sort]): SmtExpr[BoolSort] {.inline.} =
  ## (bvsge Bv64 Bv64) → Bool — signed greater-or-equal
  SmtExpr[BoolSort](raw: "(bvsge " & a.raw & " " & b.raw & ")")

# ── Bitvector arithmetic: Bv64 → Bv64 ────────────────────────

func smtBvAdd*(a, b: SmtExpr[Bv64Sort]): SmtExpr[Bv64Sort] {.inline.} =
  SmtExpr[Bv64Sort](raw: "(bvadd " & a.raw & " " & b.raw & ")")

func smtBvSub*(a, b: SmtExpr[Bv64Sort]): SmtExpr[Bv64Sort] {.inline.} =
  SmtExpr[Bv64Sort](raw: "(bvsub " & a.raw & " " & b.raw & ")")

func smtBvMul*(a, b: SmtExpr[Bv64Sort]): SmtExpr[Bv64Sort] {.inline.} =
  SmtExpr[Bv64Sort](raw: "(bvmul " & a.raw & " " & b.raw & ")")

func smtBvAnd*(a, b: SmtExpr[Bv64Sort]): SmtExpr[Bv64Sort] {.inline.} =
  ## Bitwise AND (not logical!) — both must be Bv64Sort
  SmtExpr[Bv64Sort](raw: "(bvand " & a.raw & " " & b.raw & ")")

func smtBvOr*(a, b: SmtExpr[Bv64Sort]): SmtExpr[Bv64Sort] {.inline.} =
  SmtExpr[Bv64Sort](raw: "(bvor " & a.raw & " " & b.raw & ")")

func smtBvXor*(a, b: SmtExpr[Bv64Sort]): SmtExpr[Bv64Sort] {.inline.} =
  SmtExpr[Bv64Sort](raw: "(bvxor " & a.raw & " " & b.raw & ")")

func smtBvNot*(a: SmtExpr[Bv64Sort]): SmtExpr[Bv64Sort] {.inline.} =
  SmtExpr[Bv64Sort](raw: "(bvnot " & a.raw & ")")

func smtBvShl*(a, b: SmtExpr[Bv64Sort]): SmtExpr[Bv64Sort] {.inline.} =
  SmtExpr[Bv64Sort](raw: "(bvshl " & a.raw & " " & b.raw & ")")

func smtBvLshr*(a, b: SmtExpr[Bv64Sort]): SmtExpr[Bv64Sort] {.inline.} =
  SmtExpr[Bv64Sort](raw: "(bvlshr " & a.raw & " " & b.raw & ")")

func smtBvAshr*(a, b: SmtExpr[Bv64Sort]): SmtExpr[Bv64Sort] {.inline.} =
  SmtExpr[Bv64Sort](raw: "(bvashr " & a.raw & " " & b.raw & ")")

# ── Explicit coercion (compiler-enforced) ─────────────────────
# These are the ONLY way to cross the Bool↔Bv64 boundary.
# The compiler forces the call — you cannot accidentally omit it.

func coerceToBool*(a: SmtExpr[Bv64Sort]): SmtExpr[BoolSort] {.inline.} =
  ## BV64 → Bool: nonzero = true, zero = false.
  ## This is the ONLY way to use a BV64 value in a boolean context.
  ## The compiler will reject `smtAnd(bvExpr, boolExpr)` without this call.
  SmtExpr[BoolSort](raw: "(not (= " & a.raw & " #x0000000000000000))")

func coerceToBv64*(a: SmtExpr[BoolSort]): SmtExpr[Bv64Sort] {.inline.} =
  ## Bool → BV64: true = #x01, false = #x00.
  ## This is the ONLY way to use a boolean in a bitvector context.
  SmtExpr[Bv64Sort](raw: "(ite " & a.raw & " #x0000000000000001 #x0000000000000000)")

# ── Raw string extraction ────────────────────────────────────

func toRaw*(e: SmtExpr): string {.inline.} =
  ## Extract the raw SMT-LIB2 string. Use at emission boundaries.
  e.raw

# ── Bridge: legacy string-based conjunction ───────────────────

func smtAndRaw*(conditions: seq[string]): string =
  ## Bridge: build (and ...) from raw strings.
  ## Use ONLY when migrating from legacy string-based emission.
  ## Prefer smtConjunction() with SmtExpr[BoolSort] when possible.
  if conditions.len == 0: return "true"
  if conditions.len == 1: return conditions[0]
  "(and " & conditions.join(" ") & ")"

func smtOrRaw*(conditions: seq[string]): string =
  ## Bridge: build (or ...) from raw strings.
  ## Use ONLY when migrating from legacy string-based emission.
  ## Prefer smtDisjunction() with SmtExpr[BoolSort] when possible.
  if conditions.len == 0: return "false"
  if conditions.len == 1: return conditions[0]
  "(or " & conditions.join(" ") & ")"

{.pop.}
