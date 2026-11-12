# nim-check: skip
# valuemodel/q2c_object: Task 2 — does `node[k, SomeObject]` compile?
# innerValue (value_ops.nim:14-68) has no object branch; expected verdict is
# the compile-time {.error.} at value_ops.nim:68.
# Subject: nim-toml-serialization @4aa8e2223649fc0837c490a4acfca7b8b1e756f9
# (out-of-tree READ-ONLY clone; explicit --path; convention:
# experiments/bug-verdict-e2e/cout_probe.nim).
import toml_serialization
import toml_serialization/value_ops

type Conf = object
  a: int

let doc = Toml.decode("i = 7", TomlValueRef)
let v = doc["i", Conf]
echo "RESULT compiled-and-ran v=", v
