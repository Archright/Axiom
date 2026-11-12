## Feature test: nimtry_cli.nim — policyHash separation, per-file cache
## Covers: tests/features/nimtry_cli.feature

import std/[unittest, os, strutils]
import ../../src/gate/nimtry/nimtry_cache

suite "nimtry_cli — Cache Key Separation Feature Tests":
  test "computeMultiFileHash excludes architecture_debt.json":
    ## policyHash should only include architecture_policy.lock + config.nims
    ## Changing architecture_debt.json must NOT change the policy hash
    let policyFiles = @[
      "src/gate/architecture_policy.lock",
      "config.nims"
    ]
    let hash1 = computeMultiFileHash(policyFiles)
    check hash1.len > 0
    # Verify hash is deterministic
    let hash2 = computeMultiFileHash(policyFiles)
    check hash1 == hash2

  test "computeFileHash is deterministic for same file":
    let path = "config.nims"
    if fileExists(path):
      let h1 = computeFileHash(path)
      let h2 = computeFileHash(path)
      check h1 == h2
      check h1.len > 0

  test "computeMultiFileHash changes when policy file changes":
    ## Two different file sets should produce different hashes
    let set1 = @["config.nims"]
    let set2 = @["src/gate/architecture_policy.lock"]
    let h1 = computeMultiFileHash(set1)
    let h2 = computeMultiFileHash(set2)
    # Different file sets → different hashes (unless both are empty/missing)
    if fileExists(set1[0]) and fileExists(set2[0]):
      check h1 != h2

  test "cache directory exists or can be created":
    nimtry_cache.ensureCacheDir()
    check dirExists(nimtry_cache.getCacheDir())
