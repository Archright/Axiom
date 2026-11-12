# nim-check: skip
# valuemodel/q2r_string: Task 2 — `node[k, string]` (value_ops.nim:23-25: set
# only when kind == String; every other kind yields the default ""). Modes:
# main | absent.
# Subject: nim-toml-serialization @4aa8e2223649fc0837c490a4acfca7b8b1e756f9
# (out-of-tree READ-ONLY clone; explicit --path; convention:
# experiments/bug-verdict-e2e/cout_probe.nim).
import std/os
import toml_serialization
import toml_serialization/value_ops

let doc = Toml.decode(
    "i = 7\nf = 1.5\ns = \"hi\"\nb = true", TomlValueRef)
if paramStr(1) == "absent":
  let v = doc["absent", string]
  echo "RESULT absent-v=", v
else:
  echo "RESULT match-s=", doc["s", string]
  echo "RESULT mismatch-i=", doc["i", string]
  echo "RESULT mismatch-f=", doc["f", string]
  echo "RESULT mismatch-b=", doc["b", string]
