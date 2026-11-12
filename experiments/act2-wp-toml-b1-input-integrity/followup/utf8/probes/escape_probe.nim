# nim-check: skip — out-of-tree probe: imports toml_serialization from the READ-ONLY subject clone via --path (Zero-Footprint); cannot resolve that import in repo context by design.
# Differential-verification probe B (escape interaction): drives the READ-ONLY
# subject's public decoder (toml_serialization) from OUTSIDE the subject repo
# (Zero-Footprint; compiled in /tmp with an explicit --path to the pinned
# clone). Subject: nim-toml-serialization @ 4aa8e2223649fc0837c490a4acfca7b8b1e756f9
#
# Question: under a flavor that enables TomlHexEscape, what does `\xHH` put in
# the decoded Nim string, and is that string valid UTF-8 per the subject's own
# validator and per CPython codecs (checked by the companion Python step)?

import std/[strutils, os]
import toml_serialization
import toml_serialization/private/utf8_validate

const OUTDIR = "/tmp/utf8diff/out"

proc report(tag: string, doc: string, flags: TomlFlags) =
  echo "=== ", tag, " ==="
  echo "doc_bytes_hex: ", toHex(doc)
  try:
    let v = Toml.decode(doc, string, "val", TomlCaseSensitive, flags)
    echo "decoded_len: ", v.len
    echo "decoded_hex: ", toHex(v)
    echo "subject_validateUTF8(decoded): ", validateUTF8(v)
    writeFile(OUTDIR & "/escape_" & tag & ".bin", v)
  except CatchableError as e:
    echo "raised: ", $e.name, ": ", e.msg

proc reportDefault(tag: string, doc: string) =
  # default `Toml` flavor: v1.1.0 runtime flags (incl. TomlHexEscape) are
  # merged in by the reader itself (reader.nim: flags + flavorRuntimeFlags)
  echo "=== ", tag, " (default Toml flavor, no explicit flags) ==="
  echo "doc_bytes_hex: ", toHex(doc)
  try:
    let v = Toml.decode(doc, string, "val")
    echo "decoded_len: ", v.len
    echo "decoded_hex: ", toHex(v)
    echo "subject_validateUTF8(decoded): ", validateUTF8(v)
    writeFile(OUTDIR & "/escape_" & tag & ".bin", v)
  except CatchableError as e:
    echo "raised: ", $e.name, ": ", e.msg

proc reportV100(tag: string, doc: string, flags: TomlFlags) =
  # true v1.0.0 flavor (format-level runtimeFlags = {}): no v1.1.0 flag merging
  echo "=== ", tag, " (Toml_v100 flavor) ==="
  echo "doc_bytes_hex: ", toHex(doc)
  try:
    let v = Toml_v100.decode(doc, string, "val", TomlCaseSensitive, flags)
    echo "decoded_len: ", v.len
    echo "decoded_hex: ", toHex(v)
    echo "subject_validateUTF8(decoded): ", validateUTF8(v)
    writeFile(OUTDIR & "/escape_" & tag & ".bin", v)
  except CatchableError as e:
    echo "raised: ", $e.name, ": ", e.msg

createDir(OUTDIR)

# 1. \x80 under the DEFAULT Toml flavor (v1.1.0 flag set is always merged in)
reportDefault("x80_default", "val = \"\\x80\"")

# 2. \x80 under an explicit TomlHexEscape flag
report("x80_explicit", "val = \"\\x80\"", {TomlHexEscape})

# 3. \xFF
report("xFF_explicit", "val = \"\\xFF\"", {TomlHexEscape})

# 4. the v1.1.0 spec example: Jos\xE9 (spec: \xE9 is U+00E9, i.e. "é")
report("jose_xE9_explicit", "val = \"Jos\\xE9\"", {TomlHexEscape})

# 5. control: \u0080 must produce the UTF-8 encoding of U+0080 (C2 80)
report("u0080_explicit", "val = \"\\u0080\"", {TomlHexEscape})

# 6. escape raw byte embedded between valid text
report("mixed_a_x80_b", "val = \"a\\x80b\"", {TomlHexEscape})

# 7. multi-line basic string path (same clear()-on-escape logic)
report("mlbasic_x80", "val = \"\"\"\\x80\"\"\"", {TomlHexEscape})

# 8. raw byte 0xC3 mid-sequence immediately before an escape: the
#    before-escape utf8.valid() guard must reject
report("rawC3_then_x80", "val = \"\xC3\\x80\"", {TomlHexEscape})

# 9. escape-produced raw byte followed by raw continuation-looking bytes:
#    validator cleared after the escape, so C3 A9 is checked independently
report("x80_then_rawC3A9", "val = \"\\x80\xC3\xA9\"", {TomlHexEscape})

# 10. negative control: \xHH must be refused when the flavor's runtime flags
#     do not include TomlHexEscape (true v1.0.0 flavor, flags = {})
reportV100("x45_v100_noflag", "val = \"H\\x45X\"", {})

# 11. positive control on the v1.0.0 flavor: with the flag it decodes
reportV100("x45_v100_flag", "val = \"H\\x45X\"", {TomlHexEscape})

# 10b. same doc with explicit empty user flags on the DEFAULT flavor:
#      v1.1.0 runtime flags are merged regardless, so this still decodes
#      (documents that {} does not disable \xHH on the Toml flavor)
report("x45_default_emptyflags", "val = \"H\\x45X\"", {})

# 12. surrogate via \\u must be refused (unicode scalar value rule)
report("uD800_surrogate", "val = \"\\uD800\"", {TomlHexEscape})

echo "=== done ==="
