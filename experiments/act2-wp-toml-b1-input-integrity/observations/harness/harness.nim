# nim-check: skip
# Standalone subject probe: imports toml_serialization from the OUT-OF-TREE
# READ-ONLY subject clone (Zero-Footprint — the subject is never vendored into
# this repo), compiled and run with an explicit --path to the pinned clone and
# the pinned nimble pkgs2 packages; it cannot resolve that import in repo
# context by design. Integrity is verified by executing it against the pinned
# subject (observations/repro.sh, raw evidence under observations/raw/).
# Marker + rationale follow the established repo convention:
# experiments/bug-verdict-e2e/cout_probe.nim.
# harness.nim — B1 input-integrity reproduction harness for nim-toml-serialization
#
# Subject: <workspace>/nim-toml-serialization
#          @ 4aa8e2223649fc0837c490a4acfca7b8b1e756f9  (READ-ONLY; imported via --path)
#
# Modes:
#   record        -> Toml_v100.decode(input, Obj)          (UN-KEYED form: no key argument;
#                                                             TomlUnknownFields NOT set;
#                                                             Toml_v100 runtimeFlags = {})
#   value_v100    -> Toml_v100.decode(input, TomlValueRef) (spec-conforming value path)
#   value_default -> Toml.decode(input, TomlValueRef)      (default v1.1.0 flavor; contrast)
#
# The harness exits 0 for every successfully-executed run, including runs where
# decode raised: the decode outcome is reported on stdout (DECODE_RESULT line)
# so that the recorded process exit code stays attributable to the harness
# itself. Non-zero exit = harness misuse (bad args / unreadable input file).

import std/os
import toml_serialization

type
  Obj = object of RootObj
    a: string
    b: string
    c: string

proc show(s: string): string =
  ## Bracket-delimited, control-char-escaped rendering so that empty strings
  ## and whitespace are visible verbatim in the recorded output.
  result = "["
  for ch in s:
    case ch
    of '\n': result.add "\\n"
    of '\r': result.add "\\r"
    of '\t': result.add "\\t"
    else: result.add ch
  result.add "]"

proc runRecord(input: string) =
  echo "decode_call=Toml_v100.decode(input, Obj)"
  try:
    let o = Toml_v100.decode(input, Obj)
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

proc runValue(Flavor: typedesc, callName: string, input: string) =
  mixin decode
  echo "decode_call=" & callName
  try:
    let v = Flavor.decode(input, TomlValueRef)
    echo "DECODE_RESULT=OK"
    echo "value_kind=" & $v.kind
  except CatchableError as e:
    echo "DECODE_RESULT=RAISE"
    echo "EXCEPTION_TYPE=" & $e.name
    echo "EXCEPTION_MSG=" & show(e.msg)

proc main() =
  let args = commandLineParams()
  if args.len != 2:
    quit("usage: harness <record|value_v100|value_default> <input-file>", 2)
  let mode = args[0]
  let path = args[1]
  let input = readFile(path)
  echo "harness_mode=" & mode
  echo "input_file=" & path
  echo "input_len=" & $input.len
  case mode
  of "record":
    runRecord(input)
  of "value_v100":
    runValue(Toml_v100, "Toml_v100.decode(input, TomlValueRef)", input)
  of "value_default":
    runValue(Toml, "Toml.decode(input, TomlValueRef)", input)
  else:
    quit("unknown mode: " & mode, 2)

main()
