# nim-check: skip
# Standalone subject probe (defects3/p2a): imports toml_serialization from the
# OUT-OF-TREE READ-ONLY subject clone @4aa8e2223649fc0837c490a4acfca7b8b1e756f9;
# compiled with explicit --path from /tmp, so it cannot resolve that import in
# repo context by design (convention: experiments/bug-verdict-e2e/cout_probe.nim).
# Defect 2 (raw): typed access of an ABSENT key. value_ops.nim:79-87 makes
# `node[name]` return nil (getOrDefault) and then dereferences it in
# innerValue (case n.kind), while the proc claims `raises: [KeyError]`.
# No try/except here: capture the unmediated process observable
# (exit code / signal / stderr).
# NOTE: toml_serialization.nim does not re-export value_ops, so the
# TomlValueRef accessors require the explicit submodule import below.
import toml_serialization
import toml_serialization/value_ops

let doc = Toml.decode("a = 1\ns = \"x\"", TomlValueRef)
echo "hasKey(a)=", doc.hasKey("a"), " hasKey(absent)=", doc.hasKey("absent")
echo "about to evaluate doc[\"absent\", int] ..."
let v = doc["absent", int]
echo "returned: ", v
