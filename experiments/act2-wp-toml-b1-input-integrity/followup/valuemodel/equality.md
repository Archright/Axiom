# equality.md — value-model equality semantics of `TomlValueRef.==`

Subject: `<workspace>/nim-toml-serialization` @ `4aa8e2223649fc0837c490a4acfca7b8b1e756f9` (READ-ONLY, byte-clean before/after; see `raw/final_clean.txt`).
All numbers below are verbatim program output from `probes/q3a_tolerance.nim` (`raw/q3a_tolerance.out`) and `probes/q3b_structural.nim` (`raw/q3b_structural.out`), compiled Nim 2.2.10, `--mm:orc --skipUserCfg --skipParentCfg --skipProjCfg`, run from `/tmp/valuemodel_build`. Method above re-derives everything out-of-tree (the repro driver was removed in the 2026-10-11 consolidation; run bytes pinned in `raw.tar.gz` / root `MANIFEST`).
Fact-finding only: no severity, no CVSS, no issue filed.

## Source under test

`toml_serialization/types.nim:178-215` — `func ==*(a, b: TomlValueRef): bool`, with `TomlTableRef.==` at :171-176. Float branch (:193-198):

```nim
of TomlKind.Float:
  let fc = classify(a.floatVal)
  if fc != fcNormal:
    result = classify(b.floatVal) == fc
  else:
    result = (abs(a.floatVal - b.floatVal) < 1E-7)
```

## 1. The 1E-7 tolerance is real, and its edge is strict `<`

Both operands normal (fcNormal):

| a | b | abs(a-b) | a==b | b==a |
|---|---|---|---|---|
| 1.0 | 1.0000000899999999 (1.0+9e-8) | 8.99999998971168225e-08 | **true** | true |
| 1.0 | 1.0000000999999989 (1.0+9.9999999e-8) | 9.99999989481636931e-08 | **true** (just under) | true |
| 1.0 | 1.0000001000000010 (1.0+1.00000001e-7) | 1.00000000946565137e-07 | **false** (just over) | false |

So the effective threshold is `abs(a-b) < 1E-7` exactly; a delta of 1E-7 or more compares unequal. (An exactly-1E-7 delta is not binary-representable at 1.0; the two rows above bracket it: 9.99999989e-08 → true, 1.00000001e-07 → false.)

## 2. Non-transitivity — the triple

`a = 1.0`, `b = 1.0 + 9e-8 = 1.0000000899999999`, `c = 1.0 + 1.8e-7 = 1.0000001800000000`:

```
triple_ab  absdiff=8.99999998971168225e-08  eq(a,b)=true
triple_bc  absdiff=9.00000001191614274e-08  eq(b,c)=true
triple_ac  absdiff=1.80000000016278250e-07  eq(a,c)=false
TRIPLE a==b and b==c and not a==c => true
```

(The earlier attempt's triple failed because its pairs all fell inside the band; these values straddle it: a–b and b–c are ~9e-8 apart, a–c is ~1.8e-7 apart.)

## 3. Order-dependence (stronger than non-transitivity)

The `classify(a.floatVal)` gate reads the LEFT operand only. If `a` is not fcNormal the tolerance branch is never entered, so equality depends on argument order:

```
asym_zero_5e-8   a=0.0  b=4.99999999999999977e-08  eq(a,b)=false  eq(b,a)=true
asym_zero_1e-10  a=0.0  b=1.00000000000000004e-10  eq(a,b)=false  eq(b,a)=true
```

`0.0 == 5e-8` is **false** while `5e-8 == 0.0` is **true**. (0.0 classifies fcZero, so `classify(b) == fcZero` decides; reversed, `a=5e-8` is normal and the tolerance branch accepts.)

This propagates into containers, because `Array ==` compares elements with the same `==` (`raw/q3b_structural.out`):

```
Array[F(0.0)]_vs_Array[F(5e-8)] (tolerance through elements): false
Array[F(5e-8)]_vs_Array[F(0.0)] reverse: true
```

## 4. Non-normal classes compare by class only

| comparison | result |
|---|---|
| NaN == NaN | **true** (both fcNan) |
| NaN == 1.0 | false |
| Inf == Inf | true |
| -Inf == -Inf | true |
| Inf == -Inf | false (fcInf vs fcNegInf) |
| Inf == NaN | false |
| Inf == 1.0 / 1.0 == Inf | false / false |
| +0.0 == -0.0 | **false, both directions** (fcZero vs fcNegZero; IEEE 754 says equal) |
| +0.0 == +0.0 | true |
| 5e-324 == 9.88131291682493088e-324 (two DIFFERENT subnormals) | **true** (both fcSubnormal — class equality replaces the tolerance) |
| 5e-324 == 0.0 | false (fcSubnormal vs fcZero) |

## 5. Table == InlineTable — CONFIRMED, both directions

`tableKind = {TomlKind.Table, TomlKind.InlineTable}` (types.nim:180): when kinds differ but BOTH are table kinds, the early `return false` is skipped and the `case a.kind` falls into the shared `of TomlKind.Table, TomlKind.InlineTable` branch comparing `tableVal`s (:214-215):

```
decoded tbl kind=InlineTable
InlineTable_vs_Table_same a==b: true  b==a: true
Table_vs_Table_diffContent: false sameContent: true
Table3keys_vs_Table1key lenMismatch: false
```

Reverse direction (InlineTable on the left) is also true — the branch is shared, so the relation is symmetric here (unlike the float asymmetry above).

## 6. Tables vs Array

Kinds differ and are not both in `tableKind` → immediate `return false` with NO content inspection, both directions:

```
Tables_vs_Array: false  Array_vs_Tables: false
Array_vs_Array_sameContent: true
```

## 7. Cross-kind scalar equality — all false, exact

```
Int1_vs_Float1.0: false  Float1.0_vs_Int1: false
String1_vs_Int1: false
BoolTrue_vs_Int1: false  BoolTrue_vs_Float1.0: false
String_exact_same: true diff: false
DateTime_equal: true zone_vs_noZone: false noZone_vs_zone: false
```

DateTime equality is exact field-wise `TomlDateTime ==` (Options compared with `some`/`none` — a Z-offset vs no zone makes values unequal; the decoder stores `-05:00` as `positiveShift=false, hourShift=5`, see `raw/q4d_tomldatetime_ok.out`).

## 8. nil handling — asymmetric crash

`types.nim:182-189`: if `a` is nil the result is decided immediately; if `b` is nil the code enters the guard `not (a.kind in tableKind and b.kind in tableKind)` — and for a Table/InlineTable-kind `a`, the second operand dereferences nil `b` (`b.kind`):

| expression (argv case) | outcome (dbg AND -d:release) |
|---|---|
| nil == nil | true |
| nil == Int(5) | false |
| Int(5) == nil | false |
| Array == nil | false (tableKind gate short-circuits before `b.kind`) |
| nil == Table | false (a-is-nil path) |
| **Table == nil** | **SIGSEGV, exit 139** — `b.kind` on nil b (types.nim:187) |
| **InlineTable == nil** | **SIGSEGV, exit 139** — same |

Evidence: `probes/q3c_nil.nim`, one case per process (`raw/q3c_*.out/.err/.exit`, dbg + rel identical).

## 9. Scope of exactness

**All other verdicts use exact comparison**: String is byte-exact (`stringVal ==`), Int exact `int64 ==`, Bool exact, Array is elementwise exact modulo the element `==` itself (i.e. float arrays inherit the tolerance/asymmetry above, non-float arrays are exact), Tables is length-then-elementwise (`types.nim:207-213`), Table/InlineTable compare `TomlTableRef` (length, then std `Table ==`), DateTime compares the three Options exactly. The ONLY tolerance/class-based comparison in the value model is the Float branch (:193-198), and it is non-transitive (§2), order-dependent (§3), class-collapsed for non-normals (§4), and can crash on nil (§8).
