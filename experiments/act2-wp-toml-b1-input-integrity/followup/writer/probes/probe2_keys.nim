# nim-check: skip
# Out-of-tree probe: imports the READ-ONLY pinned subject clone
# nim-toml-serialization @ 4aa8e2223649fc0837c490a4acfca7b8b1e756f9 via
# explicit --path flags (see repro.sh); the import cannot resolve in repo
# context by design. Compiled from a neutral cwd (/tmp); binary stays in /tmp.
#
# TASK 2 — key escaping (writer.nim writeKey, lines 166-181). For each key
# character of interest, record the exact bytes the writer emits on three
# write paths (top-level key/value, nested [table] header, inline table) and
# re-parse each emitted document with the same flavor.
# Usage: probe2_keys <output-dir>
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

# "k" & sub is the probed key; "" is the plain reference key; "" & "" the
# empty key.
const keySubs = ["[", "]", "=", "{", "}", ",", " ", ".", "\"", "#", "'",
                 "a", ""]

proc tryDecode(Flavor: type, doc: string): string =
  try:
    let v = Flavor.decode(doc, TomlValueRef)
    result = "DECODE-OK keys=["
    var i = 0
    for k, val in v.tableVal:
      if i > 0: result.add ", "
      result.add reprOf(k) & " -> " & $val.kind
      inc i
    result.add "]"
  except CatchableError as e:
    result = "DECODE-FAILED: " & e.msg

proc runFlavor(Flavor: type, name: string, outDir: string) =
  echo "=== flavor ", name, " ==="

  # (a) top-level key/value path
  for sub in keySubs:
    let k = "k" & sub
    let root = TomlValueRef(kind: TomlKind.Table, tableVal: TomlTableRef.new)
    root.tableVal[][k] = TomlValueRef(kind: TomlKind.Int, intVal: 7)
    let e1 = Flavor.encode(root)
    echo "[kv] key=", reprOf(k), " emitted hex : ", hexOf(e1)
    echo "[kv] key=", reprOf(k), " emitted repr: ", reprOf(e1)
    writeFile(outDir / ("key_" & name & "_kv_" & hexOf(k).multiReplace(
        {" ": ""}) & ".toml"), e1)
    echo "[kv] key=", reprOf(k), " ", tryDecode(Flavor, e1)

  # (b) nested [table] header path: { "t<sub>" = { inner = 1 } }
  for sub in ["[", "]", "=", "{", "}", ",", " "]:
    let k = "t" & sub
    let root = TomlValueRef(kind: TomlKind.Table, tableVal: TomlTableRef.new)
    let inner = TomlValueRef(kind: TomlKind.Table, tableVal: TomlTableRef.new)
    inner.tableVal[]["inner"] = TomlValueRef(kind: TomlKind.Int, intVal: 1)
    root.tableVal[][k] = inner
    let e1 = Flavor.encode(root)
    echo "[hdr] key=", reprOf(k), " emitted hex : ", hexOf(e1)
    echo "[hdr] key=", reprOf(k), " emitted repr: ", reprOf(e1)
    writeFile(outDir / ("key_" & name & "_hdr_" & hexOf(k).multiReplace(
        {" ": ""}) & ".toml"), e1)
    echo "[hdr] key=", reprOf(k), " ", tryDecode(Flavor, e1)

  # (c) inline-table member path: { k = { "k<sub>" = 7 } }
  for sub in ["[", "]", "=", "{", "}", ",", " "]:
    let k = "i" & sub
    let root = TomlValueRef(kind: TomlKind.Table, tableVal: TomlTableRef.new)
    let inl = TomlValueRef(kind: TomlKind.InlineTable,
                           tableVal: TomlTableRef.new)
    inl.tableVal[][k] = TomlValueRef(kind: TomlKind.Int, intVal: 7)
    root.tableVal[]["t"] = inl
    let e1 = Flavor.encode(root)
    echo "[inl] key=", reprOf(k), " emitted hex : ", hexOf(e1)
    echo "[inl] key=", reprOf(k), " emitted repr: ", reprOf(e1)
    writeFile(outDir / ("key_" & name & "_inl_" & hexOf(k).multiReplace(
        {" ": ""}) & ".toml"), e1)
    echo "[inl] key=", reprOf(k), " ", tryDecode(Flavor, e1)

let outDir = if paramCount() >= 1: paramStr(1) else: "."
runFlavor(Toml_v100, "v100", outDir)
runFlavor(Toml, "v110", outDir)
