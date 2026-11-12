## State Ledger Feature Test.
## Verifies the cross-process pipeline state ledger with CRC32 integrity.
##
## Tests:
##   - CRC32 correctness against known test vectors
##   - getLedgerPath returns canonical path
##   - computeBuildEnvHash is deterministic
##   - CRC32 openArray overload for empty input

import std/[unittest, os]
import core/gate/state_ledger
import core/gate/state_ledger_types
import core/gate/hash_types

suite "State Ledger — CRC32 Integrity":

  test "CRC32 of '123456789' matches standard test vector":
    ## Given the standard CRC32 test input "123456789"
    ## When crc32 is computed
    ## Then the result matches 0xCBF43926 (IEEE 802.3)
    let input = "123456789"
    let crc = crc32(cast[ptr UncheckedArray[byte]](unsafeAddr input[0]), input.len)
    check crc == 0xCBF43926'u32

  test "CRC32 of empty openArray returns 0":
    ## Given an empty byte array
    ## When crc32 openArray overload is called
    ## Then the result is 0 (defined behavior for zero-length input)
    var empty: seq[byte]
    let crc = crc32(empty)
    check crc == 0'u32

  test "CRC32 is deterministic across calls":
    ## Given the same input data
    ## When crc32 is called twice
    ## Then both calls produce identical results
    let data = "deterministic test data for CRC32"
    let crc1 = crc32(cast[ptr UncheckedArray[byte]](unsafeAddr data[0]), data.len)
    let crc2 = crc32(cast[ptr UncheckedArray[byte]](unsafeAddr data[0]), data.len)
    check crc1 == crc2

  test "CRC32 changes with single byte modification":
    ## Given two inputs differing by one byte
    ## When crc32 is computed for each
    ## Then the results are different (avalanche property)
    let data1 = "AAAAAAAAAA"
    let data2 = "AAAAAAAAAB"
    let crc1 = crc32(cast[ptr UncheckedArray[byte]](unsafeAddr data1[0]), data1.len)
    let crc2 = crc32(cast[ptr UncheckedArray[byte]](unsafeAddr data2[0]), data2.len)
    check crc1 != crc2

suite "State Ledger — Path & Hash Helpers":

  test "getLedgerPath returns canonical path":
    ## Given a repo root path
    ## When getLedgerPath is called
    ## Then the result ends with the expected ledger filename
    let path = getLedgerPath("/tmp/test-repo")
    check path == "/tmp/test-repo/.axiom/cache/pipeline_state.ledger"

  test "getLedgerPath with different roots produces different paths":
    ## Given two different repo roots
    ## When getLedgerPath is called for each
    ## Then the results are different
    let path1 = getLedgerPath("/repo1")
    let path2 = getLedgerPath("/repo2")
    check path1 != path2

  test "computeBuildEnvHash is deterministic":
    ## Given no environment changes between calls
    ## When computeBuildEnvHash is called twice
    ## Then both calls produce the same HashValue
    let h1 = computeBuildEnvHash()
    let h2 = computeBuildEnvHash()
    check h1 == h2

  test "ledgerFileExists returns false for nonexistent repo root":
    ## Given a repo root where no ledger file exists
    ## When ledgerFileExists is called
    ## Then it returns false
    check not ledgerFileExists("/tmp/test-repo-nonexistent-xyz")
    check not ledgerFileExists("")
