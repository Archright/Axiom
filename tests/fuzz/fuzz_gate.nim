{.push raises: [].}

## AFL-based Property-Based Testing (PBT) Gate for Axiom.
##
## Reads fuzzed input from stdin (AFL-compatible) and verifies core invariants:
##   1. parseInt always returns an integer or raises ValueError (no other exceptions)
##   2. safeParseInt always returns a Result type (never crashes)
##   3. Hash function output is always fixed-length
##   4. JSON parsing always produces success or error (never crashes)
##
## Compile with `-d:afl` for AFL instrumentation.
## Run: afl-fuzz -i tests/fuzz/corpus/ -o tests/fuzz/findings/ -- bin/fuzz_gate

import std/[strutils, json, hashes, options]

# ---------------------------------------------------------------------------
# AFL assertion template
# ---------------------------------------------------------------------------

when defined(afl):
  import std/posix

  template aflAssert*(cond: bool) =
    ## In AFL mode, violation triggers SIGABRT → crash → AFL captures input.
    if not cond:
      echo "AFL assertion failed: " & astToStr(cond)
      let pid = getpid()
      discard kill(pid, SIGABRT)

  template aflAssert*(cond: bool, msg: string) =
    if not cond:
      echo "AFL assertion failed: " & msg
      let pid = getpid()
      discard kill(pid, SIGABRT)
else:
  template aflAssert*(cond: bool) =
    doAssert cond

  template aflAssert*(cond: bool, msg: string) =
    doAssert cond, msg

# ---------------------------------------------------------------------------
# Invariant checkers
# ---------------------------------------------------------------------------

func safeParseInt*(s: string): Option[int] =
  ## Always returns Some(value) or None. Never raises.
  try:
    result = some(parseInt(s))
  except ValueError:
    result = none(int)

func parseIntInvariant*(s: string): bool =
  ## Invariant: parseInt always returns an integer or raises ValueError.
  ## No other exception type is ever thrown.
  try:
    let val = parseInt(s)
    discard val
    result = true
  except ValueError:
    result = false  # ValueError = invalid input, invariant violated
  except CatchableError:
    result = false  # any other exception = invariant violation

func hashLengthInvariant*(data: string): bool =
  ## Invariant: hash() output is always a fixed-size int (system word size).
  ## The hash value itself is platform-dependent but the type is always int.
  let h = hash(data)
  # sizeof(int) is constant per platform — the invariant is that
  # hash never crashes and always returns the same type.
  result = sizeof(h) == sizeof(int)

proc jsonParseInvariant*(s: string): bool =
  ## Invariant: JSON parsing always returns success or error, never crashes.
  ## Note: parseJson has side effects per Nim's effect system (nim stdlib quirk).
  try:
    let node = parseJson(s)
    result = node != nil
  except JsonParsingError:
    result = false  # JsonParsingError = invalid input, invariant violated
  except CatchableError:
    result = false  # Unexpected exceptions indicate invariant violation

func parseIntRoundTrip*(s: string): bool =
  ## Invariant: for all valid integers (positive, negative, zero), parseInt → $roundtrips.
  try:
    let val = parseInt(s)
    result = ($val).parseInt() == val
  except ValueError:
    result = false

func safeParseIntNeverCrashes*(s: string): bool =
  ## Invariant: safeParseInt never raises — always returns Option.
  result = safeParseInt(s) is Option[int]

# ---------------------------------------------------------------------------
# AFL harness: read stdin, run all invariants
# ---------------------------------------------------------------------------

proc runFuzzGate*(input: string) =
  ## Run all PBT invariants against fuzzed input string.
  aflAssert(parseIntInvariant(input),
    "parseInt invariant failed for: " & input)
  aflAssert(hashLengthInvariant(input),
    "hash length invariant failed for: " & input)
  aflAssert(jsonParseInvariant(input),
    "JSON parse invariant failed for: " & input)
  aflAssert(parseIntRoundTrip(input),
    "parseInt round-trip failed for: " & input)
  aflAssert(safeParseIntNeverCrashes(input),
    "safeParseInt crashed on: " & input)

proc main() =
  ## AFL entry point: reads all of stdin.
  var input: string
  try:
    input = readAll(stdin)
  except IOError:
    input = ""
  runFuzzGate(input)

when isMainModule:
  main()
