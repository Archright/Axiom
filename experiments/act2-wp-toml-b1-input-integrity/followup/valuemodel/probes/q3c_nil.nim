# nim-check: skip
# valuemodel/q3c_nil: Task 3 — nil handling in TomlValueRef.==
# (types.nim:169-190). Reading types.nim:186-188, when b is nil and a.kind is
# Table/InlineTable, the expression `a.kind in tableKind and b.kind in
# tableKind` dereferences nil b (b.kind) -> expected SIGSEGV. argv1 selects
# ONE comparison per run so a crash cannot mask the other rows:
#   nil_nil nil_int int_nil table_nil nil_table inlinetable_nil array_nil
# Subject: nim-toml-serialization @4aa8e2223649fc0837c490a4acfca7b8b1e756f9
# (out-of-tree READ-ONLY clone; explicit --path; convention:
# experiments/bug-verdict-e2e/cout_probe.nim).
import std/[os, tables]
import toml_serialization
import toml_serialization/value_ops

proc mkTable(kindK: TomlKind): TomlValueRef =
  result = TomlValueRef(kind: kindK)
  result.tableVal = TomlTableRef.new
  result.tableVal["a"] = TomlValueRef(kind: TomlKind.Int, intVal: 1)

let t = mkTable(TomlKind.Table)
let it = mkTable(TomlKind.InlineTable)
let five = TomlValueRef(kind: TomlKind.Int, intVal: 5)
let arr = TomlValueRef(kind: TomlKind.Array)
let nl: TomlValueRef = nil

case paramStr(1)
of "nil_nil":
  echo "RESULT nil==nil: ", (nl == nl)
of "nil_int":
  echo "RESULT nil==Int(5): ", (nl == five)
of "int_nil":
  echo "RESULT Int(5)==nil: ", (five == nl)
of "table_nil":
  echo "RESULT Table==nil: ", (t == nl)
of "nil_table":
  echo "RESULT nil==Table: ", (nl == t)
of "inlinetable_nil":
  echo "RESULT InlineTable==nil: ", (it == nl)
of "array_nil":
  echo "RESULT Array==nil: ", (arr == nl)
else:
  quit("unknown case: " & paramStr(1), 2)
