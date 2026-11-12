import std/unittest
import ../../tools/local_purity_check

## Slot-identity determinism for the purity-check worktree (the DEBT#481 defect
## family: two concurrent invocations contending over one mutable git
## worktree).
##
## The slot path is DERIVED from computeStamp, so the whole contention argument
## rests on a single pure property:
##   same inputs      -> same stamp      (stable slot; warm nimcache stays valid)
##   different inputs -> different stamp (peers never contend for one path)
##
## Both directions are checked directly against the exported function. The
## flock and the filesystem lifecycle are deliberately out of scope: they are
## I/O, not determinism, and would be flaky in a unit test.

const NimVersionLine = "Nim Compiler Version 2.2.10 [Linux: amd64]"
const CacheVersion = "warm-nimcache-v2"

suite "local_purity_check — slot stamp determinism":

  test "identical inputs yield an identical stamp":
    let contents = @["nimble.lock body", "config.nims body", "Makefile body"]
    let first = computeStamp(contents, NimVersionLine, CacheVersion)
    let second = computeStamp(contents, NimVersionLine, CacheVersion)
    check first == second
    # A differently assembled but equal seq must agree too — the stamp is a
    # function of the CONTENT, never of how the seq was built.
    var rebuilt: seq[string] = @[]
    for c in contents:
      rebuilt.add c
    check computeStamp(rebuilt, NimVersionLine, CacheVersion) == first
    # SHA-256 hex digest.
    check first.len == 64

  test "a single changed input yields a different stamp":
    let contents = @["alpha", "beta", "gamma"]
    let base = computeStamp(contents, NimVersionLine, CacheVersion)
    # Every element perturbed on its own must move the stamp.
    for i in 0 ..< contents.len:
      var mutated = contents
      mutated[i] = mutated[i] & "!"
      check computeStamp(mutated, NimVersionLine, CacheVersion) != base
    # The two non-file inputs are stamp inputs as well.
    check computeStamp(contents, "Nim Compiler Version 2.2.9", CacheVersion) != base
    check computeStamp(contents, NimVersionLine, "warm-nimcache-v3") != base
    # Length-delimited framing: one element may not alias a different split of
    # the same characters. Without the per-element length prefix these two
    # inputs would concatenate identically and contend for one slot.
    check computeStamp(@["ab"], NimVersionLine, CacheVersion) !=
          computeStamp(@["a", "b"], NimVersionLine, CacheVersion)
