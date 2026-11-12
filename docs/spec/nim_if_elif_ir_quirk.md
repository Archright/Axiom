# Nim if/elif/else Expression IR Quirk — Upper-Bound Branch Dropped

## 수정 (Fix)

**The root cause was fixed on 2026-08-10 (P1b) in commit `7e8d63ccb`**
("4대 근본 아키텍처 수리", sub-item P1b: "if/elif desugaring 수리 — 재귀적 중첩
irIf 변환").

`convertIfExpr` (`src/core/trusted/ast_to_ir.nim:306-340`) was rewritten. It now
accumulates **all** `elif`/`else` children into a `branches: seq[(BranchKind,
NimNode)]` buffer, then folds them from last to first into a proper **nested
`irIf` chain**:

```nim
# new convertIfExpr — multi-way if/elif/else → nested irIf
if/elif/else is encoded as a nested irIf chain:
  If(C1, T1, Elif(C2, T2, E)) → irIf(C1, T1, irIf(C2, T2, E))
```

So the clamp pattern:

```nim
let t = if a < 5000: 5000
        elif a > 120000: 120000   # ← no longer dropped
        else: a
```

now correctly produces:

```
(ite (< raw 5000) 5000 (ite (> raw 120000) 120000 raw))
```

**The workaround below is no longer required.** `if/elif/else` expressions now
convert correctly. The workaround section is retained as a historical record of
the lesion and the pre-fix workaround (per AGENTS.md §0.5b — the doc records the
history); it is **not** a current requirement. Axiom Core code may now use
multi-way `if/elif/else` expressions directly (though two single-branch
early-return `if … return` statements remain valid and idiomatic).

## 증상 (Symptom)

`if/elif/else` **expression** (e.g. the clamp pattern below) converts through the
Axiom IR tracker (`ast_to_ir.nim`) into a single `irIf` whose **upper-bound
(`elif`) branch is silently dropped**. The SMT produced from such an IR omits the
`elif` condition entirely, so BMC cannot prove the clamped range.

```nim
# ❌ if/elif/else expression — `elif a > 120000: 120000` is silently dropped
let t = if a < 5000: 5000
        elif a > 120000: 120000   # ← this branch is DROPPED
        else: a
```

Expected IR / SMT (clamp both bounds):

```
(ite (< raw 5000) 5000 (ite (> raw 120000) 120000 raw))
```

Actually produced IR / SMT (upper bound lost):

```
(ite (< raw 5000) 5000 raw)
```

In the `calcDynamicTimeoutCore` Pattern 2 clamp, this caused the upper bound
(`maxDynamicTimeoutMs` → 120000) to vanish from the proof query, so the engine
could not verify the clamp chain end-to-end.

## 근본 원인 (Root Cause)

`src/core/trusted/ast_to_ir.nim:306-333` — `convertIfExpr`:

```nim
func convertIfExpr*(n: NimNode, ctx: IrContext): IRExpr =
  var cond: IRExpr = nil
  var thenExpr: IRExpr = nil
  var elseExpr: IRExpr = nil
  for child in n:
    case child.kind
    of nnkElifExpr:
      if cond == nil:                    # ← only the FIRST elif is consumed
        cond = convertExpr(child[0], ctx)
        thenExpr = convertExpr(child[1], ctx)
    of nnkElifBranch:
      if cond == nil:                    # ← only the FIRST elif is consumed
        cond = convertExpr(child[0], ctx)
        thenExpr = convertExpr(child[1], ctx)
    of nnkElseExpr:
      elseExpr = convertExpr(child[0], ctx)
    of nnkElse:
      elseExpr = convertExpr(child[0], ctx)
    else: discard
  if cond == nil: cond = irLit(0)
  if thenExpr == nil: thenExpr = irLit(0)
  if elseExpr == nil: elseExpr = irLit(0)
  irIf(cond, thenExpr, elseExpr)         # ← flatten: no elif nesting
```

**The `if cond == nil` guard means the converter only ever recognizes the FIRST
`nnkElifExpr`/`nnkElifBranch`.** Any subsequent `elif` branch in a multi-way
`if/elif/else` expression is iterated but never assigned — its condition and body
are silently discarded. Because `irIf` is a flat
`(cond, then, else)` node (there is no list/vector of elif cases), the converter
does not flatten the `elif` into a nested `irIf` chain.

For the clamp expression the AST children are:
1. first `nnkElifBranch` (`a < 5000` → `5000`) → `cond`/`thenExpr`
2. second `elif` (`a > 120000` → `120000`) → **dropped** (`cond != nil`)
3. `nnkElse` (`a`) → `elseExpr`

Result: `irIf(a < 5000, 5000, a)` — the upper-bound clamp is lost.

## 해결책 (Workaround — HISTORICAL RECORD, NO LONGER REQUIRED)

> **Deprecated since the 2026-08-10 fix (P1b / commit `7e8d63ccb`).** The
> `if/elif/else` desugaring bug is fixed, so the following workaround is **no
> longer a current requirement**. It is retained only as a historical record of
> the pre-fix guidance.

Use **two separate single-branch `if … return` statements** instead of an
`if/elif/else` expression. The early-return conversion
(`ast_to_ir.nim:458-477` `convertBodyFrom`, gated by `isEarlyReturnIf` at
`ast_to_ir.nim:437-446`) handles **one branch per `if`** and nests the resulting
`irIf` chain correctly:

```nim
# ✅ Two separate single-branch early-return ifs — converts correctly
proc calcDynamicTimeoutCore(raw: int64): int64 =
  if raw < 5000:
    return 5000
  if raw > 120000:
    return 120000
  return raw
```

Each `if` is a single-branch `nnkIfStmt` (its then-branch is a `return`), so each
becomes one `irIf(cond, retVal, rest)`. The second if lands in the `else` position
of the first, yielding the correct nested clamp:

```
(ite (< raw 5000) 5000 (ite (> raw 120000) 120000 raw))
```

Z3 returns `unsat` for the negation — the clamp is provably correct.

## 발견 (Discovered)

- **일자**: 2026-08-09
- **경로**: `calcDynamicTimeoutCore` Pattern 2 implementation (clamp of
  `minDynamicTimeoutMs` → 5000, `maxDynamicTimeoutMs` → 120000)

## 영향 범위 (Impact)

Before the 2026-08-10 fix (P1b), any Axiom Core `func` whose body is a multi-way
`if/elif/else` **expression** that feeds the BMC / SMT / Lean proof pipeline was
affected (upper-bound branch dropped). Since the fix, multi-way `if/elif/else`
expressions convert correctly and are safe to use directly.

For completeness, the pre-fix guidance (now only stylistic, not mandatory):
- two+ separate single-branch `if … return` statements, or
- a `case` statement (handled by `convertCaseExpr`, not this path)

remain valid, clean alternatives.

## 참조 (References)

- 변환기: `src/core/trusted/ast_to_ir.nim:306-337` (`convertIfExpr`/
  `convertIfStmt`), `:437-477` (early-return path)
- `irIf` 노드: `src/core/trusted/axiom_ir_types.nim:88`, `src/core/trusted/axiom_ir.nim:841`
- 등록: AGENTS.md §0.5b Quirk Documentation Mandate
