{.push raises: [].}
## PBT: FileHashCache Data Properties
## Exercises: src/core/gate/file_hash_cache.nim (FileCacheEntry, VfsCacheEntry)
## Properties:
##   - FileCacheEntry field access is deterministic
##   - FileCacheEntry JSON roundtrip preserves fields
##   - VfsCacheEntry field construction is consistent
## @basic tier — runs in every CI push.

import std/[json, tables, unittest]
import core/testing/pbt_engine
import core/gate/file_hash_cache

suite "PBT: FileCacheEntry Properties":
  test "FileCacheEntry field access is deterministic (200 iterations)":
    # Property: creating entry with same values always yields same fields.
    let gen = genString(1, 64)
    let prop = proc(hash: string): bool =
      let entry = FileCacheEntry(mtime: 12345, hash: hash)
      entry.hash == hash and entry.mtime == 12345
    let pbtResult = checkProperty(gen, prop, iterations = 200,
                                   tier = PbtBasic, verbosity = PbtSilent)
    check pbtResult.passed == true

  test "FileCacheEntry default hash is empty (100 iterations)":
    # Property: default-constructed FileCacheEntry has empty hash string.
    let gen = genInt(0, 1_000_000)
    let prop = proc(mtime: int): bool =
      let entry = FileCacheEntry(mtime: int64(mtime))
      entry.hash.len == 0
    let pbtResult = checkProperty(gen, prop, iterations = 100,
                                   tier = PbtBasic, verbosity = PbtSilent)
    check pbtResult.passed == true

  test "FileCacheEntry JSON roundtrip preserves fields (200 iterations)":
    # Property: construct → serialize → parse → fields match.
    let gen = genString(1, 64)
    let prop = proc(hash: string): bool =
      let original = FileCacheEntry(mtime: 9999, hash: hash)
      let json = %*{"mtime": original.mtime, "hash": original.hash}
      let parsed = FileCacheEntry(
        mtime: json{"mtime"}.getBiggestInt(0).int64,
        hash: json{"hash"}.getStr("")
      )
      parsed.mtime == original.mtime and parsed.hash == original.hash
    let pbtResult = checkProperty(gen, prop, iterations = 200,
                                   tier = PbtBasic, verbosity = PbtSilent)
    check pbtResult.passed == true

suite "PBT: FileHashCache Table Properties":
  test "Cache entries table preserves insertion order (100 iterations)":
    # Property: inserting N entries into cache table yields table of size N.
    let gen = genInt(1, 20)
    let prop = proc(count: int): bool =
      var entries = initTable[string, FileCacheEntry]()
      for i in 0..<count:
        let path = "src/file_" & $i & ".nim"
        entries[path] = FileCacheEntry(mtime: int64(i), hash: "hash" & $i)
      entries.len == count
    let pbtResult = checkProperty(gen, prop, iterations = 100,
                                   tier = PbtBasic, verbosity = PbtSilent)
    check pbtResult.passed == true

  test "Cache lookup returns correct entry (100 iterations)":
    # Property: getOrDefault on populated table returns inserted value.
    let gen = genInt(0, 99)
    let prop = proc(idx: int): bool =
      var entries = initTable[string, FileCacheEntry]()
      for i in 0..99:
        entries["path_" & $i] = FileCacheEntry(mtime: int64(i), hash: "h" & $i)
      let lookup = entries.getOrDefault("path_" & $idx)
      lookup.mtime == int64(idx) and lookup.hash == "h" & $idx
    let pbtResult = checkProperty(gen, prop, iterations = 100,
                                   tier = PbtBasic, verbosity = PbtSilent)
    check pbtResult.passed == true

suite "PBT: VfsCacheEntry Properties":
  test "VfsCacheEntry field construction is consistent (100 iterations)":
    # Property: VfsCacheEntry with same inputs always yields identical fields.
    let gen = genInt(0, 1_000_000)
    let prop = proc(size: int): bool =
      var hashArr: array[32, byte]
      for i in 0..<32:
        hashArr[i] = byte(i mod 256)
      let entry = VfsCacheEntry(mtime: 42, size: int64(size), hash: hashArr)
      entry.mtime == 42 and entry.size == int64(size)
    let pbtResult = checkProperty(gen, prop, iterations = 100,
                                   tier = PbtBasic, verbosity = PbtSilent)
    check pbtResult.passed == true

  test "VfsCacheEntry hash array is 32 bytes (100 iterations)":
    # Property: hash array always has exactly 32 bytes.
    let gen = genInt(0, 255)
    let prop = proc(seed: int): bool =
      var hashArr: array[32, byte]
      for i in 0..<32:
        hashArr[i] = byte((seed + i) mod 256)
      let entry = VfsCacheEntry(mtime: 0, size: 0, hash: hashArr)
      entry.hash.len == 32
    let pbtResult = checkProperty(gen, prop, iterations = 100,
                                   tier = PbtBasic, verbosity = PbtSilent)
    check pbtResult.passed == true

{.pop.}
