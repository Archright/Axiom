# nim-check: skip
# OUT-OF-TREE probe: imports niprefs (ImThemes' nimble.lock pin: niprefs
# 0.3.5 @ 30f522ac1888ae2930e833ab6c5d954baf3e8702) whose re-export chain
# pulls toml_serialization @ b5b387e6fb2a7cc75d54a269b07cc6218361bd46
# (ImThemes' nimble.lock pin), all via explicit --path; unresolvable in repo
# context by design. It replicates the exact ImThemes call form
# (src/browseview.nim:193 `Toml.loadFile(path, TomlValueRef)["themes"].getTables()`
# — value-tree path, no typed object, no flags argument) to determine whether
# `TomlHexEscape` is ACTIVE at the revision ImThemes actually builds against
# (B-SEC-03 reachability, static+dynamic evidence for bsec/callsite.md).
import std/strutils
import niprefs

proc hexify(s: string): string =
  for b in s:
    result.add toHex(ord(b), 2)

proc tryLoad(label, content: string) =
  let path = "/tmp/bsec_callsite/inputs/" & label & ".toml"
  writeFile(path, content)
  try:
    let feed = Toml.loadFile(path, TomlValueRef)["themes"].getTables()
    echo label & ": OK themes=" & $feed.len & " name=[" & feed[0]["name"].getString() &
        "] bytes=[" & hexify(feed[0]["name"].getString()) & "]"
  except CatchableError as e:
    echo label & ": REJECTED " & $e.name & ": " & e.msg

tryLoad("imthemes_control", "[[themes]]\nname = \"plain\"\n")
tryLoad("imthemes_hex_45", "[[themes]]\nname = \"Jos\\xE9\"\n")
tryLoad("imthemes_hex_80", "[[themes]]\nname = \"\\x80\"\n")
