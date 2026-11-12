# nim-check: skip
# Rationale: out-of-tree P0-D2-RT roundtrip probe (convention:
# experiments/bug-verdict-e2e/cout_probe.nim). It imports the READ-ONLY pinned
# subject (nim-toml-serialization @ 4aa8e2223649fc0837c490a4acfca7b8b1e756f9,
# materialized via `git archive | tar -x` into /tmp/p0d2_rt_env) plus its
# pinned dependencies via explicit --path entries; those imports cannot resolve
# inside the Axiom3 repo context by design (Zero-Footprint: the subject is
# never vendored, the clone is never mutated).
#
# Subject call form (cited from the subject's own tests):
#   decode: Toml.decode(text, Target)   (tests/test_decoder.nim:156)
#   encode: Toml.encode(value)          (tests/test_encoder.nim:190)
# Flavor: Toml - flavorTomlVersion = TomlVersion_v110 and flavorRuntimeFlags =
# Toml_v110_Flags (format.nim:24-36), which includes TomlHexEscape; BOTH
# TomlReader.init (reader.nim:53-66) and TomlWriter.init (writer.nim:30-40)
# union `flags + flavorRuntimeFlags(Flavor)`, so default options carry
# TomlHexEscape on both sides. No options overrides are passed.
#
# Output is deterministic by construction: no timestamps, no env reads.
import std/[os, strutils, unicode]
import toml_serialization

type
  RtConf = object
    value*: string
    ctrl*: string

proc hexOf(s: string): string =
  if s.len == 0: return "(empty)"
  var parts: seq[string]
  for c in s:
    parts.add(toHex(ord(c), 2))
  parts.join(" ")

proc utf8State(s: string): string =
  let bad = validateUtf8(s)
  if bad == -1: "well-formed-UTF8"
  else: "INVALID-UTF8(first-bad-offset=" & $bad & ")"

proc printable(s: string): string =
  for c in s:
    if c >= '\x20' and c != '\\' and c < '\x7F':
      result.add(c)
    else:
      result.add("\\x" & toHex(ord(c), 2))

proc runCase(name: string, path: string, intentValue: string, intentCtrl: string) =
  echo "=== case: ", name, " ==="
  let text = readFile(path)
  echo "input_bytes_hex: ", hexOf(text)

  # A. decoder on the authored fixture file
  var conf: RtConf
  var decoded = false
  try:
    conf = Toml.decode(text, RtConf)
    decoded = true
  except CatchableError as e:
    echo "decode_outcome: RAISED ", $e.name, ": ", e.msg
  if decoded:
    echo "decode_outcome: SUCCESS"
    echo "decoded_value_bytes_hex: ", hexOf(conf.value)
    echo "decoded_value_utf8: ", utf8State(conf.value)
    echo "decoded_ctrl_bytes_hex: ", hexOf(conf.ctrl)
    echo "decoded_ctrl_utf8: ", utf8State(conf.ctrl)
    echo "authored_decode_matches_intent_value: ", $(conf.value == intentValue)
    echo "authored_decode_matches_intent_ctrl: ", $(conf.ctrl == intentCtrl)

  # B. encoder on the intended (per-spec) logical value
  let intent = RtConf(value: intentValue, ctrl: intentCtrl)
  let enc = Toml.encode(intent)
  echo "encoder_output_bytes_hex: ", hexOf(enc)
  echo "encoder_output_text: ", printable(enc)

  # C. decoder again on the encoder's own output (roundtrip)
  try:
    let back = Toml.decode(enc, RtConf)
    echo "roundtrip_value_bytes_hex: ", hexOf(back.value)
    echo "roundtrip_ctrl_bytes_hex: ", hexOf(back.ctrl)
    echo "roundtrip_value_utf8: ", utf8State(back.value)
    echo "roundtrip_identity_holds: ", $(back == intent)
  except CatchableError as e:
    echo "roundtrip_decode: RAISED ", $e.name, ": ", e.msg

  # D. independent UTF-8 oracle (std/unicode, not subject code)
  echo "ref_utf8_U00E9_hex: ", hexOf(toUTF8(Rune(0xE9)))
  echo "ref_utf8_U0080_hex: ", hexOf(toUTF8(Rune(0x80)))

when isMainModule:
  if paramCount() != 2:
    stderr.writeLine "usage: p0d2_rt_probe <case-name> <input.toml>"
    quit(QuitFailure)
  let name = paramStr(1)
  let path = paramStr(2)
  if not fileExists(path):
    stderr.writeLine "input file not found: " & path
    quit(QuitFailure)
  case name
  of "baseline":
    runCase(name, path, "hello world", "plain")
  of "defect", "unicode":
    # identical intended logical string for the defect and unicode cases:
    # U+00E9 and U+0080 (independent std/unicode encoding of the codepoints)
    runCase(name, path, "caf" & toUTF8(Rune(0xE9)), toUTF8(Rune(0x80)))
  else:
    stderr.writeLine "unknown case: " & name
    quit(QuitFailure)
