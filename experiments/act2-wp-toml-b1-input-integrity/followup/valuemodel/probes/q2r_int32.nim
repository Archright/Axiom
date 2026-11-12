# nim-check: skip
# valuemodel/q2r_int32: Task 2 — `node[k, int32]`: SomeInteger branch with
# 64->32 narrowing (value_ops.nim:17, T(n.intVal)). Modes: main | absent.
# Subject: nim-toml-serialization @4aa8e2223649fc0837c490a4acfca7b8b1e756f9
# (out-of-tree READ-ONLY clone; explicit --path; convention:
# experiments/bug-verdict-e2e/cout_probe.nim).
import std/os
import toml_serialization
import toml_serialization/value_ops

let doc = Toml.decode(
    "i = 7\nbig = 5000000000\nf = 1.5\ns = \"hi\"\nb = true", TomlValueRef)
if paramStr(1) == "absent":
  let v = doc["absent", int32]
  echo "RESULT absent-v=", v
else:
  echo "RESULT match-i=", doc["i", int32]
  echo "RESULT trunc-big=", doc["big", int32]
  echo "RESULT mismatch-f=", doc["f", int32]
  echo "RESULT mismatch-s=", doc["s", int32]
