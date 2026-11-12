# nim-check: skip
# Standalone subject probe: imports toml_serialization from the OUT-OF-TREE
# READ-ONLY subject clone (Zero-Footprint — the subject is never vendored into
# this repo), compiled and run with an explicit --path to the pinned clone and
# the pinned nimble pkgs2 packages; it cannot resolve that import in repo
# context by design. Marker + rationale follow the established repo convention:
# experiments/bug-verdict-e2e/cout_probe.nim. Integrity evidence: repro.sh in
# this directory; raw per-run output under raw/.
#
# p1_inline_table.nim — B1-EXTENSION Task 1: inline-table decode path
#
# Subject: <workspace>/nim-toml-serialization
#          @ 4aa8e2223649fc0837c490a4acfca7b8b1e756f9  (READ-ONLY; --path import)
#
# Paths under test:
#   typed        -> Toml_v100.decode(input, Outer)  Outer{t: Inner{a: string}};
#                     the inline table lands in the TYPED OBJECT FIELD `t`, so
#                     readRecordValue sees state==ExpectValue (reader.nim:303,
#                     385-389) and dispatches decodeInlineTable (reader.nim:348)
#                     driving parseInlineTableImpl (lexer.nim:1670) with
#                     findFieldReader in the value action (reader.nim:372-373).
#   whole_typed  -> Toml_v100.decode(input, Inner)  whole document is the
#                     inline-table text; un-keyed decode leaves state==TopLevel
#                     (reader.nim:66, reader.nim:74-76), so decodeRecord runs.
#   value_v100   -> Toml_v100.decode(input, TomlValueRef)  spec-conforming
#                     value path (reader.nim:442-444 -> parseValue -> lexer.nim
#                     :1827-1832 parseInlineTable with duplicate check at
#                     lexer.nim:1784-1785).
#   value_default-> Toml.decode(input, TomlValueRef)  default v1.1.0 flavor
#                     (contrast; format.nim:36).
#
# The harness exits 0 for every successfully-executed run, including runs where
# decode raised: the decode outcome is reported on stdout (DECODE_RESULT line)
# so the recorded process exit code stays attributable to the harness itself.
# Non-zero exit = harness misuse (bad args / unreadable input file).

import std/[os, tables]
import toml_serialization

type
  Inner = object of RootObj
    a: string
  Outer = object of RootObj
    t: Inner
  Outer2 = object of RootObj
    t: Inner
    u: string

proc show(s: string): string =
  result = "["
  for ch in s:
    case ch
    of '\n': result.add "\\n"
    of '\r': result.add "\\r"
    of '\t': result.add "\\t"
    else: result.add ch
  result.add "]"

proc showException(e: ref CatchableError): string =
  if e of TomlFieldReadingError:
    let fr = (ref TomlFieldReadingError)(e)
    "field=" & show(fr.field) & " inner_type=" & $fr.error.name &
      " inner_msg=" & show(fr.error.msg) & " line=" & $fr.line & " col=" & $fr.col
  elif e of TomlReaderError:
    let re = (ref TomlReaderError)(e)
    "msg=" & show(e.msg) & " line=" & $re.line & " col=" & $re.col
  else:
    "msg=" & show(e.msg)

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

proc runTyped(input: string, whole: bool) =
  if whole:
    echo "decode_call=Toml_v100.decode(input, Inner)"
    try:
      let o = Toml_v100.decode(input, Inner)
      echo "DECODE_RESULT=OK"
      echo "a=" & show(o.a)
    except CatchableError as e:
      echo "DECODE_RESULT=RAISE"
      echo "EXCEPTION_TYPE=" & $e.name
      echo "EXCEPTION_MSG=" & show(e.msg)
      echo "EXCEPTION_DETAIL=" & showException(e)
  else:
    echo "decode_call=Toml_v100.decode(input, Outer)"
    try:
      let o = Toml_v100.decode(input, Outer)
      echo "DECODE_RESULT=OK"
      echo "t_a=" & show(o.t.a)
      echo "a_is_2=" & $(o.t.a == "2")
    except CatchableError as e:
      echo "DECODE_RESULT=RAISE"
      echo "EXCEPTION_TYPE=" & $e.name
      echo "EXCEPTION_MSG=" & show(e.msg)
      echo "EXCEPTION_DETAIL=" & showException(e)

proc runTyped2(input: string) =
  echo "decode_call=Toml_v100.decode(input, Outer2)"
  try:
    let o = Toml_v100.decode(input, Outer2)
    echo "DECODE_RESULT=OK"
    echo "t_a=" & show(o.t.a)
    echo "u=" & show(o.u)
  except CatchableError as e:
    echo "DECODE_RESULT=RAISE"
    echo "EXCEPTION_TYPE=" & $e.name
    echo "EXCEPTION_MSG=" & show(e.msg)
    echo "EXCEPTION_DETAIL=" & showException(e)

proc runValue(Flavor: typedesc, callName: string, input: string) =
  mixin decode
  echo "decode_call=" & callName
  try:
    let v = Flavor.decode(input, TomlValueRef)
    echo "DECODE_RESULT=OK"
    echo "root=" & showValue(v, "")
  except CatchableError as e:
    echo "DECODE_RESULT=RAISE"
    echo "EXCEPTION_TYPE=" & $e.name
    echo "EXCEPTION_MSG=" & show(e.msg)

proc main() =
  let args = commandLineParams()
  if args.len != 2:
    quit("usage: p1_inline_table <typed|typed2|whole_typed|value_v100|value_default> <input-file>", 2)
  let mode = args[0]
  let input = readFile(args[1])
  echo "probe=p1_inline_table"
  echo "mode=" & mode
  echo "input_file=" & args[1]
  echo "input_len=" & $input.len
  case mode
  of "typed": runTyped(input, false)
  of "typed2": runTyped2(input)
  of "whole_typed": runTyped(input, true)
  of "value_v100": runValue(Toml_v100, "Toml_v100.decode(input, TomlValueRef)", input)
  of "value_default": runValue(Toml, "Toml.decode(input, TomlValueRef)", input)
  else: quit("unknown mode: " & mode, 2)

main()
