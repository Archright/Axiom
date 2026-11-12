# nim-check: skip
# Standalone subject probe (defects3/p3): imports toml_serialization from the
# OUT-OF-TREE READ-ONLY subject clone @4aa8e2223649fc0837c490a4acfca7b8b1e756f9;
# compiled with explicit --path from /tmp, so it cannot resolve that import in
# repo context by design (convention: experiments/bug-verdict-e2e/cout_probe.nim).
# Defect 3: reader.nim:89-96 `expectChars` templates hardcode `skipLf` in their
# bodies and ignore their own `skip` parameter. Consequence under test: an
# intervening newline between `=` and the value is silently skipped before
# typed int/float/date reads (reader.nim:455-478, 569-607), so `key =\n5`
# may be accepted. Each case prints ACCEPTED (with value) or REJECTED (with
# the exact error) -- the record of what the library actually does.
import std/strutils
import toml_serialization

type Conf = object
  x*: int

proc valStr(v: TomlDate): string =
  $v.year & "-" & $v.month & "-" & $v.day

proc valStr(v: TomlTime): string =
  $v.hour & ":" & $v.minute & ":" & $v.second

proc valStr(v: TomlDateTime): string =
  result = ""
  if v.date.isSome: result.add valStr(v.date.get)
  if v.time.isSome:
    if result.len > 0: result.add " "
    result.add valStr(v.time.get)

proc valStr(v: Conf): string =
  "Conf(x=" & $v.x & ")"

proc valStr[T](v: T): string =
  $v

proc valStr(v: TomlValueRef): string =
  if isNil(v): "nil"
  elif v.kind == TomlKind.Int: "TomlValueRef(Int=" & $v.intVal & ")"
  else: "TomlValueRef(kind=" & $v.kind & ")"

proc probeKeyed(label: string, T: type, input: string, key: string) =
  try:
    let v = Toml.decode(input, T, key)
    echo "keyed ", label, " ", escape(input), " -> ACCEPTED value=", valStr(v)
  except TomlError as e:
    echo "keyed ", label, " ", escape(input), " -> REJECTED TomlError: ", e.msg
  except CatchableError as e:
    echo "keyed ", label, " ", escape(input), " -> REJECTED ", e.name, ": ", e.msg

proc probeUnkeyed(label: string, T: type, input: string) =
  try:
    let v = Toml.decode(input, T)
    echo "unkeyed ", label, " ", escape(input), " -> ACCEPTED value=", valStr(v)
  except TomlError as e:
    echo "unkeyed ", label, " ", escape(input), " -> REJECTED TomlError: ", e.msg
  except CatchableError as e:
    echo "unkeyed ", label, " ", escape(input), " -> REJECTED ", e.name, ": ", e.msg

# -- the defect-3 question: KEYED form with LF between '=' and value --
probeKeyed("int", int, "key =\n5", "key")
# -- controls --
probeKeyed("int", int, "key = 5", "key")        # value on same line
probeKeyed("int", int, "key =\n\"s\"", "key")   # wrong type AFTER the newline:
                                                # proves expectChars really scans
                                                # the post-newline char
# -- other typed reads reachable through the same expectChars --
probeKeyed("float", float, "f =\n1.5", "f")
probeKeyed("TomlDate", TomlDate, "d =\n1979-05-27", "d")
probeKeyed("TomlTime", TomlTime, "t =\n07:32:00", "t")
probeKeyed("TomlDateTime", TomlDateTime, "dt =\n1979-05-27T07:32:00Z", "dt")
probeKeyed("string", string, "s =\n\"x\"", "s") # string path uses nonws(skipLf) too
probeKeyed("bool", bool, "b =\ntrue", "b")
# -- unkeyed form --
# Unkeyed SCALAR decode is a compile-time fatal by design (decoder.nim:19-27
# TomlNotTopLevel guard -> "'int' not allowed at top level Toml"); evidence:
# raw/p3.unkeyed_scalar_fatal.compile.out. Legal unkeyed forms are
# object/tuple/TomlValueRef -- those are probed here.
probeUnkeyed("TomlValueRef-int", TomlValueRef, "5")      # bare value control
probeUnkeyed("TomlValueRef-int-lf", TomlValueRef, "\n5") # leading LF before bare value
probeUnkeyed("object", Conf, "x =\n5")                   # object-field path
