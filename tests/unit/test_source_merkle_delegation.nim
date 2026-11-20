import std/[algorithm, os, strutils]
import unittest
import core/symbol_graph/global_symbol_graph_builder_part2
import core/utils/file_utils
import core/crypto/hash_kernel

proc inProcessRoot(srcRoot: string): string =
  ## The pre-delegation fold: per-file `computeFileHash`, skip unmeasurable,
  ## `path:hash\n` records sorted by path, root over the accumulator.
  var paths: seq[string] = @[]
  for p in walkDirRec(srcRoot):
    if p.endsWith(".nim"):
      paths.add p
  paths.sort(cmp)
  var acc = ""
  for p in paths:
    let h = computeFileHash(p)
    if h.len > 0:
      acc = acc & p & ":" & h & "\n"
  hash_kernel.sha256Hex(acc)

proc writeNim(dir, name, body: string) =
  writeFile(dir / name, body)

suite "Source Merkle root — platform hash delegation":
  test "root is byte-identical to the in-process fold":
    let dir = getTempDir() / "axiom_merkle_delegation_t1"
    removeDir(dir)
    createDir(dir)
    writeNim(dir, "alpha.nim", "proc alpha*() = discard\n")
    writeNim(dir, "empty.nim", "")
    writeNim(dir, "with space.nim", "proc spaced*() = discard\n")
    writeNim(dir, "with\nnewline.nim", "proc newline*() = discard\n")
    writeNim(dir, "한글.nim", "proc hangul*() = discard\n")
    writeNim(dir, "ignored.txt", "not a .nim file\n")
    let expected = inProcessRoot(dir)
    check expected.len == 64
    check computeSourceMerkleRoot(dir) == expected
    removeDir(dir)

  test "root is deterministic across repeated calls":
    let dir = getTempDir() / "axiom_merkle_delegation_t2"
    removeDir(dir)
    createDir(dir)
    writeNim(dir, "a.nim", "proc a*() = discard\n")
    writeNim(dir, "b.nim", "proc b*() = discard\n")
    let first = computeSourceMerkleRoot(dir)
    check computeSourceMerkleRoot(dir) == first
    check first == inProcessRoot(dir)
    removeDir(dir)

  test "unreadable-at-discovery tree falls back without corrupting the root":
    let dir = getTempDir() / "axiom_merkle_delegation_t3"
    removeDir(dir)
    createDir(dir)
    writeNim(dir, "a.nim", "proc a*() = discard\n")
    let expected = computeSourceMerkleRoot(dir)
    let savedPath = getEnv("PATH")
    putEnv("PATH", "")
    check computeSourceMerkleRoot(dir) == expected
    putEnv("PATH", savedPath)
    check computeSourceMerkleRoot(dir) == expected
    removeDir(dir)

  test "empty tree folds to sha256 of the empty accumulator":
    let dir = getTempDir() / "axiom_merkle_delegation_t4"
    removeDir(dir)
    createDir(dir)
    check computeSourceMerkleRoot(dir) == hash_kernel.sha256Hex("")
    removeDir(dir)