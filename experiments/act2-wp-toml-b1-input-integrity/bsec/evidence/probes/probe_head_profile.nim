# nim-check: skip
# OUT-OF-TREE probe: imports toml_serialization from the READ-ONLY subject
# clone @ 4aa8e2223649fc0837c490a4acfca7b8b1e756f9 via explicit --path;
# cannot resolve that import in repo context by design. Counterfactual arm of
# the B-SEC-03 call-site study: 4aa8e22 is upstream HEAD and reports the SAME
# version string ("0.2.18") as b5b387e6, but nimble never resolves to it
# (untagged). Runs BOTH consumer call forms (nph's typed
# `Toml.loadFile(file, NphConfig)` and ImThemes' value-tree
# `Toml.loadFile(file, TomlValueRef)["themes"]`) against the DEFAULT `Toml`
# flavor to record how the identical inputs behave at this revision.
import std/[strutils, tables]
import toml_serialization

type NphConfig = object
  exclude: seq[string]
  extendExclude {.serializedFieldName("extend-exclude").}: seq[string]
  includePatterns {.serializedFieldName("include").}: seq[string]
  color: Option[bool]

proc hexify(s: string): string =
  for b in s:
    result.add toHex(ord(b), 2)

proc tryTyped(label, content: string) =
  let path = "/tmp/bsec_callsite/inputs/head_" & label & ".toml"
  writeFile(path, content)
  try:
    let cfg = Toml.loadFile(path, NphConfig)
    echo "typed/" & label & ": OK exclude=" & $cfg.exclude & " bytes=[" & hexify(
        cfg.exclude.join("")) & "]"
  except CatchableError as e:
    echo "typed/" & label & ": REJECTED " & $e.name & ": " & e.msg

proc tryValueTree(label, content: string) =
  let path = "/tmp/bsec_callsite/inputs/headvt_" & label & ".toml"
  writeFile(path, content)
  try:
    # HEAD does not re-export value_ops, so nodeutils' `["themes"]` accessor is
    # unavailable here; the variant-object fields (types.nim) are used instead.
    let root = Toml.loadFile(path, TomlValueRef)
    var nameNode: TomlValueRef
    if root.kind == TomlKind.Tables:
      nameNode = root.tablesVal[0]["name"]
    else:
      # [[themes]] parses to a Tables-kind child (seq[TomlTableRef]) at HEAD
      nameNode = root.tableVal["themes"].tablesVal[0]["name"]
    echo "valuetree/" & label & ": OK rootkind=" & $root.kind & " bytes=[" & hexify(
        nameNode.stringVal) & "]"
  except CatchableError as e:
    echo "valuetree/" & label & ": REJECTED " & $e.name & ": " & e.msg

tryTyped("control", "exclude = [\"plain\"]\n")
tryTyped("hex_45", "exclude = [\"Jos\\x45\"]\n")
tryTyped("hex_80", "exclude = [\"\\x80\"]\n")
tryValueTree("control", "[[themes]]\nname = \"plain\"\n")
tryValueTree("hex_45", "[[themes]]\nname = \"Jos\\xE9\"\n")
tryValueTree("hex_80", "[[themes]]\nname = \"\\x80\"\n")
