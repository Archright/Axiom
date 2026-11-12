# nim-check: skip
# valuemodel/q4a_accessor_tomldate: Task 4 — typed table accessor with
# T=TomlDate hits the dateDimte typo at value_ops.nim:32. This source is
# compiled TWICE by repro.sh: against the pristine subject (expected verbatim
# `undeclared field: 'dateDimte'` error) and against a /tmp-only patched copy
# (sed dateDimte->dateTime) to capture the SECOND, independent failure
# (`Option.get` scope, value_ops.nim has no std/options import).
# Subject: nim-toml-serialization @4aa8e2223649fc0837c490a4acfca7b8b1e756f9
# (out-of-tree READ-ONLY clone; explicit --path; convention:
# experiments/bug-verdict-e2e/cout_probe.nim).
import toml_serialization
import toml_serialization/value_ops

let doc = Toml.decode("d = 1979-05-27", TomlValueRef)
let v = doc["d", TomlDate]
echo "RESULT v=", $v
