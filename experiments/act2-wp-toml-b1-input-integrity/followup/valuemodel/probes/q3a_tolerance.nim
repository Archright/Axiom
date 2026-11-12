# nim-check: skip
# valuemodel/q3a_tolerance: Task 3 — float equality semantics of
# TomlValueRef.== (types.nim:193-198): if classify(a) != fcNormal the result
# is classify(a) == classify(b); otherwise abs(a-b) < 1E-7 (STRICT, so a
# delta of exactly 1E-7 must not compare equal). Each row prints the exact
# 17-significant-digit operands and delta plus BOTH argument orders, because
# the classify(a) gate makes == order-dependent for non-normal `a`.
# Subject: nim-toml-serialization @4aa8e2223649fc0837c490a4acfca7b8b1e756f9
# (out-of-tree READ-ONLY clone; explicit --path; convention:
# experiments/bug-verdict-e2e/cout_probe.nim).
import std/[math, strutils]
import toml_serialization
import toml_serialization/value_ops

proc F(x: float64): TomlValueRef =
  TomlValueRef(kind: TomlKind.Float, floatVal: x)

proc eq(a, b: float64): bool =
  F(a) == F(b)

proc row(label: string, a, b: float64) =
  echo label, " a=", formatFloat(a, ffScientific, 17),
    " b=", formatFloat(b, ffScientific, 17),
    " absdiff=", formatFloat(abs(a - b), ffScientific, 17),
    " eq(a,b)=", eq(a, b), " eq(b,a)=", eq(b, a)

# tolerance band (both operands normal): strict abs(a-b) < 1E-7
row "tol_under", 1.0, 1.0 + 9e-8
row "tol_just_under", 1.0, 1.0 + 9.9999999e-8
row "tol_just_over", 1.0, 1.0 + 1.00000001e-7

# non-transitivity triple: a==b, b==c, but a!=c
let ta = 1.0
let tb = 1.0 + 9e-8
let tc = 1.0 + 1.8e-7
row "triple_ab", ta, tb
row "triple_bc", tb, tc
row "triple_ac", ta, tc
echo "TRIPLE a==b and b==c and not a==c => ", (eq(ta, tb) and eq(tb, tc) and not eq(ta, tc))

# the classify(a)==fcNormal gate: 0.0 is fcZero, so the tolerance branch is
# never entered when 0.0 is the LEFT operand -> order-dependent equality
row "asym_zero_5e-8", 0.0, 5e-8
row "asym_zero_1e-10", 0.0, 1e-10

# signed zeros are distinct classes (fcZero vs fcNegZero)
row "zero_negzero", 0.0, -0.0
row "zero_zero", 0.0, 0.0

# subnormals: classify-equality replaces the tolerance entirely
row "sub_sub", 5e-324, 9.9e-324
row "sub_zero", 5e-324, 0.0

# non-normal classes compare by class only
row "nan_nan", NaN, NaN
row "nan_one", NaN, 1.0
row "inf_inf", Inf, Inf
row "neginf_neginf", NegInf, NegInf
row "inf_neginf", Inf, NegInf
row "inf_nan", Inf, NaN
row "inf_one", Inf, 1.0
row "one_inf", 1.0, Inf
