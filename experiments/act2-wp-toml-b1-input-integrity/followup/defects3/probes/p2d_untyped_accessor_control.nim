# nim-check: skip
# Standalone subject probe (defects3/p2d, control): imports toml_serialization
# from the OUT-OF-TREE READ-ONLY subject clone
# @4aa8e2223649fc0837c490a4acfca7b8b1e756f9; compiled with explicit --path from
# /tmp, so it cannot resolve that import in repo context by design
# (convention: experiments/bug-verdict-e2e/cout_probe.nim).
# Defect 2 control: the UNTYPED accessor `node["absent"]` (value_ops.nim:79-84)
# silently returns nil via getOrDefault -- no exception at all. This is the
# mechanism feeding nil into the typed accessor.
# NOTE: toml_serialization.nim does not re-export value_ops, so the
# TomlValueRef accessors require the explicit submodule import below.
import toml_serialization
import toml_serialization/value_ops

let doc = Toml.decode("a = 1", TomlValueRef)
let n = doc["absent"]
echo "doc[\"absent\"] isNil: ", isNil(n)
echo "doc.getOrDefault(\"absent\") isNil: ", isNil(doc.getOrDefault("absent"))
echo "survived"
