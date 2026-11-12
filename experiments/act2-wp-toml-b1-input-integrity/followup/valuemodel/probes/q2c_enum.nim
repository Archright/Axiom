# nim-check: skip
# valuemodel/q2c_enum: Task 2 — does `node[k, SomeEnum]` compile? The enum
# branch (value_ops.nim:37-41) casts Int kinds and parseEnum's String kinds.
# Subject: nim-toml-serialization @4aa8e2223649fc0837c490a4acfca7b8b1e756f9
# (out-of-tree READ-ONLY clone; explicit --path; convention:
# experiments/bug-verdict-e2e/cout_probe.nim).
import toml_serialization
import toml_serialization/value_ops

type Fruit = enum
  fApple = (1, "apple")
  fBanana = (2, "banana")

let doc = Toml.decode("i = 7", TomlValueRef)
let v = doc["i", Fruit]
echo "RESULT compiled-and-ran v=", $v
