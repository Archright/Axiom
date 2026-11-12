# nim-check: skip
# valuemodel/q3b_structural: Task 3 — equality across kinds and structures.
# argv1 = inputs/doc_struct.toml, argv2 = inputs/doc_scalar.toml.
# Covers: Table==InlineTable (both directions), Tables vs Array, Int vs Float,
# String/Bool vs Int, exact string equality, DateTime exactness (zone makes a
# difference), and tolerance propagation through Array elements.
# Only NON-crashing comparisons live here (nil-RHS comparisons on table-kind
# LHS may kill the process -> q3c_nil probes those separately, one per run).
# Subject: nim-toml-serialization @4aa8e2223649fc0837c490a4acfca7b8b1e756f9
# (out-of-tree READ-ONLY clone; explicit --path; convention:
# experiments/bug-verdict-e2e/cout_probe.nim).
import std/[os, tables, options]
import toml_serialization
import toml_serialization/value_ops

let sdoc = Toml.decode(readFile(paramStr(2)), TomlValueRef)
let doc = Toml.decode(readFile(paramStr(1)), TomlValueRef)

proc mkTable(kindK: TomlKind, x: int64): TomlValueRef =
  result = TomlValueRef(kind: kindK)
  result.tableVal = TomlTableRef.new
  result.tableVal["x"] = TomlValueRef(kind: TomlKind.Int, intVal: x)

let it = doc["tbl"] # InlineTable {x = 1} as decoded from TOML
let t = mkTable(TomlKind.Table, 1)
let t2 = mkTable(TomlKind.Table, 2)
let t3 = mkTable(TomlKind.Table, 1)
echo "decoded tbl kind=", $it.kind
echo "InlineTable_vs_Table_same a==b: ", (it == t), "  b==a: ", (t == it)
echo "Table_vs_Table_diffContent: ", (t == t2), " sameContent: ", (t == t3)
echo "Table3keys_vs_Table1key lenMismatch: ",
    (block:
  var big = TomlValueRef(kind: TomlKind.Table)
  big.tableVal = TomlTableRef.new
  for k in ["p", "q", "r"]:
    big.tableVal[k] = TomlValueRef(kind: TomlKind.Int, intVal: 1)
  big == t)

let arr = doc["arr"]
let tbs = doc["tbs"]
echo "decoded arr kind=", $arr.kind, " tbs kind=", $tbs.kind
echo "Tables_vs_Array: ", (tbs == arr), "  Array_vs_Tables: ", (arr == tbs)
echo "Array_vs_Array_sameContent: ", (arr == doc["arr"])

proc F(x: float64): TomlValueRef =
  TomlValueRef(kind: TomlKind.Float, floatVal: x)
proc I(x: int64): TomlValueRef =
  TomlValueRef(kind: TomlKind.Int, intVal: x)
proc S(x: string): TomlValueRef =
  TomlValueRef(kind: TomlKind.String, stringVal: x)
proc B(x: bool): TomlValueRef =
  TomlValueRef(kind: TomlKind.Bool, boolVal: x)

echo "Int1_vs_Float1.0: ", (I(1) == F(1.0)), "  Float1.0_vs_Int1: ", (F(1.0) == I(1))
echo "String1_vs_Int1: ", (S("1") == I(1))
echo "BoolTrue_vs_Int1: ", (B(true) == I(1)), "  BoolTrue_vs_Float1.0: ", (B(true) == F(1.0))
echo "String_exact_same: ", (S("hi") == S("hi")), " diff: ", (S("hi") == S("HI"))

# DateTime: exact field-wise equality via Option[TomlDate]/Option[TomlTime]/
# Option[TomlTimeZone] comparison (types.nim:201-202)
let dtFull = TomlValueRef(kind: TomlKind.DateTime)
dtFull.dateTime.date = some(TomlDate(year: 1979, month: 5, day: 27))
dtFull.dateTime.time = some(TomlTime(hour: 7, minute: 32, second: 0, subsecond: 0))
dtFull.dateTime.zone = some(TomlTimeZone(positiveShift: true, hourShift: 0, minuteShift: 0))
let dtNoZone = TomlValueRef(kind: TomlKind.DateTime)
dtNoZone.dateTime.date = some(TomlDate(year: 1979, month: 5, day: 27))
dtNoZone.dateTime.time = some(TomlTime(hour: 7, minute: 32, second: 0, subsecond: 0))
let dtSame = TomlValueRef(kind: TomlKind.DateTime)
dtSame.dateTime.date = some(TomlDate(year: 1979, month: 5, day: 27))
dtSame.dateTime.time = some(TomlTime(hour: 7, minute: 32, second: 0, subsecond: 0))
dtSame.dateTime.zone = some(TomlTimeZone(positiveShift: true, hourShift: 0, minuteShift: 0))
echo "DateTime_equal: ", (dtFull == dtSame), " zone_vs_noZone: ", (dtFull == dtNoZone),
    " noZone_vs_zone: ", (dtNoZone == dtFull)

# tolerance propagates through Array (seq[TomlValueRef] == uses elementwise
# TomlValueRef.==): 0.0 vs 5e-8 inside arrays compares EQUAL (left operand of
# the inner compare is 5e-8, a normal float)
let a1 = TomlValueRef(kind: TomlKind.Array)
a1.arrayVal = @[F(0.0)]
let a2 = TomlValueRef(kind: TomlKind.Array)
a2.arrayVal = @[F(5e-8)]
echo "Array[F(0.0)]_vs_Array[F(5e-8)] (tolerance through elements): ", (a1 == a2)
let a3 = TomlValueRef(kind: TomlKind.Array)
a3.arrayVal = @[F(5e-8)]
let a4 = TomlValueRef(kind: TomlKind.Array)
a4.arrayVal = @[F(0.0)]
echo "Array[F(5e-8)]_vs_Array[F(0.0)] reverse: ", (a3 == a4)
