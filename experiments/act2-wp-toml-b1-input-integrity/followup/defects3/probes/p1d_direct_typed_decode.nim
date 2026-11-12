# nim-check: skip
# Standalone subject probe (defects3/p1d, control): imports toml_serialization
# from the OUT-OF-TREE READ-ONLY subject clone
# @4aa8e2223649fc0837c490a4acfca7b8b1e756f9; compiled with explicit --path from
# /tmp, so it cannot resolve that import in repo context by design
# (convention: experiments/bug-verdict-e2e/cout_probe.nim).
# Defect 1 control: DIRECT typed decode of TomlDate/TomlTime goes through
# reader.nim readValue (reader.nim:460-468) and never instantiates the
# value_ops.nim innerValue branches that contain the `dateDimte` typo.
# Expected: compiles and runs correctly -> isolates the typo to the
# TomlValueRef accessor path only.
import toml_serialization

let d = Toml.decode("d = 1979-05-27", TomlDate, "d")
echo "date: ", d.year, "-", d.month, "-", d.day
let t = Toml.decode("t = 07:32:00", TomlTime, "t")
echo "time: ", t.hour, ":", t.minute, ":", t.second
