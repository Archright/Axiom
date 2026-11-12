# nim-check: skip
# Standalone subject probe: imports toml_serialization from the OUT-OF-TREE
# READ-ONLY subject clone (Zero-Footprint — the subject is never vendored into
# this repo), compiled and run with an explicit --path to the pinned clone and
# the pinned nimble pkgs2 packages; it cannot resolve that import in repo
# context by design. Marker + rationale follow the established repo convention:
# experiments/bug-verdict-e2e/cout_probe.nim. Integrity evidence: repro.sh in
# this directory; raw per-run output under raw/.
#
# p3_fragment_recipe.nim — B1-EXTENSION Task 3: fragment recipe
# N = totalFields − k on the TOP-LEVEL record path
#
# Subject: <workspace>/nim-toml-serialization
#          @ 4aa8e2223649fc0837c490a4acfca7b8b1e756f9  (READ-ONLY; --path import)
#
# Pinned configuration (identical to the base study): Toml_v100 flavor,
# UN-KEYED decode, no TomlUnknownFields. Type under test:
#   Obj = object of RootObj   (totalSerializedFields(Obj) == 3)
#     a, b, c: string
# Every matched entry increments fieldsDone (reader.nim:334); duplicates of an
# already-matched key re-match through the wrap-around loop (utils.nim:83-85)
# WITHOUT advancing expectedFieldPos, and when fieldsDone >= totalFields the
# loop breaks (reader.nim:345-346) so all later input is never read.
#
# Modes:
#   record     -> Toml_v100.decode(input, Obj)
#   value_v100 -> Toml_v100.decode(input, TomlValueRef)  (control: value path
#                   reads the whole document, no early break anywhere)
#
# The harness exits 0 for every successfully-executed run, including runs
# where decode raised (reported on stdout). Non-zero exit = harness misuse.

import std/[os, tables]
import toml_serialization

type
  Obj = object of RootObj
    a: string
    b: string
    c: string

proc show(s: string): string =
  result = "["
  for ch in s:
    case ch
    of '\n': result.add "\\n"
    of '\r': result.add "\\r"
    of '\t': result.add "\\t"
    else: result.add ch
  result.add "]"

proc showValue(v: TomlValueRef, indent: string): string =
  case v.kind
  of TomlKind.String:
    result = indent & "String " & show(v.stringVal)
  of TomlKind.InlineTable, TomlKind.Table:
    result = indent & ($v.kind) & " len=" & $v.tableVal[].len & "\n"
    var first = true
    for k, val in v.tableVal[]:
      if not first: result.add "\n"
      first = false
      result.add indent & "  key=" & show(k) & " ->\n" &
        showValue(val, indent & "    ")
  else:
    result = indent & $v.kind

proc runRecord(input: string) =
  echo "decode_call=Toml_v100.decode(input, Obj)"
  try:
    let o = Toml_v100.decode(input, Obj)
    echo "DECODE_RESULT=OK"
    echo "a=" & show(o.a)
    echo "b=" & show(o.b)
    echo "c=" & show(o.c)
    echo "c_is_empty=" & $(o.c == "")
    echo "c_is_later=" & $(o.c == "later")
  except CatchableError as e:
    echo "DECODE_RESULT=RAISE"
    echo "EXCEPTION_TYPE=" & $e.name
    echo "EXCEPTION_MSG=" & show(e.msg)

proc runValue(input: string) =
  echo "decode_call=Toml_v100.decode(input, TomlValueRef)"
  try:
    let v = Toml_v100.decode(input, TomlValueRef)
    echo "DECODE_RESULT=OK"
    echo "root=" & showValue(v, "")
  except CatchableError as e:
    echo "DECODE_RESULT=RAISE"
    echo "EXCEPTION_TYPE=" & $e.name
    echo "EXCEPTION_MSG=" & show(e.msg)

proc main() =
  let args = commandLineParams()
  if args.len != 2:
    quit("usage: p3_fragment_recipe <record|value_v100> <input-file>", 2)
  let input = readFile(args[1])
  echo "probe=p3_fragment_recipe"
  echo "mode=" & args[0]
  echo "input_file=" & args[1]
  echo "input_len=" & $input.len
  case args[0]
  of "record": runRecord(input)
  of "value_v100": runValue(input)
  else: quit("unknown mode: " & args[0], 2)

main()
