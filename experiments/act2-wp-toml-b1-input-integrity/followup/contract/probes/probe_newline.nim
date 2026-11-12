# nim-check: skip
# Standalone subject probe: imports toml_serialization from the OUT-OF-TREE
# READ-ONLY subject clone (Zero-Footprint — the subject is never vendored into
# this repo), compiled with explicit --path entries to the pinned clone and the
# pinned nimble packages; it cannot resolve those imports in repo context by
# design (a nimble.lock in a cwd ancestor disables nimble discovery, so this
# must be compiled from a neutral cwd such as /tmp).
#
# Behavioural contract probe: newline between `=` and the value, per FIELD TYPE
# (Task 4, readValue path). Usage: probe_newline <fieldId> <inputFile>
# Input files have the shape `x =\n<value>` (or the same-line control `x = <v>`).
# Exit 0 = decode accepted, exit 3 = decode rejected.
import std/[os, strutils, strformat, sequtils]
import toml_serialization
import toml_serialization/lexer

type
  Color = enum
    cRed, cBlue
  Inner = object
    q: int
  AllTypes = object
    i: int
    f: float
    b: bool
    s: string
    d: TomlDate
    t: TomlTime
    dt: TomlDateTime
    e: Color
    sq: seq[int]
    o: Inner

func fmtDate(d: TomlDate): string =
  fmt"{d.year:04}-{d.month:02}-{d.day:02}"

func fmtTime(t: TomlTime): string =
  fmt"{t.hour:02}:{t.minute:02}:{t.second:02}.{t.subsecond}"

func fmtDT(dt: TomlDateTime): string =
  let d = if dt.date.isSome: fmtDate(dt.date.get) else: "<none>"
  let t = if dt.time.isSome: fmtTime(dt.time.get) else: "<none>"
  let z = if dt.zone.isSome: fmt"+{dt.zone.get.hourShift:02}:{dt.zone.get.minuteShift:02}" else: "<none>"
  fmt"{d}T{t}{z}"

let which = paramStr(1)
let data = readFile(paramStr(2))

try:
  let v = Toml.decode(data, AllTypes)
  echo "CASE nl-", which
  echo "KIND accept"
  let detail = case which
    of "i": $v.i
    of "f": $v.f
    of "b": $v.b
    of "s": "[" & v.s & "]"
    of "d": fmtDate(v.d)
    of "t": fmtTime(v.t)
    of "dt": fmtDT(v.dt)
    of "e": $v.e
    of "sq": "[" & v.sq.mapIt($it).join(",") & "]"
    of "o": "[q=" & $v.o.q & "]"
    else: "<probe-bug: unknown field id>"
  echo "FIELDS ", detail
  quit(0)
except TomlFieldReadingError as fe:
  # decodeRecord wraps per-field reader errors in TomlFieldReadingError
  # (reader.nim:330-331); the informative message lives in `.error`.
  echo "CASE nl-", which
  echo "KIND reject"
  echo "ERRTYPE ", fe.name
  echo "ERRMSG ", fe.msg.replace("\n", "\\n")
  echo "ERRFIELD ", fe.field
  if fe.error != nil:
    echo "ERRINNERMSG ", fe.error.msg.replace("\n", "\\n")
  quit(3)
except CatchableError as e:
  echo "CASE nl-", which
  echo "KIND reject"
  echo "ERRTYPE ", e.name
  echo "ERRMSG ", e.msg.replace("\n", "\\n")
  quit(3)
