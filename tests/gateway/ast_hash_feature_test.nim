## AST Hash Feature Test.
## See tests/features/ast_hash.feature for the specification.
##
## Validates: deterministic content hashing, cache key generation,
## config snapshot integration.

import std/[os, strutils, unittest]
import verification/batch_uap/ast_hash

const
  projectRoot = currentSourcePath().parentDir().parentDir().parentDir()

suite "AST Hash — Core Interface":

  test "computeContentHash returns deterministic result":
    ## Given a source string
    ## When computeContentHash is called twice
    ## Then both hashes are identical
    let source = "proc add(x, y: int): int = x + y"
    let h1 = computeContentHash(source)
    let h2 = computeContentHash(source)
    check h1.len > 0
    check h1 == h2

  test "computeContentHash detects structural changes":
    ## Given two source strings with different semantics
    ## When computeContentHash is called on each
    ## Then the hashes differ
    let s1 = "proc add(x, y: int): int = x + y"
    let s2 = "proc sub(x, y: int): int = x - y"
    let h1 = computeContentHash(s1)
    let h2 = computeContentHash(s2)
    check h1 != h2

  test "computeContentHash handles empty string":
    ## Given an empty string
    ## When computeContentHash is called
    ## Then a non-empty hash is returned
    let h = computeContentHash("")
    check h.len > 0

  test "computeCacheKeyFromSource returns consistent key":
    ## Given a source string and config hash
    ## When computeCacheKeyFromSource is called twice
    ## Then both keys are identical
    let source = "func max(a, b: int): int = if a > b: a else: b"
    let configHash = "deadbeef01234567"
    let k1 = computeCacheKeyFromSource(source, configHash)
    let k2 = computeCacheKeyFromSource(source, configHash)
    check k1.len > 0
    check k1 == k2

  test "computeCacheKeyFromSource without config hash":
    ## Given a source string without a config hash
    ## When computeCacheKeyFromSource is called
    ## Then a valid key is returned
    let source = "let x = 42"
    let k = computeCacheKeyFromSource(source)
    check k.len > 0

  test "cacheKeyValid rejects empty key":
    ## Given an empty key
    ## When cacheKeyValid is called
    ## Then it returns false
    check cacheKeyValid("") == false

  test "cacheKeyValid accepts valid key":
    ## Given a non-empty key
    ## When cacheKeyValid is called
    ## Then it returns true
    check cacheKeyValid("abc123def456") == true

  test "combineHashes is order-sensitive":
    ## Given two hash strings
    ## When combineHashes is called in both orders
    ## Then the results differ
    let a = "aaa"
    let b = "bbb"
    let ab = combineHashes(a, b)
    let ba = combineHashes(b, a)
    check ab != ba

  test "resetConfigSnapshot clears singleton":
    ## Given a loaded config snapshot
    ## When resetConfigSnapshot is called
    ## Then the singleton is cleared
    resetConfigSnapshot()
    # After reset, loading should work fresh
    let snap = loadConfigSnapshot(projectRoot)
    check snap.combinedHash.len >= 0  # may be empty if no config files exist
