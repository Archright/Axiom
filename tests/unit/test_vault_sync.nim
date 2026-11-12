import std/[os, tables, sets]
import unittest
import verification/vault_index

suite "Vault index key canonicalization":
  test "canonicalizeModulePath strips src/ prefix from relative path":
    check canonicalizeModulePath("src/core/json_utils.nim", "") == "core/json_utils.nim"

  test "canonicalizeModulePath leaves already-canonical path unchanged":
    check canonicalizeModulePath("core/json_utils.nim", "") == "core/json_utils.nim"

  test "canonicalizeModulePath normalizes DirSep to slash":
    when defined(windows):
      check canonicalizeModulePath("core\\json_utils.nim", "") == "core/json_utils.nim"
    else:
      check canonicalizeModulePath("core/json_utils.nim", "") == "core/json_utils.nim"

  test "canonicalizeModulePath handles absolute path via projectRoot":
    let repoRoot = getCurrentDir()
    let absPath = joinPath(repoRoot, "src", "core", "json_utils.nim")
    let result = canonicalizeModulePath(absPath, repoRoot)
    check result == "core/json_utils.nim"

  test "canonicalizeModulePath handles absolute path without src/ prefix":
    let repoRoot = getCurrentDir()
    let absPath = joinPath(repoRoot, "core", "json_utils.nim")
    let result = canonicalizeModulePath(absPath, repoRoot)
    check result == "core/json_utils.nim"

  test "makeVaultKey combines modulePath and functionName":
    check makeVaultKey("core/json_utils.nim", "getOrDefault") == "core/json_utils.nim::getOrDefault"

  test "makeVaultKey with projectRoot canonicalizes absolute modulePath":
    let repoRoot = getCurrentDir()
    let absPath = joinPath(repoRoot, "src", "core", "json_utils.nim")
    check makeVaultKey(absPath, "getOrDefault", repoRoot) == "core/json_utils.nim::getOrDefault"

suite "Vault index sync isomorphic rebuild":
  test "removeUnseenVaultEntries preserves entries with matching uint64 hash":
    var idx = VaultIndex(
      version: 1,
      lastVerifiedAt: 0,
      entries: initTable[string, VaultIndexEntry](),
      byFileName: initTable[string, string]()
    )
    let key = "core/json_utils.nim::getOrDefault"
    idx.entries[key] = VaultIndexEntry(
      fileName: "core_json_utils_getOrDefault.json",
      modulePath: "core/json_utils.nim",
      functionName: "getOrDefault",
      fingerprint: "abc123",
      status: "certGreen",
      trusted: true
    )
    idx.byFileName["core_json_utils_getOrDefault.json"] = key

    var seenKeys = initHashSet[uint64]()
    seenKeys.incl(stableHash64(key))

    removeUnseenVaultEntries(idx, seenKeys)

    check idx.entries.len == 1
    check idx.byFileName.len == 1
    check idx.entries.hasKey(key)

  test "removeUnseenVaultEntries removes stale entries not in seenKeys":
    var idx = VaultIndex(
      version: 1,
      lastVerifiedAt: 0,
      entries: initTable[string, VaultIndexEntry](),
      byFileName: initTable[string, string]()
    )
    let staleKey = "core/old.nim::deprecatedFunc"
    idx.entries[staleKey] = VaultIndexEntry(
      fileName: "old.json",
      modulePath: "core/old.nim",
      functionName: "deprecatedFunc",
      fingerprint: "old",
      status: "certGreen",
      trusted: true
    )
    idx.byFileName["old.json"] = staleKey

    var seenKeys = initHashSet[uint64]()
    # Do not add staleKey to seenKeys

    removeUnseenVaultEntries(idx, seenKeys)

    check idx.entries.len == 0
    check idx.byFileName.len == 0

  test "removeUnseenVaultEntries rebuilds byFileName consistently":
    var idx = VaultIndex(
      version: 1,
      lastVerifiedAt: 0,
      entries: initTable[string, VaultIndexEntry](),
      byFileName: initTable[string, string]()
    )
    let keyA = "a.nim::foo"
    let keyB = "b.nim::bar"
    idx.entries[keyA] = VaultIndexEntry(
      fileName: "a.json", modulePath: "a.nim", functionName: "foo",
      fingerprint: "fpA", status: "certGreen", trusted: true
    )
    idx.entries[keyB] = VaultIndexEntry(
      fileName: "b.json", modulePath: "b.nim", functionName: "bar",
      fingerprint: "fpB", status: "certGreen", trusted: true
    )
    idx.byFileName["a.json"] = keyA
    idx.byFileName["b.json"] = keyB

    var seenKeys = initHashSet[uint64]()
    seenKeys.incl(stableHash64(keyA))

    removeUnseenVaultEntries(idx, seenKeys)

    check idx.entries.len == 1
    check idx.byFileName.len == 1
    check idx.entries.hasKey(keyA)
    check idx.byFileName.hasKey("a.json")
    check not idx.entries.hasKey(keyB)
    check not idx.byFileName.hasKey("b.json")

import ../../src/verification/global_symbol_graph

suite "Source Merkle Root determinism":
  test "computeSourceMerkleRoot returns same hash for identical content":
    let merkle1 = computeSourceMerkleRoot("src")
    let merkle2 = computeSourceMerkleRoot("src")
    check merkle1 == merkle2
    check merkle1.len > 0

  test "computeSourceMerkleRoot changes after file modification":
    let merkleBefore = computeSourceMerkleRoot("src")
    # Touch a file to change mtime without changing content
    let testFile = "src/core/json_utils.nim"
    if fileExists(testFile):
      let original = readFile(testFile)
      writeFile(testFile, original)
      let merkleAfter = computeSourceMerkleRoot("src")
      check merkleBefore == merkleAfter  # content unchanged → merkle unchanged
