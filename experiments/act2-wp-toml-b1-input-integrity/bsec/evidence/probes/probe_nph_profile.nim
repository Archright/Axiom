# nim-check: skip
# OUT-OF-TREE probe: imports toml_serialization from nph's installed
# dependency snapshot (/tmp/capdelta/nph/nimbledeps/pkgs2, toml_serialization
# vcsRevision b5b387e6fb2a7cc75d54a269b07cc6218361bd46) via explicit --path;
# it cannot resolve that import in repo context by design. It replicates the
# exact nph call form (src/nph.nim:103 `Toml.loadFile(configFile, NphConfig)`,
# un-keyed, no flags argument, bare `Toml` flavor symbol) to determine whether
# `TomlHexEscape` is ACTIVE at the revision nph actually builds against
# (B-SEC-03 reachability, static+dynamic evidence for bsec/callsite.md).
import std/strutils
import toml_serialization

type NphConfig = object
  exclude: seq[string]
  extendExclude {.serializedFieldName("extend-exclude").}: seq[string]
  includePatterns {.serializedFieldName("include").}: seq[string]
  color: Option[bool]

proc hexify(s: string): string =
  for b in s:
    result.add toHex(ord(b), 2)

proc tryLoad(label, content: string) =
  let path = "/tmp/bsec_callsite/inputs/" & label & ".toml"
  writeFile(path, content)
  try:
    let cfg = Toml.loadFile(path, NphConfig)
    echo label & ": OK exclude=" & $cfg.exclude & " bytes=[" & hexify(
        cfg.exclude.join("")) & "] color=" & $cfg.color
  except CatchableError as e:
    var name = $e.name
    var msg = e.msg
    if e of TomlFieldReadingError:
      let g = (ref TomlFieldReadingError)(e)
      name = name & "{field=" & g.field & ", inner=" & $g.error.name & "}"
      msg = g.error.msg
    elif e of GenericTomlReaderError:
      let g = (ref GenericTomlReaderError)(e)
      name = name & "{field=" & g.deserializedField & ", inner=" & $g.innerException.name & "}"
      msg = g.innerException.msg
    echo label & ": REJECTED " & name & ": " & msg

tryLoad("nph_control", "exclude = [\"plain\"]\n")
tryLoad("nph_hex_45", "exclude = [\"Jos\\x45\"]\n")
tryLoad("nph_hex_80", "exclude = [\"\\x80\"]\n")
