import std/os
import std/strformat
import std/strutils
import std/unittest

import core/audit/content_hash
import core/audit/theater_skip

proc tempDir(name: string): string =
  let dir = getTempDir() / name & "_" & $getCurrentProcessId()
  removeDir(dir)
  createDir(dir)
  result = dir

suite "theater skip audit":
  test "computeProcHash hashes matching proc text":
    let dir = tempDir("axiom_theater_skip_hash")
    defer: removeDir(dir)
    let sourcePath = dir / "sample.nim"
    writeFile(sourcePath, """
proc alpha(x: int): int =
  result = x + 1

proc beta(): int =
  result = 2
""")

    let alphaHash = computeProcHash(sourcePath, "alpha")
    let betaHash = computeProcHash(sourcePath, "beta")

    check alphaHash.startsWith("sha256:")
    check alphaHash.len == 71
    check alphaHash != betaHash

  test "computeProcHash returns empty signature hash when symbol is absent":
    let dir = tempDir("axiom_theater_skip_missing_symbol")
    defer: removeDir(dir)
    let sourcePath = dir / "sample.nim"
    writeFile(sourcePath, "proc alpha(): int =\n  result = 1\n")

    check computeProcHash(sourcePath, "missing") == "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

  test "shouldSkipTheaterAudit skips matching false-positive content hash":
    let dir = tempDir("axiom_theater_skip_skip")
    defer: removeDir(dir)
    let sourcePath = dir / "sample.nim"
    let registryPath = dir / "debt_registry.json"
    writeFile(sourcePath, """
proc alpha(x: int): int =
  result = x + 1
""")

    let contentHash = computeProcHash(sourcePath, "alpha")
    writeFile(registryPath, &"""
{{
  "version": 3,
  "entries": [
    {{
      "id": "DEBT#900",
      "category": "Theater/Vacuous Proof",
      "description": "false positive",
      "file": "src/foo.nim",
      "symbol": "alpha",
      "resolution": "FALSE_POSITIVE",
      "contentHash": "{contentHash}"
    }}
  ]
}}
""")

    check shouldSkipTheaterAudit("src/foo.nim", "alpha", contentHash, registryPath)

  test "shouldSkipTheaterAudit requires matching content hash":
    let dir = tempDir("axiom_theater_skip_mismatch")
    defer: removeDir(dir)
    let registryPath = dir / "debt_registry.json"
    writeFile(registryPath, """
{
  "version": 3,
  "entries": [
    {
      "id": "DEBT#901",
      "category": "Theater/Vacuous Proof",
      "description": "false positive",
      "file": "src/foo.nim",
      "symbol": "alpha",
      "resolution": "FALSE_POSITIVE",
      "contentHash": "sha256:wrong"
    }
  ]
}
""")

    check not shouldSkipTheaterAudit("src/foo.nim", "alpha", "sha256:right", registryPath)

  test "shouldSkipTheaterAudit misses absent entries":
    let dir = tempDir("axiom_theater_skip_absent")
    defer: removeDir(dir)
    let registryPath = dir / "debt_registry.json"
    writeFile(registryPath, """
{
  "version": 3,
  "entries": [
    {
      "id": "DEBT#902",
      "category": "Theater/Vacuous Proof",
      "description": "different symbol",
      "file": "src/foo.nim",
      "symbol": "beta",
      "resolution": "FALSE_POSITIVE",
      "contentHash": "sha256:match"
    }
  ]
}
""")

    check not shouldSkipTheaterAudit("src/foo.nim", "alpha", "sha256:match", registryPath)
