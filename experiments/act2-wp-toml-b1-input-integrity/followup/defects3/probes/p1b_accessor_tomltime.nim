# nim-check: skip
# Standalone subject probe (defects3/p1b): imports toml_serialization from the
# OUT-OF-TREE READ-ONLY subject clone @4aa8e2223649fc0837c490a4acfca7b8b1e756f9;
# compiled with explicit --path from /tmp, so it cannot resolve that import in
# repo context by design (convention: experiments/bug-verdict-e2e/cout_probe.nim).
# Defect 1 (TomlTime branch): instantiates the typed table accessor
# `["k", TomlTime]`, whose innerValue expansion hits `n.dateDimte` at
# toml_serialization/value_ops.nim:36. Expected: COMPILE FAILURE.
# NOTE: toml_serialization.nim does not re-export value_ops, so the
# TomlValueRef accessors require the explicit submodule import below.
import toml_serialization
import toml_serialization/value_ops

let doc = Toml.decode("t = 07:32:00", TomlValueRef)
let t = doc["t", TomlTime]
echo "time: ", t.hour, ":", t.minute, ":", t.second
