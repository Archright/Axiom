# nim-check: skip
# valuemodel/q2c_TomlDateTime: Task 2 — does `node[k, TomlDateTime]` COMPILE? innerValue
# (value_ops.nim:14-68) is instantiated per T at the typed accessor call
# (value_ops.nim:86-87); unsupported T reaches the compile-time {.error.} at
# value_ops.nim:68. repro.sh compiles this probe to capture the compile-time
# verdict verbatim; when it compiles, it is also run as a bonus observation.
# Subject: nim-toml-serialization @4aa8e2223649fc0837c490a4acfca7b8b1e756f9
# (out-of-tree READ-ONLY clone; explicit --path; convention:
# experiments/bug-verdict-e2e/cout_probe.nim).
import toml_serialization
import toml_serialization/value_ops

let doc = Toml.decode("i = 7", TomlValueRef)
let v = doc["i", TomlDateTime]
echo "RESULT compiled-and-ran v=", v
