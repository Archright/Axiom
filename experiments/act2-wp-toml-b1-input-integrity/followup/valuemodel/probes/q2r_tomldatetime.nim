# nim-check: skip
# valuemodel/q2r_tomldatetime: Task 2 — `node[k, TomlDateTime]`
# (value_ops.nim:26-28: the ONLY struct branch with no typo; reads
# n.dateTime directly). Observes full datetime, date-only, time-only (all
# TomlKind.DateTime variants) and a mismatching Int kind. Modes: main | absent.
# Subject: nim-toml-serialization @4aa8e2223649fc0837c490a4acfca7b8b1e756f9
# (out-of-tree READ-ONLY clone; explicit --path; convention:
# experiments/bug-verdict-e2e/cout_probe.nim).
import std/[os, options]
import toml_serialization
import toml_serialization/value_ops

let doc = Toml.decode(
    "dt = 1979-05-27T07:32:00Z\nd = 1979-05-27\nt = 07:32:00\ni = 7",
    TomlValueRef)
proc show(label: string, v: TomlDateTime) =
  echo label,
    " date-some=", v.date.isSome,
    " y=", (if v.date.isSome: $v.date.get.year else: "-"),
    " time-some=", v.time.isSome,
    " h=", (if v.time.isSome: $v.time.get.hour else: "-"),
    " zone-some=", v.zone.isSome
if paramStr(1) == "absent":
  let v = doc["absent", TomlDateTime]
  echo "RESULT absent-v=", $v
else:
  show("RESULT full-dt", doc["dt", TomlDateTime])
  show("RESULT dateonly-d", doc["d", TomlDateTime])
  show("RESULT timeonly-t", doc["t", TomlDateTime])
  show("RESULT mismatch-i", doc["i", TomlDateTime])
