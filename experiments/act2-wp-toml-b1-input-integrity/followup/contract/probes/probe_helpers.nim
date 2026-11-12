# nim-check: skip
# Standalone subject probe: imports toml_serialization (and faststreams for the
# memory input) from the OUT-OF-TREE READ-ONLY subject clone (Zero-Footprint —
# the subject is never vendored into this repo), compiled with explicit --path
# entries to the pinned clone and the pinned nimble packages; it cannot resolve
# those imports in repo context by design (a nimble.lock in a cwd ancestor
# disables nimble discovery, so this must be compiled from a neutral cwd such
# as /tmp).
#
# Behavioural contract probe: the PUBLIC value-parsing helpers on TomlReader
# (reader.nim ~569-610), each of which fronts one or more `expectChars` call
# sites (Task 4). Input files contain the value bytes only; hv_* files start
# with a newline to test an intervening LF before the value.
# Usage: probe_helpers <helperId> <inputFile>
# Exit 0 = accepted, exit 3 = rejected.
import std/[os, strutils]
import toml_serialization
import faststreams/inputs

let which = paramStr(1)
let data = readFile(paramStr(2))

try:
  var stream = unsafeMemoryInput(data)
  # NOTE: the 2-arg `TomlReader.init(stream)` convenience overload fails to
  # instantiate (default `Flavor = Toml` is not applied through the typedesc
  # chain), so the flavor is given explicitly here. This mirrors what
  # `Toml.decode` does internally via `Reader(Format)`.
  var r = TomlReader[Toml].init(stream)
  echo "CASE hv-", which
  echo "KIND accept"
  case which
  of "int":
    echo "FIELDS value=", r.parseInt(int)
  of "float":
    var s: string
    let sign = r.parseFloat(s)
    echo "FIELDS value=", s, " sign=", $sign
  of "number":
    var s: string
    let (sign, base) = r.parseNumber(s)
    echo "FIELDS value=", s, " sign=", $sign, " base=", $base
  of "bool":
    echo "FIELDS value=", $r.parseBool()
  of "string":
    var s: string
    let (ml, literal) = r.parseString(s)
    echo "FIELDS value=[", s, "] multiline=", $ml, " literal=", $literal
  of "asstring":
    echo "FIELDS value=[", r.parseAsString(), "]"
  of "date":
    var d = r.parseDate()
    echo "FIELDS value=", d.year, "-", d.month, "-", d.day
  of "time":
    var t = r.parseTime()
    echo "FIELDS value=", t.hour, ":", t.minute, ":", t.second, ".", t.subsecond
  of "datetime":
    var dt = r.parseDateTime()
    let d = if dt.date.isSome: $dt.date.get.year else: "<none>"
    let t = if dt.time.isSome: $dt.time.get.hour else: "<none>"
    echo "FIELDS value=", d, "T", t
  else:
    echo "FIELDS <probe-bug: unknown helper id>"
  quit(0)
except CatchableError as e:
  echo "CASE hv-", which
  echo "KIND reject"
  echo "ERRTYPE ", e.name
  echo "ERRMSG ", e.msg.replace("\n", "\\n")
  quit(3)
