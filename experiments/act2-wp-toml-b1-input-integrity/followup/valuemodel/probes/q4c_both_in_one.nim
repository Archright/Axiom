# nim-check: skip
# valuemodel/q4c_both_in_one: Task 4 — BOTH typed Date and Time accessor
# calls in one compilation unit, to record how many errors Nim reports for a
# single instantiation pass (does the compiler surface :32 and :36 together?).
# Subject: nim-toml-serialization @4aa8e2223649fc0837c490a4acfca7b8b1e756f9
# (out-of-tree READ-ONLY clone; explicit --path; convention:
# experiments/bug-verdict-e2e/cout_probe.nim).
import toml_serialization
import toml_serialization/value_ops

let doc = Toml.decode("d = 1979-05-27\nt = 07:32:00", TomlValueRef)
let a = doc["d", TomlDate]
let b = doc["t", TomlTime]
echo "RESULT a=", $a, " b=", $b
