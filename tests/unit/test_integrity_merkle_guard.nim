## SA-γ3 Merkle root guard — content-binding contract (DEBT#546 restore).
##
## The compile-time guard in config/integrity.nims and the regeneration
## authority tools/merkle_hash.nim must agree on one algorithm:
##   per-file SHA-256 over each guarded file's bytes, digests concatenated in
##   canonical (lexicographic) repo-relative path order, SHA-256 of the
##   concatenation.
## The pinned data/expected_merkle_root.txt must equal that root, and a
## one-byte tamper of a guarded file must change the root (so the compile-time
## guard turns red instead of binding to diagnostic text).

import std/[os, strutils, unittest]
import core/crypto/hash_kernel

const
  GuardedFiles = [
    "src/core/trusted/architecture_invariants.nim",
    "src/core/trusted/axiom_pragmas.nim",
    "src/core/trusted/effect_bridge.nim",
    "src/core/trusted/effect_types.nim",
  ]
  ExpectedRootPath = "data/expected_merkle_root.txt"
  GuardPath = "config/integrity.nims"
  RegeneratorPath = "tools/merkle_hash.nim"

proc findRepoRoot(): string =
  var dir = getCurrentDir()
  while true:
    if fileExists(dir / ".axiom_root"):
      return dir
    let parent = dir.parentDir()
    if parent == dir:
      break
    dir = parent
  raise newException(IOError, ".axiom_root not found from " & getCurrentDir())

proc merkleRoot(contents: openArray[string]): string =
  var concat = ""
  for content in contents:
    concat.add sha256Hex(content)
  result = sha256Hex(concat)

proc isSha256Hex(s: string): bool =
  if s.len != 64:
    return false
  for ch in s:
    if ch notin {'0'..'9', 'a'..'f'}:
      return false
  true

proc declarationOrder(src: string; files: openArray[string]): seq[int] =
  ## Position of each guarded-path literal in a declarative list. Lexicographic
  ## order of the literals is the canonical aggregation order.
  for f in files:
    result.add src.find("\"" & f & "\"")

suite "SA-γ3 merkle root guard — content binding":
  let root = findRepoRoot()

  test "pinned expected root equals the recomputed content root":
    var contents: seq[string] = @[]
    for f in GuardedFiles:
      contents.add readFile(root / f)
    let expected = readFile(root / ExpectedRootPath).strip()
    check isSha256Hex(expected)
    check merkleRoot(contents) == expected

  test "a one-byte tamper changes the root":
    var contents: seq[string] = @[]
    for f in GuardedFiles:
      contents.add readFile(root / f)
    let clean = merkleRoot(contents)
    var tampered = contents
    tampered[0] = tampered[0] & "# tamper probe\n"
    check merkleRoot(tampered) != clean

  test "guard hashes project-rooted paths and fails closed":
    let src = readFile(root / GuardPath)
    check src.contains("projectRoot / rel")
    check "extractFilename" notin src
    check "if staticFileExists(fullPath):" notin src
    check src.contains("guarded file missing: ")
    check src.contains("sha256sum \" & cmdPaths.join")
    check src.contains("valid digests for ")
    check src.contains("quit(1)")
    check "guard_merkle_root_file_missing" notin src

  test "guard and regeneration authority share the canonical order":
    let guardOrder = declarationOrder(readFile(root / GuardPath), GuardedFiles)
    let regenOrder = declarationOrder(readFile(root / RegeneratorPath), GuardedFiles)
    for pos in guardOrder:
      check pos >= 0
    for pos in regenOrder:
      check pos >= 0
    for i in 1 ..< guardOrder.len:
      check guardOrder[i - 1] < guardOrder[i]
      check regenOrder[i - 1] < regenOrder[i]