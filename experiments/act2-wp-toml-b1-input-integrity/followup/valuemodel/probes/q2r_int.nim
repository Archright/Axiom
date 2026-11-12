# nim-check: skip
# valuemodel/q2r_int: Task 2 — runtime behavior of `node[k, int]`
# (innerValue SomeInteger branch, value_ops.nim:15-19). Modes (argv1):
#   main   = matching kind + mismatching kinds (Float/String/Bool)
#   absent = missing key (value_ops.nim:87 feeds nil into innerValue:16)
# Each run observes one mode so a crash cannot mask the other rows.
# Subject: nim-toml-serialization @4aa8e2223649fc0837c490a4acfca7b8b1e756f9
# (out-of-tree READ-ONLY clone; explicit --path; convention:
# experiments/bug-verdict-e2e/cout_probe.nim).
import std/os
import toml_serialization
import toml_serialization/value_ops

let doc = Toml.decode(
    "i = 7\nbig = 5000000000\nf = 1.5\ns = \"hi\"\nb = true", TomlValueRef)
if paramStr(1) == "absent":
  let v = doc["absent", int]
  echo "RESULT absent-v=", v
else:
  echo "RESULT match-i=", doc["i", int]
  echo "RESULT trunc-big=", doc["big", int]
  echo "RESULT mismatch-f=", doc["f", int]
  echo "RESULT mismatch-s=", doc["s", int]
  echo "RESULT mismatch-b=", doc["b", int]
