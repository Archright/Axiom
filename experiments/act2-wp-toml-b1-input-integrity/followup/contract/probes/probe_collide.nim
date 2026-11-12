# nim-check: skip
# Standalone subject probe: imports toml_serialization from the OUT-OF-TREE
# READ-ONLY subject clone (Zero-Footprint — the subject is never vendored into
# this repo), compiled with explicit --path entries to the pinned clone and the
# pinned nimble packages; it cannot resolve those imports in repo context by
# design (a nimble.lock in a cwd ancestor disables nimble discovery, so this
# must be compiled from a neutral cwd such as /tmp).
#
# Behavioural contract probe: field-name COLLISION matrix (Task 5). Nim 2.2.10
# accepts an object declaring both `foo` and `Foo` (style-insensitive identity
# does not merge them), so the decoder's field table can contain two
# byte-distinct names that collide under TomlCaseInsensitive (and partially
# under TomlCaseNim). This probe records, per case mode, whether a key raises,
# overwrites one field, or targets a different field.
# Usage: probe_collide <caseId> <inputFile>
# Exit 0 = decode accepted, exit 3 = decode rejected.
import std/[os, strutils, strformat]
import toml_serialization
import toml_serialization/lexer

type Bad = object
  foo: int
  Foo: int

func dumpBad(v: Bad): string =
  fmt"foo=[{v.foo}] Foo=[{v.Foo}]"

proc run(id: string, data: string) =
  var detail: string
  case id
  of "X-CS-foo":        detail = dumpBad(Toml.decode(data, Bad, "", TomlCaseSensitive))
  of "X-CS-Foo":        detail = dumpBad(Toml.decode(data, Bad, "", TomlCaseSensitive))
  of "X-CS-FOO":        detail = dumpBad(Toml.decode(data, Bad, "", TomlCaseSensitive))
  of "X-CS-rep-foo":    detail = dumpBad(Toml.decode(data, Bad, "", TomlCaseSensitive))
  of "X-CS-rep-Foo":    detail = dumpBad(Toml.decode(data, Bad, "", TomlCaseSensitive))
  of "X-CS-mixed":      detail = dumpBad(Toml.decode(data, Bad, "", TomlCaseSensitive))
  of "X-CS-mixed-rev":  detail = dumpBad(Toml.decode(data, Bad, "", TomlCaseSensitive))
  of "X-CI-FOO":        detail = dumpBad(Toml.decode(data, Bad, "", TomlCaseInsensitive))
  of "X-CI-Foo":        detail = dumpBad(Toml.decode(data, Bad, "", TomlCaseInsensitive))
  of "X-CI-rep-FOO":    detail = dumpBad(Toml.decode(data, Bad, "", TomlCaseInsensitive))
  of "X-CI-rep-Foo":    detail = dumpBad(Toml.decode(data, Bad, "", TomlCaseInsensitive))
  of "X-CI-mixed":      detail = dumpBad(Toml.decode(data, Bad, "", TomlCaseInsensitive))
  of "X-CI-mixed-rev":  detail = dumpBad(Toml.decode(data, Bad, "", TomlCaseInsensitive))
  of "X-CN-Foo":        detail = dumpBad(Toml.decode(data, Bad, "", TomlCaseNim))
  of "X-CN-FOO":        detail = dumpBad(Toml.decode(data, Bad, "", TomlCaseNim))
  of "X-CN-mixed":      detail = dumpBad(Toml.decode(data, Bad, "", TomlCaseNim))
  of "X-CN-mixed-rev":  detail = dumpBad(Toml.decode(data, Bad, "", TomlCaseNim))
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
let data = readFile(paramStr(2))
try:
  run(id, data)
except TomlFieldReadingError as fe:
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
