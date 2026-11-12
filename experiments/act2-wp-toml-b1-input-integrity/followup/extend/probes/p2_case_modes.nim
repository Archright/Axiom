# nim-check: skip
# Standalone subject probe: imports toml_serialization from the OUT-OF-TREE
# READ-ONLY subject clone (Zero-Footprint — the subject is never vendored into
# this repo), compiled and run with an explicit --path to the pinned clone and
# the pinned nimble pkgs2 packages; it cannot resolve that import in repo
# context by design. Marker + rationale follow the established repo convention:
# experiments/bug-verdict-e2e/cout_probe.nim. Integrity evidence: repro.sh in
# this directory; raw per-run output under raw/.
#
# p2_case_modes.nim — B1-EXTENSION Task 2: key-matching case modes
#
# Subject: <workspace>/nim-toml-serialization
#          @ 4aa8e2223649fc0837c490a4acfca7b8b1e756f9  (READ-ONLY; --path import)
#
# The case mode is only selectable on the keyed decode overload
# (decoder.nim:118-122); the un-keyed overloads hardcode TomlCaseSensitive
# (decoder.nim:127,133,144,150). An EMPTY key makes moveToKey a no-op
# (reader.nim:74-76), so `Toml_v100.decode(input, T, "", caseMode)` reproduces
# the pinned un-keyed record path (decodeRecord at TopLevel) with a selectable
# tomlCase (used by findFieldReader, reader.nim:324-325 -> utils.nim:52-87).
#
# Type candidates:
#   lower — fields `foo`, `bar` (Nim-distinct); input keys `FOO` repeated.
#   camel — fields `fooBar`, `other` (Nim-distinct); input key pairs
#           `fooBar`/`foo_bar` (Nim-ident form) and `foobar`/`FOOBAR`
#           (case-fold form).
# NOTE: two fields differing only by CASE (`Foo` + `foo`) ARE declarable in
# Nim 2.2.10 (see p2a_case_compile_attempt.nim: only underscore variants are
# rejected). That makes the prior claim's two-compare-equal-fields design
# testable exactly as proposed: type `pair` below declares `Foo` then `foo`.
# Because Nim member LOOKUP is itself style-insensitive, `o.Foo` and `o.foo`
# cannot be used to observe which slot got which value; the values are read
# positionally through a layout-identical view type (two string fields, plain
# objects, identical binary layout) instead.
#
# Usage: p2_case_modes <sensitive|insensitive|nim> <lower|camel|pair> <input-file>
# Exits 0 on managed outcomes (decode raise is reported on stdout).

import std/os
import toml_serialization

type
  Lower = object of RootObj
    foo: string
    bar: string
  Camel = object of RootObj
    fooBar: string
    other: string
  # exact proposed design: two compare-equal fields in one object
  CasePair = object
    Foo: string
    foo: string
  # positional view over CasePair (identical layout; no RTTI delta for plain objects)
  CasePairView = object
    slot0: string   # declared field `Foo`
    slot1: string   # declared field `foo`

proc show(s: string): string =
  result = "["
  for ch in s:
    case ch
    of '\n': result.add "\\n"
    of '\r': result.add "\\r"
    of '\t': result.add "\\t"
    else: result.add ch
  result.add "]"

proc caseVal(name: string): TomlCase =
  case name
  of "sensitive": TomlCaseSensitive
  of "insensitive": TomlCaseInsensitive
  of "nim": TomlCaseNim
  else: quit("unknown case mode: " & name, 2)

proc report(callName: string, ok: bool, e: ref CatchableError, fields: varargs[string]) =
  echo "decode_call=" & callName
  if ok:
    echo "DECODE_RESULT=OK"
    for f in fields: echo f
  else:
    echo "DECODE_RESULT=RAISE"
    echo "EXCEPTION_TYPE=" & $e.name
    echo "EXCEPTION_MSG=" & show(e.msg)

proc main() =
  let args = commandLineParams()
  if args.len != 3:
    quit("usage: p2_case_modes <sensitive|insensitive|nim> <lower|camel|pair> <input-file>", 2)
  let c = caseVal(args[0])
  let input = readFile(args[2])
  echo "probe=p2_case_modes"
  echo "case_mode=" & args[0]
  echo "type_name=" & args[1]
  echo "input_file=" & args[2]
  echo "input_len=" & $input.len
  case args[1]
  of "lower":
    try:
      let o = Toml_v100.decode(input, Lower, "", c)
      report("Toml_v100.decode(input, Lower, \"\", " & args[0] & "Case)", true, nil,
             "foo=" & show(o.foo), "bar=" & show(o.bar),
             "foo_is_y=" & $(o.foo == "y"), "bar_is_y=" & $(o.bar == "y"))
    except CatchableError as e:
      report("Toml_v100.decode(input, Lower, \"\", " & args[0] & "Case)", false, e)
  of "camel":
    try:
      let o = Toml_v100.decode(input, Camel, "", c)
      report("Toml_v100.decode(input, Camel, \"\", " & args[0] & "Case)", true, nil,
             "fooBar=" & show(o.fooBar), "other=" & show(o.other),
             "fooBar_is_y=" & $(o.fooBar == "y"), "other_is_y=" & $(o.other == "y"))
    except CatchableError as e:
      report("Toml_v100.decode(input, Camel, \"\", " & args[0] & "Case)", false, e)
  of "pair":
    try:
      let o = Toml_v100.decode(input, CasePair, "", c)
      let v = cast[CasePairView](o)
      report("Toml_v100.decode(input, CasePair, \"\", " & args[0] & "Case)", true, nil,
             "slot0_Foo=" & show(v.slot0), "slot1_foo=" & show(v.slot1),
             "slot0_is_x=" & $(v.slot0 == "x"), "slot1_is_y=" & $(v.slot1 == "y"))
    except CatchableError as e:
      report("Toml_v100.decode(input, CasePair, \"\", " & args[0] & "Case)", false, e)
  else:
    quit("unknown type: " & args[1], 2)

main()
