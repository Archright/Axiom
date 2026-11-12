# nim-check: skip
# Standalone subject probe (defects3/p2b): imports toml_serialization from the
# OUT-OF-TREE READ-ONLY subject clone @4aa8e2223649fc0837c490a4acfca7b8b1e756f9;
# compiled with explicit --path from /tmp, so it cannot resolve that import in
# repo context by design (convention: experiments/bug-verdict-e2e/cout_probe.nim).
# Defect 2 (instrumented): same absent-key typed access wrapped in try/except
# to classify the failure. If a KeyError were raised (as the proc signature
# claims), we would see "EXCEPTION: KeyError". If the process dies before any
# handler runs, that is a hard nil dereference (NilAccessDefect via signal).
# NOTE: toml_serialization.nim does not re-export value_ops, so the
# TomlValueRef accessors require the explicit submodule import below.
import toml_serialization
import toml_serialization/value_ops

let doc = Toml.decode("a = 1", TomlValueRef)
try:
  let v = doc["absent", int]
  echo "NO EXCEPTION, returned: ", v
except Defect as d:
  echo "DEFECT: ", d.name, ": ", d.msg
except CatchableError as e:
  echo "EXCEPTION: ", e.name, ": ", e.msg
echo "survived"
