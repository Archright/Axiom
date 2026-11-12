# nim-check: skip
# Out-of-tree probe: imports the READ-ONLY pinned subject clone
# nim-toml-serialization @ 4aa8e2223649fc0837c490a4acfca7b8b1e756f9 via
# explicit --path flags (see repro.sh); the import cannot resolve in repo
# context by design. Compiled from a neutral cwd (/tmp); binary stays in /tmp.
#
# WRITER-TABLE TASK 1 (+ data for Tasks 3 & 4) — exhaustive 256-byte sweep of
# the WRITER's string escaping, under BOTH flavors:
#   Toml_v100 (runtimeFlags = {}, TOML v1.0.0) and default Toml
#   (runtimeFlags = Toml_v110_Flags, TOML v1.1.0).
# For every byte 0x00..0xFF as a single-char string value {"v": <byte>}:
#   - records the exact emitted token (the writer emits ONLY basic strings —
#     writer.nim:131-164 has no literal-string path; recorded as a fact),
#   - writes the emitted document to <out>/esc_<flavor>/bXX.toml (tomllib input),
#   - re-parses the emitted document with the SAME flavor and compares the
#     decoded value BYTES against the input byte (exact byte comparison;
#     TomlValueRef.== is NOT used — see types.nim:198 tolerance).
# Usage: probe_esc_sweep <output-dir>
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

proc runFlavor(Flavor: type, name: string, outDir: string) =
  let dir = outDir / ("esc_" & name)
  createDir(dir)
  var tsv = "byte\thex\temitted_token\tlib_read\tbyte_preserved\tdecoded_hex\n"
  for b in 0 .. 255:
    let s = $chr(b)
    let root = TomlValueRef(kind: TomlKind.Table, tableVal: TomlTableRef.new)
    root.tableVal[]["v"] = TomlValueRef(kind: TomlKind.String, stringVal: s)
    let e1 = Flavor.encode(root)
    let fname = "b" & toHex(b, 2) & ".toml"
    writeFile(dir / fname, e1)
    # emitted doc is exactly: "  v=" & token & "\n" (single key "v")
    let token = e1[4 ..< e1.len - 1]
    var libRead = "OK"
    var bytePres = "-"
    var decHex = "-"
    try:
      let v = Flavor.decode(e1, TomlValueRef)
      let back = v.tableVal[]["v"].stringVal
      bytePres = $(back == s)
      decHex = hexOf(back)
    except CatchableError as e:
      libRead = "FAIL " & reprOf(e.msg)
    tsv.add $b & "\t" & toHex(b, 2) & "\t" & reprOf(token) & "\t" &
      libRead & "\t" & bytePres & "\t" & decHex & "\n"
  writeFile(outDir / ("esc_sweep_" & name & ".tsv"), tsv)
  echo "esc sweep ", name, ": 256 cases written to ", dir

let outDir = if paramCount() >= 1: paramStr(1) else: "."
createDir(outDir)
runFlavor(Toml_v100, "v100", outDir)
runFlavor(Toml, "v110", outDir)
