## Property-Based Testing for engine API invariants.
##
## Exercises countSymbols and bindingCheck with random/iterated inputs
## to verify crash-free behavior and basic invariants.
##
## Note: The tested functions (countSymbols, bindingCheck, Hint) reside in
## src/engine/engine.nim, forwarded via src/engine.nim. The user-requested
## path src/core/api/api.nim does not contain these symbols.

import std/unittest
import std/random
import engine

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

proc randomAlphaString(rng: var Rand; length: int): string =
  ## Generate a random alphabetic string of given length.
  const alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
  result = newString(length)
  for i in 0 ..< length:
    result[i] = alphabet[rng.rand(alphabet.len - 1)]

proc randomWhitespaceString(rng: var Rand; length: int): string =
  ## Generate a random string mixing words and whitespace.
  const words = ["forall", "x", "y", "Nat", "Int", "+", "-", "*", "=",
                 "=>", "<=", ">=", "implies", "and", "or"]
  result = ""
  for i in 0 ..< length:
    if rng.rand(2) == 0:
      result.add(' ')
    else:
      result.add(words[rng.rand(words.len - 1)])
      result.add(' ')

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

suite "PBT: countSymbols invariants":

  test "countSymbols is always >= 0 for any input string":
    var rng = initRand(42)
    for i in 0 .. 100:
      let s = randomAlphaString(rng, rng.rand(0 .. 200))
      check countSymbols(s) >= 0

  test "countSymbols(empty) == 0":
    check countSymbols("") == 0

  test "countSymbols is deterministic (same input -> same output)":
    var rng = initRand(99)
    for i in 0 .. 100:
      let s = randomWhitespaceString(rng, rng.rand(0 .. 100))
      let first = countSymbols(s)
      let second = countSymbols(s)
      check first == second

  test "countSymbols(whitespace-only) == 0":
    check countSymbols("   ") == 0
    check countSymbols("\t\n  ") == 0

  test "countSymbols with keywords filtered":
    # "assert" and "and" are filtered out; "x" is a valid symbol
    let result = countSymbols("assert and x")
    check result == 1

  test "countSymbols stress: varied random inputs do not crash":
    var rng = initRand(7)
    for i in 0 .. 100:
      let len = rng.rand(0 .. 500)
      let s = randomAlphaString(rng, len)
      discard countSymbols(s)  # must not crash

suite "PBT: bindingCheck invariants":

  test "bindingCheck returns false when any variable is missing":
    let source = "let x = 1\nlet y = 2\n"
    check bindingCheck(source, @["x", "z"]) == false
    check bindingCheck(source, @["missing"]) == false
    check bindingCheck(source, @[""]) == true  # empty string is contained in any string

  test "bindingCheck returns true when all variables are present":
    let source = "let alpha = 1\nlet beta = 2\nlet gamma = 3\n"
    check bindingCheck(source, @["alpha", "beta", "gamma"]) == true
    check bindingCheck(source, @["alpha"]) == true
    check bindingCheck(source, @["let"]) == true

  test "bindingCheck with empty variable list always returns true":
    var rng = initRand(123)
    for i in 0 .. 100:
      let s = randomAlphaString(rng, rng.rand(0 .. 200))
      check bindingCheck(s, @[]) == true

  test "bindingCheck is deterministic":
    var rng = initRand(314)
    for i in 0 .. 100:
      let source = randomAlphaString(rng, rng.rand(10 .. 100))
      let varName = randomAlphaString(rng, rng.rand(1 .. 10))
      let first = bindingCheck(source, @[varName])
      let second = bindingCheck(source, @[varName])
      check first == second

  test "bindingCheck stress: varied random inputs do not crash":
    var rng = initRand(271)
    for i in 0 .. 100:
      let source = randomAlphaString(rng, rng.rand(0 .. 300))
      var vars: seq[string] = @[]
      let numVars = rng.rand(0 .. 5)
      for j in 0 .. numVars:
        vars.add(randomAlphaString(rng, rng.rand(0 .. 20)))
      discard bindingCheck(source, vars)  # must not crash

suite "PBT: Hint type construction (no I/O)":

  test "Hint object can be constructed with arbitrary strings":
    var rng = initRand(101)
    for i in 0 .. 100:
      let h = Hint(
        lean_proposition: randomAlphaString(rng, rng.rand(0 .. 100)),
        smt_constraint: randomAlphaString(rng, rng.rand(0 .. 100)),
        source_lines: randomAlphaString(rng, rng.rand(0 .. 100)),
        variables: @[randomAlphaString(rng, rng.rand(0 .. 20))]
      )
      # Fields must be accessible without crash
      check h.lean_proposition.len >= 0
      check h.smt_constraint.len >= 0
      check h.source_lines.len >= 0
      check h.variables.len >= 0
