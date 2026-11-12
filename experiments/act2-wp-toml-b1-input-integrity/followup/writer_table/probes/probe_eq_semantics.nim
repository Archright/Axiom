# nim-check: skip
# Out-of-tree probe: imports the READ-ONLY pinned subject clone
# nim-toml-serialization @ 4aa8e2223649fc0837c490a4acfca7b8b1e756f9 via
# explicit --path flags (see repro.sh); the import cannot resolve in repo
# context by design. Compiled from a neutral cwd (/tmp); binary stays in /tmp.
#
# WRITER-TABLE TASK 5 — precise `TomlValueRef.==` semantics (types.nim:190-215):
#   - float branch: abs(a-b) < 1E-7 (STRICT), non-normal floats compared by
#     classify() category only (so NaN == NaN is TRUE, +Inf == -Inf is FALSE,
#     0.0 == -0.0 is FALSE via fcZero vs fcNegZero)
#   - Table vs InlineTable are equated (both in `tableKind`, types.nim:180-188)
#   - kind mismatches elsewhere are FALSE (Int vs Float)
#   - round-trip relevance: a decoded 1.00000001 equals 1.0 under ==
# No verdict in this task's report uses `==`; byte comparison is used instead.
# Usage: probe_eq_semantics <output-dir>
import toml_serialization
import std/[strutils, os, math, tables]

proc reprOf(s: string): string =
  for c in s:
    if c >= '\x20' and c < '\x7f':
      result.add c
    else:
      result.add "\\x" & toHex(ord(c), 2)

proc fl(x: float): TomlValueRef =
  TomlValueRef(kind: TomlKind.Float, floatVal: x)

proc buildTable(kind: static TomlKind, innerKind: static TomlKind,
                v: TomlValueRef): TomlValueRef =
  result = TomlValueRef(kind: kind, tableVal: TomlTableRef.new)
  result.tableVal[]["k"] = TomlValueRef(kind: innerKind, tableVal: TomlTableRef.new)
  result.tableVal[]["k"].tableVal[]["x"] = v

let outDir = if paramCount() >= 1: paramStr(1) else: "."
createDir(outDir)

echo "== float tolerance branch (types.nim:198: abs(a-b) < 1E-7, strict) =="
echo "TOL 1.0 vs 1.00000001      : ", fl(1.0) == fl(1.00000001)
echo "TOL 1.0 vs 1.0000001       : ", fl(1.0) == fl(1.0000001)
echo "TOL 1.0 vs 1.000001        : ", fl(1.0) == fl(1.000001)
echo "TOL diff(1.0,1.00000001)   : ", formatFloat(abs(1.00000001 - 1.0), ffScientific, 18)
echo "TOL diff(1.0,1.0000001)    : ", formatFloat(abs(1.0000001 - 1.0), ffScientific, 18)
echo "TOL diff(1.0,1.000001)     : ", formatFloat(abs(1.000001 - 1.0), ffScientific, 18)
echo "TOL 1.0 vs 1.00000005      : ", fl(1.0) == fl(1.00000005)

echo "== non-transitivity triple =="
let x = 1.0
let y = 0.99999994
let z = 0.99999988
echo "TRI x=1.0 y=0.99999994 z=0.99999988"
echo "TRI x==y : ", fl(x) == fl(y), "  diff=", formatFloat(abs(x-y), ffScientific, 18)
echo "TRI y==z : ", fl(y) == fl(z), "  diff=", formatFloat(abs(y-z), ffScientific, 18)
echo "TRI x==z : ", fl(x) == fl(z), "  diff=", formatFloat(abs(x-z), ffScientific, 18)
echo "TRANSITIVITY VIOLATED: ", (fl(x) == fl(y)) and (fl(y) == fl(z)) and not (fl(x) == fl(z))

echo "== non-normal float branches (classify-only comparison) =="
echo "NAN NaN==NaN      : ", fl(NaN) == fl(NaN)
echo "INF Inf==Inf      : ", fl(Inf) == fl(Inf)
echo "INF Inf==-Inf     : ", fl(Inf) == fl(-Inf)
echo "ZERO 0.0==-0.0    : ", fl(0.0) == fl(-0.0)
echo "ZERO 0.0==1e-30   : ", fl(0.0) == fl(1e-30)

echo "== kind-mismatch guard (types.nim:186-188) =="
echo "KIND Int(1) == Float(1.0)            : ",
  TomlValueRef(kind: TomlKind.Int, intVal: 1) == fl(1.0)
echo "KIND String(a) == String(a)          : ",
  TomlValueRef(kind: TomlKind.String, stringVal: "a") ==
  TomlValueRef(kind: TomlKind.String, stringVal: "a")

echo "== Table == InlineTable (types.nim:180-188 tableKind) =="
let t = TomlValueRef(kind: TomlKind.Table, tableVal: TomlTableRef.new)
t.tableVal[]["k"] = TomlValueRef(kind: TomlKind.Int, intVal: 1)
let i = TomlValueRef(kind: TomlKind.InlineTable, tableVal: TomlTableRef.new)
i.tableVal[]["k"] = TomlValueRef(kind: TomlKind.Int, intVal: 1)
echo "EQ Table{k:1} == InlineTable{k:1}       : ", t == i
let t2 = buildTable(TomlKind.Table, TomlKind.Table, fl(1.0))
let i2 = buildTable(TomlKind.InlineTable, TomlKind.InlineTable, fl(1.0))
echo "EQ nested Table{k:{x:1.0}} == Inline    : ", t2 == i2
let i3 = TomlValueRef(kind: TomlKind.InlineTable, tableVal: TomlTableRef.new)
i3.tableVal[]["k"] = TomlValueRef(kind: TomlKind.Int, intVal: 2)
echo "EQ Table{k:1} == InlineTable{k:2}       : ", t == i3

echo "== round-trip relevance of the tolerance =="
let root = TomlValueRef(kind: TomlKind.Table, tableVal: TomlTableRef.new)
root.tableVal[]["v"] = fl(1.00000001)
let e1 = Toml.encode(root)
let v = Toml.decode(e1, TomlValueRef)
echo "RT emitted doc: ", reprOf(e1)
echo "RT decoded == Float(1.0)   : ", v.tableVal[]["v"] == fl(1.0)
echo "RT decoded floatVal == 1.00000001 exactly: ", v.tableVal[]["v"].floatVal == 1.00000001
echo "eq probe done"
