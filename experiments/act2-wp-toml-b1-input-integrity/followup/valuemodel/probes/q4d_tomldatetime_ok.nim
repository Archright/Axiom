# nim-check: skip
# valuemodel/q4d_tomldatetime_ok: Task 4 — control: the TomlDateTime branch
# of innerValue (value_ops.nim:26-28) reads `n.dateTime` and contains NO typo;
# `node[k, TomlDateTime]` must compile and run for every DateTime variant
# (full Z datetime, offset datetime, date-only, time-only). argv1 =
# inputs/doc_temporal.toml.
# Subject: nim-toml-serialization @4aa8e2223649fc0837c490a4acfca7b8b1e756f9
# (out-of-tree READ-ONLY clone; explicit --path; convention:
# experiments/bug-verdict-e2e/cout_probe.nim).
import std/[os, options]
import toml_serialization
import toml_serialization/value_ops

let doc = Toml.decode(readFile(paramStr(1)), TomlValueRef)
let full = doc["dt", TomlDateTime]
echo "RESULT dt date=", $full.date.get, " time=", $full.time.get,
    " zone-some=", full.zone.isSome
let dtz = doc["dtzone", TomlDateTime]
echo "RESULT dtzone zone-some=", dtz.zone.isSome,
    " pos=", (if dtz.zone.isSome: $dtz.zone.get.positiveShift else: "-"),
    " h=", (if dtz.zone.isSome: $dtz.zone.get.hourShift else: "-")
let dateOnly = doc["d", TomlDateTime]
echo "RESULT d date=", $dateOnly.date.get, " time-none=", dateOnly.time.isNone
let timeOnly = doc["t", TomlDateTime]
echo "RESULT t time=", $timeOnly.time.get, " date-none=", timeOnly.date.isNone
