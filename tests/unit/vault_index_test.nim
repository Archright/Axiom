## Vault Index Unit Test
## Verifies Virtual DB operations: key generation, save/load roundtrip,
## certificate sync, and symbolic garbage collection.

import std/[unittest, os, json, tables, sets, times]
import ../../src/verification/vault_index

suite "makeVaultKey contract":
  test "produces deterministic module::function key":
    check makeVaultKey("core/axiom_api", "buildKInductionFinalStateNode") ==
          "core/axiom_api::buildKInductionFinalStateNode"

  test "empty module or function still produces separator":
    check makeVaultKey("", "foo") == "::foo"
    check makeVaultKey("bar", "") == "bar::"

suite "save/load roundtrip":
  test "persist and restore empty index":
    let path = getTempDir() / "axiom_vault_test_empty.idx"
    let original = VaultIndex(
      version: 1, lastVerifiedAt: 0,
      entries: initTable[string, VaultIndexEntry](),
      byFileName: initTable[string, string]()
    )
    saveVirtualVaultIndex(path, original)
    let restored = loadVirtualVaultIndex(path)
    check restored.version == 1
    check restored.lastVerifiedAt == 0
    check restored.entries.len == 0
    check restored.byFileName.len == 0
    if fileExists(path): removeFile(path)

  test "persist and restore populated index":
    let path = getTempDir() / "axiom_vault_test_populated.idx"
    var original = VaultIndex(
      version: 1, lastVerifiedAt: 1234567890,
      entries: initTable[string, VaultIndexEntry](),
      byFileName: initTable[string, string]()
    )
    let entry = VaultIndexEntry(
      fileName: "core_axiom_api__buildKInductionFinalStateNode.json",
      modulePath: "core/axiom_api",
      functionName: "buildKInductionFinalStateNode",
      fingerprint: "abc123",
      status: "verified",
      trusted: true,
      sourceMtime: 9876543210,
      certMtime: 1234567890
    )
    let key = makeVaultKey(entry.modulePath, entry.functionName)
    original.entries[key] = entry
    original.byFileName[entry.fileName] = key
    saveVirtualVaultIndex(path, original)
    let restored = loadVirtualVaultIndex(path)
    check restored.entries.len == 1
    check restored.byFileName.len == 1
    check restored.entries.hasKey(key)
    let r = restored.entries[key]
    check r.fileName == entry.fileName
    check r.modulePath == entry.modulePath
    check r.functionName == entry.functionName
    check r.fingerprint == entry.fingerprint
    check r.status == entry.status
    check r.trusted == entry.trusted
    check r.sourceMtime == entry.sourceMtime
    check r.certMtime == entry.certMtime
    if fileExists(path): removeFile(path)

suite "syncVaultIndexWithCertificates":
  test "adds new certificate files to index":
    let certDir = getTempDir() / "axiom_vault_test_certs"
    createDir(certDir)
    let certPath = certDir / "core_test__foo.json"
    let certNode = %*{
      "modulePath": "core/test",
      "functionName": "foo",
      "fingerprint": "fp1",
      "status": "verified"
    }
    writeFile(certPath, $certNode)
    var idx = VaultIndex(
      version: 1, lastVerifiedAt: 0,
      entries: initTable[string, VaultIndexEntry](),
      byFileName: initTable[string, string]()
    )
    syncVaultIndexWithCertificates(idx, certDir)
    check idx.entries.len == 1
    check idx.byFileName.len == 1
    let key = makeVaultKey("core/test", "foo")
    check idx.entries.hasKey(key)
    check idx.entries[key].fingerprint == "fp1"
    removeDir(certDir)

  test "skips unchanged files via mtime fast-path":
    let certDir = getTempDir() / "axiom_vault_test_certs2"
    createDir(certDir)
    let certPath = certDir / "existing.json"
    let certNode = %*{
      "modulePath": "core/test",
      "functionName": "existing",
      "fingerprint": "fp_old",
      "status": "verified"
    }
    writeFile(certPath, $certNode)
    let certMtime = getLastModificationTime(certPath).toUnix()
    var idx = VaultIndex(
      version: 1, lastVerifiedAt: 0,
      entries: initTable[string, VaultIndexEntry](),
      byFileName: initTable[string, string]()
    )
    let key = makeVaultKey("core/test", "existing")
    idx.entries[key] = VaultIndexEntry(
      fileName: "existing.json", modulePath: "core/test",
      functionName: "existing", fingerprint: "fp_old",
      status: "verified", trusted: true,
      sourceMtime: 0, certMtime: certMtime
    )
    idx.byFileName["existing.json"] = key
    syncVaultIndexWithCertificates(idx, certDir)
    check idx.entries.len == 1
    check idx.entries[key].fingerprint == "fp_old"
    removeDir(certDir)

suite "runSymbolicGc":
  test "returns keys not in currentSymbols without modifying idx":
    var idx = VaultIndex(
      version: 1, lastVerifiedAt: 0,
      entries: initTable[string, VaultIndexEntry](),
      byFileName: initTable[string, string]()
    )
    idx.entries["mod::keep"] = VaultIndexEntry(
      fileName: "keep.json", modulePath: "mod",
      functionName: "keep", fingerprint: "",
      status: "", trusted: true,
      sourceMtime: 0, certMtime: 0
    )
    idx.byFileName["keep.json"] = "mod::keep"
    idx.entries["mod::remove"] = VaultIndexEntry(
      fileName: "remove.json", modulePath: "mod",
      functionName: "remove", fingerprint: "",
      status: "", trusted: true,
      sourceMtime: 0, certMtime: 0
    )
    idx.byFileName["remove.json"] = "mod::remove"
    var currentSymbols = toHashSet(["mod::keep"])
    let removed = runSymbolicGc(idx, currentSymbols)
    check removed == @["mod::remove"]
    check idx.entries.len == 2
    check idx.byFileName.len == 2

  test "returns empty when all symbols are current":
    var idx = VaultIndex(
      version: 1, lastVerifiedAt: 0,
      entries: initTable[string, VaultIndexEntry](),
      byFileName: initTable[string, string]()
    )
    idx.entries["a::b"] = VaultIndexEntry(
      fileName: "ab.json", modulePath: "a",
      functionName: "b", fingerprint: "",
      status: "", trusted: true,
      sourceMtime: 0, certMtime: 0
    )
    idx.byFileName["ab.json"] = "a::b"
    var currentSymbols = toHashSet(["a::b"])
    let removed = runSymbolicGc(idx, currentSymbols)
    check removed.len == 0
