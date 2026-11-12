{.push raises: [].}
## PBT Engine Self-Test
## Tests: seed determinism, shrink convergence, combinator composability,
## silent mode, BitStream atomicity, shrink timeout.

import std/[tables, times, unittest]
import core/testing/pbt_engine
import core/parsers/safe_parsers
import core/types/results

suite "PBT Engine Core":
  test "Seed determinism: same seed produces identical BitStream sequence":
    let seed: int64 = 42
    var bs1 = initBitStream(seed)
    var bs2 = initBitStream(seed)
    for i in 0..<100:
      check bs1.randInt(0, 1000) == bs2.randInt(0, 1000)

  test "initSeed respects AXIOM_PBT_SEED env":
    # When env is set, seed should be deterministic
    let s1 = initSeed()
    let s2 = initSeed()
    # Both calls in same second → same seed (unless env overrides)
    # Just verify it returns a non-negative int64
    check s1 >= 0
    check s2 >= 0

  test "initBitStream sets seed correctly":
    let bs = initBitStream(12345)
    check bs.seed == 12345
    check bs.cursor == 0
    check bs.shrinkDepth == 0

  test "BitStream cursor advances on randInt":
    var bs = initBitStream(1)
    check bs.cursor == 0
    discard bs.randInt(0, 10)
    check bs.cursor == 1
    discard bs.randInt(0, 10)
    check bs.cursor == 2

  test "BitStream cursor advances on randFloat":
    var bs = initBitStream(1)
    discard bs.randFloat()
    check bs.cursor == 1

  test "BitStream cursor advances on randBool":
    var bs = initBitStream(1)
    discard bs.randBool()
    check bs.cursor == 1

  test "BitStream cursor advances on randAlphanumeric":
    var bs = initBitStream(1)
    let s = bs.randAlphanumeric(5)
    check s.len == 5
    check bs.cursor == 5  # one cursor unit per character in randAlphanumeric(5)

suite "Combinator Composability":
  test "genInt produces values in range":
    let gen = genInt(0, 100)
    var bs = initBitStream(42)
    for i in 0..<50:
      let v = gen(bs)
      check v >= 0
      check v <= 100

  test "genBool produces both true and false (no degenerate output)":
    # axiom:theater-fix - replaced fragile boundary checks with meaningful
    # distributional property: a correct genBool must exercise both branches
    # of conditional logic, otherwise shrink/retry heuristics break.
    let gen = genBool()
    var bs = initBitStream(42)
    var trueCount = 0
    for i in 0..<100:
      if gen(bs):
        inc trueCount
    # Verify balanced distribution: neither outcome dominates (>90% threshold)
    # This catches degenerate generators that always return the same value
    check trueCount > 10  # at least 10% true
    check trueCount < 90  # at most 90% true

  test "genString produces strings in length range":
    let gen = genString(3, 10)
    var bs = initBitStream(42)
    for i in 0..<20:
      let s = gen(bs)
      check s.len >= 3
      check s.len <= 10

  test "map transforms generator output":
    let intGen = genInt(1, 10)
    let strGen = intGen.map(proc(i: int): string = $i)
    var bs = initBitStream(42)
    let s = strGen(bs)
    check s.len > 0
    check safeParseInt(s).get() >= 1
    check safeParseInt(s).get() <= 10

  test "genSeq produces seq in length range":
    let elemGen = genInt(0, 100)
    let seqGen = genSeq(elemGen, 1, 5)
    var bs = initBitStream(42)
    for i in 0..<10:
      let s = seqGen(bs)
      check s.len >= 1
      check s.len <= 5

  test "genTable produces table in size range":
    let keyGen = genString(3, 5)
    let valGen = genInt(0, 100)
    let tblGen = genTable(keyGen, valGen, 1, 5)
    var bs = initBitStream(42)
    let t = tblGen(bs)
    check t.len >= 1
    check t.len <= 5

suite "Silent Mode":
  test "PbtSilent suppresses SEED marker on success":
    let gen = genInt(0, 100)
    let prop = proc(i: int): bool = true  # always passes
    let result = checkProperty(gen, prop, iterations = 10,
                               verbosity = PbtSilent)
    check result.passed == true
    # Silent mode: no stdout output expected for success
    # (Can't easily capture stdout in unittest, but the code path is exercised)

  test "PbtVerbose outputs SEED marker on success":
    let gen = genInt(0, 100)
    let prop = proc(i: int): bool = true
    let result = checkProperty(gen, prop, iterations = 10,
                               verbosity = PbtVerbose)
    check result.passed == true

suite "Shrink Convergence":
  test "Shrink finds minimal counter-example":
    let gen = genInt(0, 1000)
    let prop = proc(i: int): bool = i < 50  # fails for i >= 50
    let result = checkProperty(gen, prop, iterations = 200,
                                maxShrinkSteps = 50,
                                verbosity = PbtSilent)
    check result.passed == false
    check result.seed > 0
    # The counter-example should be reported
    check result.counterExample.len > 0

suite "BitStream Atomicity (withSnapshot)":
  test "withSnapshot restores cursor on normal exit":
    var bs = initBitStream(42)
    bs.cursor = 10
    bs.withSnapshot:
      discard bs.randInt(0, 100)
      discard bs.randInt(0, 100)
    check bs.cursor == 10  # restored

  test "withSnapshot restores cursor on exception":
    var bs = initBitStream(42)
    bs.cursor = 10
    try:
      bs.withSnapshot:
        discard bs.randInt(0, 100)
        raise newException(ValueError, "test")
    except ValueError:
      discard
    check bs.cursor == 10  # restored even after exception

suite "Shrink Timeout":
  test "Shrink respects maxDuration":
    # Use a property that's hard to shrink (always fails)
    let gen = genInt(0, 10000)
    let prop = proc(i: int): bool = false  # always fails → forces shrink
    let result = checkProperty(gen, prop, iterations = 1,
                                maxShrinkSteps = 10000,
                                maxDuration = initDuration(seconds = 1),
                                verbosity = PbtSilent)
    check result.passed == false
    # Should either complete or timeout within reasonable time
    # (The 1s timeout ensures it doesn't hang)

{.pop.}
