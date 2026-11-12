# nim-check: skip
# valuemodel/q4f_array_typed_tomldate: Task 4 — the INT-KEYED typed accessor
# (value_ops.nim:97-98) is the second and only other innerValue caller; with
# T=TomlDate it must hit the SAME dateDimte error (:32), proving the blast
# radius covers both typed accessors.
# Subject: nim-toml-serialization @4aa8e2223649fc0837c490a4acfca7b8b1e756f9
# (out-of-tree READ-ONLY clone; explicit --path; convention:
# experiments/bug-verdict-e2e/cout_probe.nim).
import toml_serialization
import toml_serialization/value_ops

let doc = Toml.decode("arr = [1979-05-27]", TomlValueRef)
let v = doc["arr"][0, TomlDate]
echo "RESULT v=", $v
