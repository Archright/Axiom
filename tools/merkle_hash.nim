import core/trusted/layer_declaration
axiomLayer "tools"
import std/[strutils]
import checksums/sha2

# Canonical order: lexicographic by repo-relative path. Shared with the SA-γ3
# compile-time guard in config/integrity.nims — keep both lists in sync.
# Regeneration authority (run from repo root after an intentional change):
#   nim c --hints:off -d:AXIOM_GATE_BOND -o:bin/merkle_hash tools/merkle_hash.nim
#   bin/merkle_hash > data/expected_merkle_root.txt
const guardedFiles = [
  "src/core/trusted/architecture_invariants.nim",
  "src/core/trusted/axiom_pragmas.nim",
  "src/core/trusted/effect_bridge.nim",
  "src/core/trusted/effect_types.nim"
]

var allHashes = ""
for f in guardedFiles:
  let hash = $secureHash(Sha_256, readFile(f))
  allHashes &= hash.toLower()
echo $secureHash(Sha_256, allHashes)
