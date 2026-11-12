# nim-check: skip
# valuemodel/q2r_int64: Task 2 — `node[k, int64]` (identity conversion from
# intVal: int64, value_ops.nim:17). Modes: main | absent.
# Subject: nim-toml-serialization @4aa8e2223649fc0837c490a4acfca7b8b1e756f9
# (out-of-tree READ-ONLY clone; explicit --path; convention:
# experiments/bug-verdict-e2e/cout_probe.nim).
import std/os
import toml_serialization
import toml_serialization/value_ops

let doc = Toml.decode(
    "i = 7\nbig = 5000000000\nf = 1.5\ns = \"hi\"\nb = true", TomlValueRef)
if paramStr(1) == "absent":
  let v = doc["absent", int64]
  echo "RESULT absent-v=", v
else:
  echo "RESULT match-i=", doc["i", int64]
  echo "RESULT match-big=", doc["big", int64]
  echo "RESULT mismatch-f=", doc["f", int64]
  echo "RESULT mismatch-s=", doc["s", int64]
