# nim-check: skip
# Standalone subject probe: imports toml_serialization from the OUT-OF-TREE
# READ-ONLY subject clone (Zero-Footprint — the subject is never vendored into
# this repo), compiled with explicit --path entries to the pinned clone and the
# pinned nimble packages; it cannot resolve those imports in repo context by
# design (a nimble.lock in a cwd ancestor disables nimble discovery, so this
# must be compiled from a neutral cwd such as /tmp).
#
# Behavioural contract probe: typed record decoder (Tasks 1, 2, 3, 5).
# Usage: probe_record <caseId> <inputFile>
# Output is deterministic; exit 0 = decode accepted, exit 3 = decode rejected.
import std/[os, strutils, strformat]
import toml_serialization
import toml_serialization/lexer

type
  Three = object
    a, b, c: string
  One = object
    only: string
  Inner = object
    x, y: int
  Wrap = object
    inner: Inner
  CP3 = object
    foo, bar, baz: int
  Named = object
    myfield: int

func dumpThree(v: Three): string =
  fmt"a=[{v.a}] b=[{v.b}] c=[{v.c}]"

func dumpOne(v: One): string =
  fmt"only=[{v.only}]"

func dumpWrap(v: Wrap): string =
  fmt"inner=[x={v.inner.x} y={v.inner.y}]"

func dumpCP3(v: CP3): string =
  fmt"foo=[{v.foo}] bar=[{v.bar}] baz=[{v.baz}]"

func dumpNamed(v: Named): string =
  fmt"myfield=[{v.myfield}]"

proc readInput(path: string): string =
  readFile(path)

proc run(id: string, data: string) =
  # Each case hardcodes its own flags/case-mode so that repro.sh cannot
  # desynchronize the matrix from the probe.
  template decodeDefault(t: untyped): untyped =
    Toml.decode(data, t)
  template decodeUnknown(t: untyped): untyped =
    Toml.decode(data, t, {TomlUnknownFields})
  template decodeCase(t: untyped, cs: TomlCase): untyped =
    Toml.decode(data, t, "", cs)

  var detail: string
  case id
  # ---------------- Task 1: unknown keys ----------------
  of "U1": # flag OFF, unknown key before completion
    detail = dumpThree(decodeDefault(Three))
  of "U2": # flag ON, unknown key before completion
    detail = dumpThree(decodeUnknown(Three))
  of "U3": # flag OFF, unknown key after record complete (past early break)
    detail = dumpThree(decodeDefault(Three))
  of "U4": # flag ON, unknown key after record complete
    detail = dumpThree(decodeUnknown(Three))
  of "U5": # flag OFF, unknown key alone
    detail = dumpThree(decodeDefault(Three))
  of "U6": # flag ON, unknown key alone
    detail = dumpThree(decodeUnknown(Three))
  of "U7": # flag OFF, unknown key mixed between known keys
    detail = dumpThree(decodeDefault(Three))
  of "U8": # flag ON, unknown key mixed between known keys
    detail = dumpThree(decodeUnknown(Three))
  of "U9": # flag ON, unknown key whose VALUE is invalid TOML
    detail = dumpThree(decodeUnknown(Three))
  of "U10": # flag OFF, unknown key whose VALUE is invalid TOML
    detail = dumpThree(decodeDefault(Three))
  of "U11off": # flag OFF, unknown key inside inline table (known object field)
    detail = dumpWrap(decodeDefault(Wrap))
  of "U11on": # flag ON, unknown key inside inline table
    detail = dumpWrap(decodeUnknown(Wrap))
  of "U12off": # flag OFF, unknown array-of-tables header on array-less type
    detail = dumpThree(decodeDefault(Three))
  of "U12on": # flag ON, unknown array-of-tables header on array-less type
    detail = dumpThree(decodeUnknown(Three))
  of "U13off": # flag OFF, unknown key whose VALUE is an inline table
    detail = dumpThree(decodeDefault(Three))
  of "U13on": # flag ON, unknown key whose VALUE is an inline table (skip path
              # must parse it as TomlVoid)
    detail = dumpThree(decodeUnknown(Three))
  # ---------------- Task 2: field completeness ----------------
  of "C1": # 0 of 3 fields supplied
    detail = dumpThree(decodeDefault(Three))
  of "C2": # 1 of 3
    detail = dumpThree(decodeDefault(Three))
  of "C3": # 2 of 3
    detail = dumpThree(decodeDefault(Three))
  of "C4": # 3 of 3 (baseline)
    detail = dumpThree(decodeDefault(Three))
  of "C5": # duplicate key consumes a slot before the 3rd field is reached
    detail = dumpThree(decodeDefault(Three))
  # ---------------- Task 3: trailing input ----------------
  of "T3a", "T3b", "T3c", "T3c2", "T3d", "T3e", "T3f", "T3g":
    detail = dumpThree(decodeDefault(Three))
  of "K1": # control: same garbage as T3b but record incomplete
    detail = dumpThree(decodeDefault(Three))
  of "K2off": # control: unterminated string value of unknown key, flag OFF
    detail = dumpThree(decodeDefault(Three))
  of "K2on": # control: unterminated string value of unknown key, flag ON
    detail = dumpThree(decodeUnknown(Three))
  of "K3": # control: table header while incomplete, remaining field after
    detail = dumpThree(decodeDefault(Three))
  of "K3on": # control: table header while incomplete, unknown-fields flag ON
             # (header name is looked up as a field, then the SKIP path tries
             # to parse the following line as a value)
    detail = dumpThree(decodeUnknown(Three))
  of "K4": # control: array-of-tables header while incomplete
    detail = dumpThree(decodeDefault(Three))
  of "SL1": # garbage on same line as LAST value, record started line 1
    detail = dumpThree(decodeDefault(Three))
  of "SL2": # garbage on same line as FIRST value (still record start line)
    detail = dumpThree(decodeDefault(Three))
  of "SL3": # single-field record, garbage on the value's line
    detail = dumpOne(decodeDefault(One))
  of "SL4": # garbage mid-record on a line after the record start
    detail = dumpThree(decodeDefault(Three))
  # ---------------- Task 5: case modes ----------------
  of "M-sens-dup":
    detail = dumpCP3(decodeCase(CP3, TomlCaseSensitive))
  of "M-insens-dup":
    detail = dumpCP3(decodeCase(CP3, TomlCaseInsensitive))
  of "M-nim-dup":
    detail = dumpCP3(decodeCase(CP3, TomlCaseNim))
  of "M-sens-dup-rev":
    detail = dumpCP3(decodeCase(CP3, TomlCaseSensitive))
  of "M-insens-dup-rev":
    detail = dumpCP3(decodeCase(CP3, TomlCaseInsensitive))
  of "M-nim-dup-rev":
    detail = dumpCP3(decodeCase(CP3, TomlCaseNim))
  of "M-sens-breaksteal":
    detail = dumpCP3(decodeCase(CP3, TomlCaseSensitive))
  of "M-insens-breaksteal":
    detail = dumpCP3(decodeCase(CP3, TomlCaseInsensitive))
  of "M-nim-breaksteal":
    detail = dumpCP3(decodeCase(CP3, TomlCaseNim))
  of "M-sens-underscore":
    detail = dumpNamed(decodeCase(Named, TomlCaseSensitive))
  of "M-insens-underscore":
    detail = dumpNamed(decodeCase(Named, TomlCaseInsensitive))
  of "M-nim-underscore":
    detail = dumpNamed(decodeCase(Named, TomlCaseNim))
  of "M-sens-caseonly":
    detail = dumpNamed(decodeCase(Named, TomlCaseSensitive))
  of "M-insens-caseonly":
    detail = dumpNamed(decodeCase(Named, TomlCaseInsensitive))
  of "M-nim-caseonly":
    detail = dumpNamed(decodeCase(Named, TomlCaseNim))
  else:
    echo "CASE ", id
    echo "KIND probe-bug"
    echo "ERRMSG unknown case id"
    quit(2)

  echo "CASE ", id
  echo "KIND accept"
  echo "FIELDS ", detail
  quit(0)

let id = paramStr(1)
let data = readInput(paramStr(2))
try:
  run(id, data)
except TomlFieldReadingError as fe:
  # decodeRecord wraps per-field reader errors in TomlFieldReadingError
  # (reader.nim:330-331); the informative message lives in `.error`.
  echo "CASE ", id
  echo "KIND reject"
  echo "ERRTYPE ", fe.name
  echo "ERRMSG ", fe.msg.replace("\n", "\\n")
  echo "ERRFIELD ", fe.field
  if fe.error != nil:
    echo "ERRINNERMSG ", fe.error.msg.replace("\n", "\\n")
  quit(3)
except CatchableError as e:
  echo "CASE ", id
  echo "KIND reject"
  echo "ERRTYPE ", e.name
  echo "ERRMSG ", e.msg.replace("\n", "\\n")
  quit(3)
