## SA-γ3 Merkle root guard — content binding (DEBT#546 restore).
##
## The compile-time guard in config/integrity.nims hashes the four guarded
## files' bytes with the host sha256sum primitive, concatenates the digests in
## the declared order and hashes the concatenation. This suite pins that
## algorithm to data/expected_merkle_root.txt and rejects a regression to the
## pre-restore behaviour (bare filenames, verdict bound to diagnostic text).

import std/[os, strutils, unittest]
import core/crypto/hash_kernel

const
  GuardedFiles = [
    "src/core/trusted/architecture_invariants.nim",
    "src/core/trusted/axiom_pragmas.nim",
    "src/core/trusted/effect_types.nim",
    "src/core/trusted/effect_bridge.nim",
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

proc literalsInOrder(src: string; files: openArray[string]): seq[int] =
  ## Position of each guarded-path literal in the source. A negative entry
  ## means the literal is missing.
  for f in files:
    result.add src.find("\"" & f & "\"")

proc isIncreasing(whenOrdered: seq[int]): bool =
  result = whenOrdered.len == GuardedFiles.len
  for i, pos in whenOrdered:
    if pos < 0:
      return false
    if i > 0 and whenOrdered[i - 1] >= pos:
      return false

suite "SA-γ3 merkle root guard — content binding":
  let root = findRepoRoot()

  test "pinned root equals sha256 over the guarded file contents":
    var contents: seq[string] = @[]
    for f in GuardedFiles:
      contents.add readFile(root / f)
    let pinned = readFile(root / ExpectedRootPath).strip()
    check pinned.len == 64
    check pinned == merkleRoot(contents)

  test "changing one byte changes the root":
    var contents: seq[string] = @[]
    for f in GuardedFiles:
      contents.add readFile(root / f)
    let clean = merkleRoot(contents)
    var tampered = contents
    tampered[0][0] = char(ord(tampered[0][0]) xor 1)
    check tampered[0] != contents[0]
    check merkleRoot(tampered) != clean

  test "guard hashes project-rooted paths and fails closed":
    let src = readFile(root / GuardPath)
    check "extractFilename" notin src
    check src.contains("let fullPath = projectRoot / rel")
    check src.contains("guarded file missing: ")
    check src.contains("splitWhitespace")
    check src.contains("quit(1)")
    check "actualMerkle.len > 0 and" notin src

  test "guard and regeneration authority share one declared order":
    check isIncreasing(literalsInOrder(readFile(root / GuardPath), GuardedFiles))
    check isIncreasing(literalsInOrder(readFile(root / RegeneratorPath), GuardedFiles))