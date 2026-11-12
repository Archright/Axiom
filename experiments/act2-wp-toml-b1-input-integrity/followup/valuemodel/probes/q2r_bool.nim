# nim-check: skip
# valuemodel/q2r_bool: Task 2 — `node[k, bool]` (value_ops.nim:20-22: set only
# when kind == Bool; every other kind yields the default false). Modes:
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
  let v = doc["absent", bool]
  echo "RESULT absent-v=", v
else:
  echo "RESULT match-b=", doc["b", bool]
  echo "RESULT mismatch-i=", doc["i", bool]
  echo "RESULT mismatch-f=", doc["f", bool]
  echo "RESULT mismatch-s=", doc["s", bool]
