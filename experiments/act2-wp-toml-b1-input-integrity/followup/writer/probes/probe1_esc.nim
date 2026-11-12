# nim-check: skip
# Out-of-tree probe: imports the READ-ONLY pinned subject clone
# nim-toml-serialization @ 4aa8e2223649fc0837c490a4acfca7b8b1e756f9 via
# explicit --path flags (see repro.sh); the import cannot resolve in repo
# context by design. Compiled from a neutral cwd (/tmp); binary stays in /tmp.
#
# TASK 1 — the `\e` escape (writer.nim line 148) under BOTH flavors:
#   Toml_v100 (runtimeFlags = {}, TOML v1.0.0) and default Toml
#   (runtimeFlags = Toml_v110_Flags, TOML v1.1.0).
# Records the exact bytes the WRITER emits for a string containing ESC (0x1B),
# then re-parses the emitted document with the same flavor.
# Usage: probe1_esc <output-dir>
import toml_serialization
import std/tables
import std/[strutils, os]

proc hexOf(s: string): string =
  var parts: seq[string]
  for c in s:
    parts.add toHex(ord(c), 2)
  parts.join(" ")

proc reprOf(s: string): string =
  for c in s:
    if c >= '\x20' and c < '\x7f':
      result.add c
    else:
      result.add "\\x" & toHex(ord(c), 2)

const ctrlSweep = "\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d" &
  "\x0e\x0f\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1a\x1b\x1c\x1d\x1e\x1f" &
  "\x7f\x80\xff"

proc runFlavor(Flavor: type, name: string, outDir: string) =
  echo "=== flavor ", name, " ==="

  # (a) TomlValueRef path: single-key table {esc = "<ESC>ABC"}
  block:
    let root = TomlValueRef(kind: TomlKind.Table, tableVal: TomlTableRef.new)
    root.tableVal[]["esc"] = TomlValueRef(
      kind: TomlKind.String, stringVal: "\x1b" & "ABC")
    let e1 = Flavor.encode(root)
    echo "[value] emitted hex : ", hexOf(e1)
    echo "[value] emitted repr: ", reprOf(e1)
    writeFile(outDir / ("esc_" & name & "_value.toml"), e1)
    try:
      let v = Flavor.decode(e1, TomlValueRef)
      let back = v.tableVal[]["esc"].stringVal
      echo "[value] re-decoded stringVal hex: ", hexOf(back)
      echo "[value] byte-exact vs original  : ", (back == "\x1b" & "ABC")
    except CatchableError as e:
      echo "[value] re-decode FAILED: ", e.msg

  # (b) plain object path: Obj(s = "<ESC>ABC")
  block:
    type Obj = object
      s: string
    let o = Obj(s: "\x1b" & "ABC")
    let e1 = Flavor.encode(o)
    echo "[object] emitted hex : ", hexOf(e1)
    echo "[object] emitted repr: ", reprOf(e1)
    writeFile(outDir / ("esc_" & name & "_object.toml"), e1)
    try:
      let o2 = Flavor.decode(e1, Obj)
      echo "[object] re-decoded s hex: ", hexOf(o2.s),
          "  byte-exact: ", (o2.s == o.s)
    except CatchableError as e:
      echo "[object] re-decode FAILED: ", e.msg

  # (c) full C0 sweep + DEL(0x7F) + 0x80 + 0xFF (context for the verdict)
  block:
    let root = TomlValueRef(kind: TomlKind.Table, tableVal: TomlTableRef.new)
    root.tableVal[]["ctrl"] = TomlValueRef(
      kind: TomlKind.String, stringVal: ctrlSweep)
    let e1 = Flavor.encode(root)
    echo "[ctrl] emitted hex : ", hexOf(e1)
    echo "[ctrl] emitted repr: ", reprOf(e1)
    writeFile(outDir / ("esc_" & name & "_ctrl.toml"), e1)
    try:
      let v = Flavor.decode(e1, TomlValueRef)
      let back = v.tableVal[]["ctrl"].stringVal
      echo "[ctrl] re-decoded hex: ", hexOf(back)
      echo "[ctrl] byte-exact vs original: ", (back == ctrlSweep)
    except CatchableError as e:
      echo "[ctrl] re-decode FAILED: ", e.msg

let outDir = if paramCount() >= 1: paramStr(1) else: "."
runFlavor(Toml_v100, "v100", outDir)
runFlavor(Toml, "v110", outDir)
