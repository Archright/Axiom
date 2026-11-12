# nim-check: skip
# Out-of-tree probe: imports the READ-ONLY pinned subject clone
# nim-toml-serialization @ 4aa8e2223649fc0837c490a4acfca7b8b1e756f9 via
# explicit --path flags (see repro.sh); the import cannot resolve in repo
# context by design. Compiled from a neutral cwd (/tmp); binary stays in /tmp.
#
# TASK 3 — general encode -> decode -> encode round-trip under Toml_v100
# (TOML v1.0.0 flavor, runtimeFlags = {}). Every case is a single-key root
# table {"v": value} so unordered-table iteration cannot hide differences.
# String/key comparisons are EXACT BYTE comparisons (TomlValueRef.== is not
# used for the verdict because types.nim:198 gives floats a 1E-7 tolerance and
# treats Table/InlineTable kinds as interchangeable). Where == would hide a
# mismatch, this is demonstrated explicitly at the end.
# Usage: probe3_roundtrip <output-dir>
import toml_serialization
import std/tables
import std/[strutils, os]

proc hexOf(s: string): string =
  var parts: seq[string]
  for c in s:
    parts.add toHex(ord(c), 2)
  parts.join(" ")

proc reprOf(s: string): string =
  for c in s:
    if c >= '\x20' and c < '\x7f':
      result.add c
    else:
      result.add "\\x" & toHex(ord(c), 2)

proc strV(s: string): TomlValueRef =
  TomlValueRef(kind: TomlKind.String, stringVal: s)

proc intV(i: int64): TomlValueRef =
  TomlValueRef(kind: TomlKind.Int, intVal: i)

proc wrap(v: TomlValueRef): TomlValueRef =
  let root = TomlValueRef(kind: TomlKind.Table, tableVal: TomlTableRef.new)
  root.tableVal[]["v"] = v
  root

proc strCase(label, s: string): (string, TomlValueRef) = (label, wrap(strV(s)))

proc floatV(x: float): TomlValueRef =
  TomlValueRef(kind: TomlKind.Float, floatVal: x)

proc checkValue(v0, v1: TomlValueRef) =
  # Exact-byte value-level checks; never uses TomlValueRef.== for a verdict.
  if v0.isNil or v1.isNil:
    echo "  value-level check skipped (nil)"
    return
  if v0.kind != TomlKind.Table or v1.kind != TomlKind.Table:
    echo "  (case root is not a table)"
    return
  if v0.tableVal[].hasKey("v") and not v0.tableVal[]["v"].isNil and
      v0.tableVal[]["v"].kind == TomlKind.String and
      v1.tableVal[].hasKey("v") and not v1.tableVal[]["v"].isNil and
      v1.tableVal[]["v"].kind == TomlKind.String:
    let a = v0.tableVal[]["v"].stringVal
    let b = v1.tableVal[]["v"].stringVal
    echo "  string bytes preserved: ", (a == b),
        (if a != b: "  in=" & hexOf(a) & "  out=" & hexOf(b) else: "")
  var keys0, keys1: seq[string]
  for k in v0.tableVal[].keys: keys0.add k
  for k in v1.tableVal[].keys: keys1.add k
  echo "  keys preserved byte-exact: ", (keys0 == keys1),
      (if keys0 != keys1:
        "  in=" & reprOf(join(keys0, "|")) & "  out=" & reprOf(join(keys1, "|"))
      else: "")

proc run(outDir: string) =
  var cases: seq[(string, TomlValueRef)]

  # -- strings (value bytes) --
  cases.add strCase("str_plain", "abc")
  cases.add strCase("str_tab", "a\tb")
  cases.add strCase("str_nl", "a\nb")
  cases.add strCase("str_cr", "a\rb")
  cases.add strCase("str_esc", "\x1b")
  cases.add strCase("str_quote", "say \"hi\"")
  cases.add strCase("str_bs", "a\\b")
  cases.add strCase("str_apos", "it's")
  cases.add strCase("str_eacute_utf8", "\xc3\xa9")      # é, valid UTF-8
  cases.add strCase("str_cjk", "\xe6\x97\xa5\xe6\x9c\xac\xe8\xaa\x9e")
  cases.add strCase("str_emoji", "\xf0\x9f\x98\x80")    # U+1F600
  cases.add strCase("str_del", "\x7f")
  cases.add strCase("str_lone_e9", "\xe9")              # lone 0xE9 (invalid UTF-8)
  cases.add strCase("str_lone_ff", "\xff")              # lone 0xFF (invalid UTF-8)
  cases.add strCase("str_empty", "")
  cases.add strCase("str_ctrl_mix", "a\x00b\x1bc\"d\\e")

  # -- scalars --
  cases.add ("int_pos", wrap(intV(42)))
  cases.add ("int_neg", wrap(intV(-17)))
  cases.add ("float_pi", wrap(floatV(3.141592653589793)))
  cases.add ("float_near", wrap(floatV(1.00000001)))
  cases.add ("bool_t", wrap(TomlValueRef(kind: TomlKind.Bool, boolVal: true)))
  block:
    var dt: TomlDateTime
    dt.date = some(TomlDate(year: 1979, month: 5, day: 27))
    dt.time = some(TomlTime(hour: 7, minute: 32, second: 0, subsecond: 0))
    dt.zone = some(TomlTimeZone(positiveShift: true, hourShift: 0,
                                minuteShift: 0))
    cases.add ("datetime_z", wrap(TomlValueRef(kind: TomlKind.DateTime,
                                               dateTime: dt)))

  # -- arrays / nesting --
  block:
    let arr = TomlValueRef(kind: TomlKind.Array)
    arr.arrayVal = @[intV(1), strV("a"),
                     TomlValueRef(kind: TomlKind.Bool, boolVal: true)]
    cases.add ("arr_mixed", wrap(arr))
  block:
    let a1 = TomlValueRef(kind: TomlKind.Array)
    a1.arrayVal = @[intV(1), intV(2)]
    let a2 = TomlValueRef(kind: TomlKind.Array)
    a2.arrayVal = @[intV(3), intV(4)]
    let arr = TomlValueRef(kind: TomlKind.Array)
    arr.arrayVal = @[a1, a2]
    cases.add ("arr_nested", wrap(arr))
  block:
    let inner = TomlValueRef(kind: TomlKind.Table, tableVal: TomlTableRef.new)
    inner.tableVal[]["b"] = intV(1)
    let outer = TomlValueRef(kind: TomlKind.Table, tableVal: TomlTableRef.new)
    outer.tableVal[]["a"] = inner
    cases.add ("tbl_nested", wrap(outer))
  block:
    let inl = TomlValueRef(kind: TomlKind.InlineTable,
                           tableVal: TomlTableRef.new)
    inl.tableVal[]["x"] = intV(1)
    cases.add ("inline_x", wrap(inl))
  block:
    let root = TomlValueRef(kind: TomlKind.Table, tableVal: TomlTableRef.new)
    var t1 = TomlTableRef.new
    t1[]["name"] = strV("a")
    var t2 = TomlTableRef.new
    t2[]["name"] = strV("b")
    root.tableVal[]["aot"] = TomlValueRef(kind: TomlKind.Tables,
                                        tablesVal: @[t1, t2])
    cases.add ("aot_2", root)

  # -- odd keys (value is int 1; the KEY is the subject) --
  for (label, k) in [("key_empty", ""), ("key_dot", "a.b"),
                     ("key_bracket", "k["), ("key_space", "k "),
                     ("key_apos", "k'"), ("key_uni", "\xc9\x8e\xca\x9e")]:
    let root = TomlValueRef(kind: TomlKind.Table, tableVal: TomlTableRef.new)
    root.tableVal[][k] = intV(1)
    cases.add (label, root)

  echo "=== encode -> decode -> encode, flavor Toml_v100 ==="
  for (label, v0) in cases:
    let e1 = Toml_v100.encode(v0)
    writeFile(outDir / ("rt_v100_" & label & ".toml"), e1)
    echo "--- ", label, " ---"
    echo "  E1 hex : ", hexOf(e1)
    echo "  E1 repr: ", reprOf(e1)
    var v1: TomlValueRef
    try:
      v1 = Toml_v100.decode(e1, TomlValueRef)
    except CatchableError as e:
      echo "  DECODE FAILED: ", e.msg
      continue
    let e2 = Toml_v100.encode(v1)
    echo "  E1==E2 byte-exact: ", (e1 == e2)
    if e1 != e2:
      echo "  E2 repr: ", reprOf(e2)
    checkValue(v0, v1)

when isMainModule:
  let outDir = if paramCount() >= 1: paramStr(1) else: "."
  run(outDir)

  # -- where TomlValueRef.== tolerance would hide a mismatch --
  echo "=== == tolerance demonstrations (types.nim:198) ==="
  block:
    let near = Toml_v100.decode(
      Toml_v100.encode(wrap(floatV(1.00000001))), TomlValueRef)
    let one = floatV(1.0)
    echo "  decoded(1.00000001) == 1.0 : ", (near.tableVal[]["v"] == one)
  block:
    let x = floatV(1.0)
    let y = floatV(0.99999994)
    let z = floatV(0.99999988)
    echo "  x==y (1.0 vs 0.99999994)      : ", (x == y)
    echo "  y==z (0.99999994 vs 0.99999988) : ", (y == z)
    echo "  x==z (1.0 vs 0.99999988)        : ", (x == z)
  block:
    let t = TomlValueRef(kind: TomlKind.Table, tableVal: TomlTableRef.new)
    t.tableVal[]["x"] = intV(1)
    let i = TomlValueRef(kind: TomlKind.InlineTable, tableVal: TomlTableRef.new)
    i.tableVal[]["x"] = intV(1)
    echo "  Table == InlineTable (same content): ", (t == i)
