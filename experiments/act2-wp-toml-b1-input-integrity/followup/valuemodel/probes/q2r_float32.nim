# nim-check: skip
# valuemodel/q2r_float32: Task 2 — `node[k, float32]` (SomeFloat branch,
# value_ops.nim:15-19). Modes: main | absent.
# Subject: nim-toml-serialization @4aa8e2223649fc0837c490a4acfca7b8b1e756f9
# (out-of-tree READ-ONLY clone; explicit --path; convention:
# experiments/bug-verdict-e2e/cout_probe.nim).
import std/os
import toml_serialization
import toml_serialization/value_ops

let doc = Toml.decode(
    "i = 7\nf = 1.5\ns = \"hi\"\nb = true", TomlValueRef)
if paramStr(1) == "absent":
  let v = doc["absent", float32]
  echo "RESULT absent-v=", v
else:
  echo "RESULT match-f=", doc["f", float32]
  echo "RESULT mismatch-i=", doc["i", float32]
  echo "RESULT mismatch-s=", doc["s", float32]
