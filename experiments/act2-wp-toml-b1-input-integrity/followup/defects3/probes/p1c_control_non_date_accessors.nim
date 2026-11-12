# nim-check: skip
# Standalone subject probe (defects3/p1c, control): imports toml_serialization
# from the OUT-OF-TREE READ-ONLY subject clone
# @4aa8e2223649fc0837c490a4acfca7b8b1e756f9; compiled with explicit --path from
# /tmp, so it cannot resolve that import in repo context by design
# (convention: experiments/bug-verdict-e2e/cout_probe.nim).
# Defect 1 control: uses only non-date typed accessors (int/string/bool), so
# innerValue's TomlDate/TomlTime branches are never instantiated. If this
# compiles and runs, the library itself is healthy and the p1a/p1b failure is
# attributable solely to the lazy instantiation of the typo branches.
# NOTE: toml_serialization.nim does not re-export value_ops, so the
# TomlValueRef accessors require the explicit submodule import below.
import toml_serialization
import toml_serialization/value_ops

let doc = Toml.decode("x = 5\ns = \"hi\"\nb = true", TomlValueRef)
echo doc["x", int], " ", doc["s", string], " ", doc["b", bool]
