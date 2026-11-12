# nim-check: skip
# Rationale: canonicalization runner that reuses Axiom3's SINGLE canonical
# projection implementation (src/core/utils/canonical_projection.nim:
# canonicalProjectionHash + stripVolatile, mandated as the only implementation
# by docs/spec/productization_contract.md §6). The import chain
# (core/crypto/hash_kernel -> checksums/sha2) resolves only with --path entries
# to <Axiom3>/src and the pinned nimble checksums package; it cannot resolve in
# repo-context standalone checks by design, and no second volatile-key list is
# defined here.
#
# Usage: p0d2_canon <evidence.json> <out-canonical.json>
#   - writes stripVolatile(parse(input)) rendered by std/json to <out>
#   - prints "canonicalProjectionHash: <hex>" (SHA-256 of the sorted,
#     volatility-stripped projection, per the SSOT)
import std/[json, os]
import core/utils/canonical_projection

when isMainModule:
  if paramCount() != 2:
    stderr.writeLine "usage: p0d2_canon <evidence.json> <out-canonical.json>"
    quit(QuitFailure)
  let node = parseFile(paramStr(1))
  let stripped = stripVolatile(node)
  writeFile(paramStr(2), $stripped & "\n")
  echo "canonicalProjectionHash: ", canonicalProjectionHash(node)
