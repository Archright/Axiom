# nim-check: skip
# Standalone subject probe (defects3/p2c): imports toml_serialization from the
# OUT-OF-TREE READ-ONLY subject clone @4aa8e2223649fc0837c490a4acfca7b8b1e756f9;
# compiled with explicit --path from /tmp, so it cannot resolve that import in
# repo context by design (convention: experiments/bug-verdict-e2e/cout_probe.nim).
# Defect 2 (array case, raw): typed access at an OUT-OF-RANGE index. Unlike the
# table case, `node[index]` (value_ops.nim:89-95) indexes arrayVal directly, so
# Nim's bounds check should raise IndexDefect (documented in the proc comment,
# value_ops.nim:90-92). Capture the unmediated observable.
# NOTE: toml_serialization.nim does not re-export value_ops, so the
# TomlValueRef accessors require the explicit submodule import below.
import toml_serialization
import toml_serialization/value_ops

let doc = Toml.decode("arr = [1, 2, 3]", TomlValueRef)
let arr = doc["arr"]
echo "arr.len=", arr.len
echo "about to evaluate arr[9, int] ..."
let v = arr[9, int]
echo "returned: ", v
