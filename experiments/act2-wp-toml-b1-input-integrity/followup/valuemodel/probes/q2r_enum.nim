# nim-check: skip
# valuemodel/q2r_enum: Task 2 — `node[k, SomeEnum]` CANNOT COMPILE for any
# enum type: innerValue's enum branch (value_ops.nim:37-41) calls
# strutils.parseEnum[T], which may raise ValueError, forbidden by the module
# push raises:[] at value_ops.nim:8 — identical failure to q2c_enum. This
# source is kept as the runtime-behavior probe that the subject makes
# unreachable; its COMPILE_EXIT=1 (raw/q2r_enum.compile.out) IS the recorded
# datum for T=enum. Subject: nim-toml-serialization
# @4aa8e2223649fc0837c490a4acfca7b8b1e756f9 (out-of-tree READ-ONLY clone;
# explicit --path; convention: experiments/bug-verdict-e2e/cout_probe.nim).
import std/[os, tables]
import toml_serialization
import toml_serialization/value_ops

type Fruit = enum
  fApple = (1, "apple")
  fBanana = (2, "banana")

let t = TomlValueRef(kind: TomlKind.Table)
t.tableVal = TomlTableRef.new
t.tableVal["i"] = TomlValueRef(kind: TomlKind.Int, intVal: 2)
t.tableVal["s"] = TomlValueRef(kind: TomlKind.String, stringVal: "banana")
t.tableVal["s2"] = TomlValueRef(kind: TomlKind.String, stringVal: "fBanana")
t.tableVal["f"] = TomlValueRef(kind: TomlKind.Float, floatVal: 1.5)

if paramStr(1) == "absent":
  let v = t["absent", Fruit]
  echo "RESULT absent-v=", $v
else:
  echo "RESULT match-i(2)=", $t["i", Fruit]
  echo "RESULT match-s(banana)=", $t["s", Fruit]
  echo "RESULT miss-name(fBanana)->default=", $t["s2", Fruit]
  echo "RESULT mismatch-f->default=", $t["f", Fruit]
