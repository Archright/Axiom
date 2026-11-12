## Unit tests for PathManifest — PATH binary collection,
## deterministic hashing, and cache persistence.

import std/[unittest, os]
import core/gate/path_manifest

suite "PathManifest":
  test "collectPathManifest with explicit PATH finds /usr/bin executables":
    let pathEnv = "/usr/bin"
    let manifest = collectPathManifest(pathEnv)
    # /usr/bin typically has many executables
    check manifest.entries.len > 0
    # Every entry must have non-empty name, path, and hash
    for entry in manifest.entries:
      check entry.name.len > 0
      check entry.path.len > 0
      check entry.contentHash.len > 0

  test "manifest hash is deterministic across calls":
    let pathEnv = "/usr/bin"
    let m1 = collectPathManifest(pathEnv)
    let m2 = collectPathManifest(pathEnv)
    check m1.hash == m2.hash
    check m1.entries.len == m2.entries.len

  test "entries are sorted by name":
    let pathEnv = "/usr/bin"
    let manifest = collectPathManifest(pathEnv)
    for i in 1..<manifest.entries.len:
      check manifest.entries[i - 1].name <= manifest.entries[i].name

  test "nonexistent PATH dir produces empty manifest":
    let manifest = collectPathManifest("/nonexistent/path/xyz")
    check manifest.entries.len == 0
    # Hash of empty manifest is still a valid hash string
    check manifest.hash.len > 0

  test "cache and load round-trip":
    let pathEnv = "/usr/bin"
    let manifest = collectPathManifest(pathEnv)

    let tmpDir = getTempDir() / "axiom_pm_cache_" & $getCurrentProcessId()
    createDir(tmpDir)
    let cachePath = tmpDir / "manifest.hash"

    manifest.cachePathManifest(cachePath)
    let loaded = loadCachedPathManifest(cachePath)
    check loaded == manifest.hash

    removeDir(tmpDir)

  test "loadCachedPathManifest returns empty on cache miss":
    let loaded = loadCachedPathManifest("/nonexistent/cache/path.hash")
    check loaded == ""
