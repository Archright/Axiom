# nim-check: skip
# Standalone subject probe (defects3/p1e): imports toml_serialization from a
# PATCHED COPY of the subject repo placed under /tmp (the read-only clone
# @4aa8e2223649fc0837c490a4acfca7b8b1e756f9 is untouched; the copy fixes ONLY
# the `dateDimte` -> `dateTime` typos at value_ops.nim:32 and :36). Compiled
# with explicit --path from /tmp, so it cannot resolve that import in repo
# context by design (convention: experiments/bug-verdict-e2e/cout_probe.nim).
# Defect 1 fix-check: with the typo repaired, the same accessor one-liners
# should compile AND return the correct values.
# NOTE: toml_serialization.nim does not re-export value_ops, so the
# TomlValueRef accessors require the explicit submodule import below.
import toml_serialization
import toml_serialization/value_ops

let doc = Toml.decode(
  "d = 1979-05-27T07:32:00Z\nt = 07:32:00",
  TomlValueRef)
let d = doc["d", TomlDate]
let t = doc["t", TomlTime]
echo "date: ", d.year, "-", d.month, "-", d.day
echo "time: ", t.hour, ":", t.minute, ":", t.second
