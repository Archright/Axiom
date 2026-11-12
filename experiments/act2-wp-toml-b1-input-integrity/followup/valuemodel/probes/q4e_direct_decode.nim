# nim-check: skip
# valuemodel/q4e_direct_decode: Task 4 — control: DIRECT typed decode through
# the reader path (Toml.decode(..., TomlDate/TomlTime/TomlDateTime, "key"))
# never instantiates innerValue, so the dateDimte typo cannot affect it.
# Expected: all three compile and run.
# Subject: nim-toml-serialization @4aa8e2223649fc0837c490a4acfca7b8b1e756f9
# (out-of-tree READ-ONLY clone; explicit --path; convention:
# experiments/bug-verdict-e2e/cout_probe.nim).
import toml_serialization

let d = Toml.decode("d = 1979-05-27", TomlDate, "d")
echo "RESULT date=", $d
let t = Toml.decode("t = 07:32:00", TomlTime, "t")
echo "RESULT time=", $t
let dt = Toml.decode("dt = 1979-05-27T07:32:00Z", TomlDateTime, "dt")
echo "RESULT datetime=", $dt
