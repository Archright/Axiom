# nim-check: skip
# valuemodel/q4b_accessor_tomltime: Task 4 — typed table accessor with
# T=TomlTime hits the dateDimte typo at value_ops.nim:36 (verbatim compile
# error captured by repro.sh).
# Subject: nim-toml-serialization @4aa8e2223649fc0837c490a4acfca7b8b1e756f9
# (out-of-tree READ-ONLY clone; explicit --path; convention:
# experiments/bug-verdict-e2e/cout_probe.nim).
import toml_serialization
import toml_serialization/value_ops

let doc = Toml.decode("t = 07:32:00", TomlValueRef)
let v = doc["t", TomlTime]
echo "RESULT v=", $v
