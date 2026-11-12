# nim-check: skip
# valuemodel/q2r_uint64: Task 2 — `node[k, uint64]`: intVal: int64 -> uint64
# bit-pattern conversion (value_ops.nim:17); key i2 = -1 observes the wrap.
# Modes: main | absent.
# Subject: nim-toml-serialization @4aa8e2223649fc0837c490a4acfca7b8b1e756f9
# (out-of-tree READ-ONLY clone; explicit --path; convention:
# experiments/bug-verdict-e2e/cout_probe.nim).
import std/os
import toml_serialization
import toml_serialization/value_ops

let doc = Toml.decode(
    "i = 7\ni2 = -1\nf = 1.5\ns = \"hi\"\nb = true", TomlValueRef)
if paramStr(1) == "absent":
  let v = doc["absent", uint64]
  echo "RESULT absent-v=", v
else:
  echo "RESULT match-i=", doc["i", uint64]
  echo "RESULT neg-i2=", doc["i2", uint64]
  echo "RESULT mismatch-f=", doc["f", uint64]
  echo "RESULT mismatch-s=", doc["s", uint64]
