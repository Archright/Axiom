import core/trusted/layer_declaration
axiomLayer "tools"
import std/[strutils]
import checksums/sha2

const guardedFiles = [
  "src/core/trusted/architecture_invariants.nim",
  "src/core/trusted/axiom_pragmas.nim",
  "src/core/trusted/effect_types.nim",
  "src/core/trusted/effect_bridge.nim"
]

var allHashes = ""
for f in guardedFiles:
  let hash = $secureHash(Sha_256, readFile(f))
  allHashes &= hash.toLower()
echo $secureHash(Sha_256, allHashes)
