# nim-check: skip
# valuemodel/q1_matrix: Task 1 — accessor x receiver-kind matrix probe.
# One binary, but exactly ONE accessor call per run: argv1=accessor name,
# argv2=receiver kind, argv3=extra (key or index). Receivers are CONSTRUCTED
# manually (not decoded) so each run observes exactly one combination; a
# crashing combination kills only its own process and cannot contaminate the
# other rows. Receiver kinds: Table InlineTable Tables Array String Int Float
# Bool DateTime Nil. NOTE: TomlKind has no Date/Time members — date-only and
# time-only values are TomlKind.DateTime with Options, hence no Date/Time
# receiver rows can exist (see types.nim:59-68, 98-101). String-key accessors
# use argv3 as the key so present ("a") and absent ("absent") rows are both
# covered; index accessors use argv3 as the index ("1" in-range, "99" OOB).
# Subject: nim-toml-serialization @4aa8e2223649fc0837c490a4acfca7b8b1e756f9
# (out-of-tree READ-ONLY clone, reached via explicit --path; convention:
# experiments/bug-verdict-e2e/cout_probe.nim). toml_serialization.nim does not
# re-export value_ops, hence the explicit submodule import.
import std/[os, tables, options, strutils]
import toml_serialization
import toml_serialization/value_ops

proc makeReceiver(kindName: string): TomlValueRef =
  case kindName
  of "Table":
    result = TomlValueRef(kind: TomlKind.Table)
    result.tableVal = TomlTableRef.new
    result.tableVal["a"] = TomlValueRef(kind: TomlKind.Int, intVal: 7)
  of "InlineTable":
    result = TomlValueRef(kind: TomlKind.InlineTable)
    result.tableVal = TomlTableRef.new
    result.tableVal["a"] = TomlValueRef(kind: TomlKind.Int, intVal: 7)
  of "Tables":
    result = TomlValueRef(kind: TomlKind.Tables)
    let t = TomlTableRef.new
    t["a"] = TomlValueRef(kind: TomlKind.Int, intVal: 7)
    result.tablesVal = @[t]
  of "Array":
    result = TomlValueRef(kind: TomlKind.Array)
    for i in 1 .. 3:
      result.arrayVal.add TomlValueRef(kind: TomlKind.Int, intVal: 6 + i)
  of "String":
    result = TomlValueRef(kind: TomlKind.String, stringVal: "hi")
  of "Int":
    result = TomlValueRef(kind: TomlKind.Int, intVal: 5)
  of "Float":
    result = TomlValueRef(kind: TomlKind.Float, floatVal: 1.5)
  of "Bool":
    result = TomlValueRef(kind: TomlKind.Bool, boolVal: true)
  of "DateTime":
    result = TomlValueRef(kind: TomlKind.DateTime)
    result.dateTime.date = some(TomlDate(year: 1979, month: 5, day: 27))
    result.dateTime.time = some(TomlTime(hour: 7, minute: 32, second: 0, subsecond: 0))
  else:
    discard # "Nil" -> nil TomlValueRef

let n = makeReceiver(paramStr(2))
let extra = if paramCount() >= 3: paramStr(3) else: "a"

case paramStr(1)
of "len":
  # value_ops.nim:70-77 (Array -> seq len, Table -> pairs len, else 0)
  echo "RESULT len=", n.len()
of "get_untyped":
  # value_ops.nim:79-84: node.tableVal.getOrDefault(name)
  let v = n[extra]
  echo "RESULT isNil=", v.isNil
of "get_typed":
  # value_ops.nim:86-87: node[name].innerValue(T); T=int here (the T
  # dimension is Task 2 / innervalue.tsv)
  let v = n[extra, int]
  echo "RESULT v=", v
of "idx_untyped":
  # value_ops.nim:89-95: node.arrayVal[index] (bounds-checked seq access)
  let v = n[strutils.parseInt(extra)]
  echo "RESULT isNil=", v.isNil
of "idx_typed":
  # value_ops.nim:97-98: node[index].innerValue(T)
  let v = n[strutils.parseInt(extra), int]
  echo "RESULT v=", v
of "haskey":
  # value_ops.nim:100-103
  echo "RESULT hasKey=", n.hasKey(extra)
of "contains_key":
  # value_ops.nim:105-108
  echo "RESULT contains=", n.contains(extra)
of "contains_val":
  # value_ops.nim:110-113: find(node.arrayVal, val)
  echo "RESULT contains=",
      n.contains(TomlValueRef(kind: TomlKind.Int, intVal: 7))
of "set":
  # value_ops.nim:115-118: obj.tableVal[key] = val
  n[extra] = TomlValueRef(kind: TomlKind.Int, intVal: 9)
  echo "RESULT set-completed"
of "curly_get":
  # value_ops.nim:120-128: guarded traversal, nil on missing/non-table/nil
  let v = n{extra}
  echo "RESULT isNil=", v.isNil
of "getordefault":
  # value_ops.nim:130-134: guarded, nil on missing/non-table/nil
  let v = n.getOrDefault(extra)
  echo "RESULT isNil=", v.isNil
of "curly_set":
  # value_ops.nim:136-144: uses hasKey (asserts Table kind)
  n{extra} = TomlValueRef(kind: TomlKind.Int, intVal: 9)
  echo "RESULT curlyset-completed"
of "delete":
  # value_ops.nim:146-151: raises IndexDefect when key missing
  n.delete(extra)
  echo "RESULT delete-completed"
of "copy":
  # value_ops.nim:160-196: deep copy; no assert on kind or nil
  let v = copy(n)
  echo "RESULT copykind=", $v.kind
else:
  quit("unknown accessor: " & paramStr(1), 2)
