# nim-check: skip
# Standalone subject probe: imports toml_serialization from the OUT-OF-TREE
# READ-ONLY subject clone (Zero-Footprint — the subject is never vendored into
# this repo); the import cannot resolve in repo context by design. Marker +
# rationale follow the established repo convention:
# experiments/bug-verdict-e2e/cout_probe.nim.
#
# B-SEC link experiment (a) — flavor transfer.
# The committed B-1 results (../../observations/raw/, JUDGMENT.md) were taken
# with the UN-KEYED typed decode on the `Toml_v100` flavor:
#   Toml_v100.decode(input, Obj)
# This probe runs the SAME byte-pinned inputs through the DEFAULT flavor:
#   Toml.decode(input, Obj)
# (un-keyed — no key argument, no TomlUnknownFields). Output format matches
# the committed harness (observations/harness/harness.nim) line-for-line so
# that per-case observation blocks can be compared byte-for-byte; the only
# intentionally-different line is `decode_call=`, which names the invoked
# flavor and is therefore run metadata, excluded from the byte comparison.
#
# Binaries are produced under /tmp only; the subject clone is opened
# read-only via --path and is never written.

import std/os
import toml_serialization

type
  Obj = object of RootObj
    a: string
    b: string
    c: string

proc show(s: string): string =
  ## Bracket-delimited, control-char-escaped rendering (identical to the
  ## committed B-1 harness) so empty strings and whitespace stay visible.
  result = "["
  for ch in s:
    case ch
    of '\n': result.add "\\n"
    of '\r': result.add "\\r"
    of '\t': result.add "\\t"
    else: result.add ch
  result.add "]"

proc runRecordDefault(input: string) =
  echo "decode_call=Toml.decode(input, Obj)"
  try:
    let o = Toml.decode(input, Obj)
    echo "DECODE_RESULT=OK"
    echo "a=" & show(o.a)
    echo "b=" & show(o.b)
    echo "c=" & show(o.c)
    echo "a_is_second=" & $(o.a == "second")
    echo "b_is_third=" & $(o.b == "third")
    echo "c_is_empty=" & $(o.c == "")
  except CatchableError as e:
    echo "DECODE_RESULT=RAISE"
    echo "EXCEPTION_TYPE=" & $e.name
    echo "EXCEPTION_MSG=" & show(e.msg)

proc main() =
  let args = commandLineParams()
  if args.len != 1:
    quit("usage: probe_flavor_transfer <input-file>", 2)
  let path = args[0]
  let input = readFile(path)
  echo "harness_mode=record_default"
  echo "input_file=" & path
  echo "input_len=" & $input.len
  runRecordDefault(input)

main()
