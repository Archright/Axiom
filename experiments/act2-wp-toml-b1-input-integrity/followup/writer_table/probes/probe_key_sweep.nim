# nim-check: skip
# Out-of-tree probe: imports the READ-ONLY pinned subject clone
# nim-toml-serialization @ 4aa8e2223649fc0837c490a4acfca7b8b1e756f9 via
# explicit --path flags (see repro.sh); the import cannot resolve in repo
# context by design. Compiled from a neutral cwd (/tmp); binary stays in /tmp.
#
# WRITER-TABLE TASK 2 (+ lib-side Task 3) — exhaustive 256-single-char-key
# sweep plus representative multi-char keys, under BOTH flavors:
#   Toml_v100 (runtimeFlags = {}, TOML v1.0.0) and default Toml
#   (runtimeFlags = Toml_v110_Flags, TOML v1.1.0).
# For every byte 0x00..0xFF as a single-char key {<byte>: 7}:
#   - records the exact emitted key token (bare vs quoted; writeKey,
#     writer.nim:166-181 — quoted keys go through writeValue, i.e. basic string),
#   - writes the emitted document to <out>/keys_<flavor>/bXX.toml (tomllib input),
#   - re-parses with the SAME flavor and compares the decoded KEY BYTES against
#     the input key (exact byte comparison; TomlValueRef.== NOT used).
# Multi-char keys: a.b, a b, a"b, a'b, a#b, a[b, a]b, a=b, a{b, a}b, a,b,
#   a<LF>b, é (C3 A9), ʎǝʞ (C9 8E CA 9E), lone E9 (invalid UTF-8).
# Usage: probe_key_sweep <output-dir>
import toml_serialization
import std/[strutils, os, tables]

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

proc emitAndReparse(Flavor: type, name: string, dir: string, fname: string,
                    key: string, caseId: string, tsv: var string) =
  let root = TomlValueRef(kind: TomlKind.Table, tableVal: TomlTableRef.new)
  root.tableVal[][key] = TomlValueRef(kind: TomlKind.Int, intVal: 7)
  let e1 = Flavor.encode(root)
  writeFile(dir / fname, e1)
  # emitted doc: "  " & keyToken & "=" & "7" & "\n"; separator is the LAST '='
  let sep = e1.rfind('=')
  let keyToken = e1[2 ..< sep]
  var libRead = "OK"
  var bytePres = "-"
  var decHex = "-"
  try:
    let v = Flavor.decode(e1, TomlValueRef)
    if v.kind != TomlKind.Table:
      libRead = "FAIL root not a table"
    elif v.tableVal.len != 1:
      libRead = "FAIL root key count " & $v.tableVal.len
    else:
      for k, val in v.tableVal[]:
        bytePres = $(k == key)
        decHex = hexOf(k)
  except CatchableError as e:
    libRead = "FAIL " & reprOf(e.msg)
  tsv.add caseId & "\t" & reprOf(keyToken) & "\t" & libRead & "\t" &
    bytePres & "\t" & decHex & "\n"

proc runFlavor(Flavor: type, name: string, outDir: string) =
  let dir = outDir / ("keys_" & name)
  createDir(dir)
  var tsv = "case\thex\tkey_token\tlib_read\tkey_bytes_preserved\tdecoded_key_hex\n"
  for b in 0 .. 255:
    let s = $chr(b)
    emitAndReparse(Flavor, name, dir, "b" & toHex(b, 2) & ".toml", s,
                   $b & "\t" & toHex(b, 2), tsv)
  const mcKeys = [
    ("dot", "a.b"), ("space", "a b"), ("dquote", "a\"b"), ("squote", "a'b"),
    ("hash", "a#b"), ("lbrack", "a[b"), ("rbrack", "a]b"), ("eq", "a=b"),
    ("lbrace", "a{b"), ("rbrace", "a}b"), ("comma", "a,b"), ("newline", "a\nb"),
    ("eacute", "\xC3\xA9"), ("uni", "\xC9\x8E\xCA\x9E"), ("lone_e9", "\xE9"),
  ]
  for slug, key in mcKeys.items:
    var hexId = ""
    for c in key:
      hexId.add toHex(ord(c), 2)
    emitAndReparse(Flavor, name, dir, "mc_" & slug & ".toml", key,
                   "mc:" & slug & "\t" & hexId, tsv)
  writeFile(outDir / ("keys_sweep_" & name & ".tsv"), tsv)
  echo "key sweep ", name, ": 256 + ", mcKeys.len, " cases written to ", dir

let outDir = if paramCount() >= 1: paramStr(1) else: "."
createDir(outDir)
runFlavor(Toml_v100, "v100", outDir)
runFlavor(Toml, "v110", outDir)
