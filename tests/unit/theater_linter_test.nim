import std/unittest

import core/audit/theater_linter

let badSource = """
proc swallowedFailure(): void {.raises: [CatchableError].} =
  try:
    discard
  except CatchableError:
    discard

proc emptyExcept(): void {.raises: [CatchableError].} =
  try:
    discard
  except CatchableError:
    # intentionally empty for test coverage

proc alwaysTrueIf(): bool =
  if true:
    return true
  else:
    return false

proc alwaysTrueWhen(): bool =
  when true:
    return true
  else:
    return false

proc verifyAlways(): bool =
  return true

proc checkAlways(): bool =
  return true
"""

let goodSource = """
proc verifyGood(ok: bool): bool =
  if ok:
    return ok
  return false

proc checkGood(ok: bool): bool =
  when ok:
    return ok
  return false

proc notVerification(): bool =
  return true

proc emptyExcept(ok: bool): void {.raises: [CatchableError].} =
  try:
    discard
  except CatchableError:
    echo "handled"
"""

proc countPattern(pattern: TheaterPattern; findings: seq[TheaterFinding]): int =
  for finding in findings:
    if finding.pattern == pattern:
      inc result

suite "theater linter":
  test "detects swallowed CatchableError discard":
    let findings = scanTheaterSource(badSource, "fixture.nim")
    check countPattern(tpSwallowedFailure, findings) == 1
    check findings[0].line == 4
    check findings[0].symbol == "swallowedFailure"

  test "detects empty except blocks":
    let findings = scanTheaterSource(badSource, "fixture.nim")
    check countPattern(tpEmptyExceptBlock, findings) == 1
    check findings[1].line == 10

  test "detects always-true if and when branches":
    let findings = scanTheaterSource(badSource, "fixture.nim")
    check countPattern(tpAlwaysTrueCondition, findings) == 2

  test "detects hardcoded true returns in verify and check functions":
    let findings = scanTheaterSource(badSource, "fixture.nim")
    check countPattern(tpHardcodedTrueReturn, findings) == 2

  test "ignores non-theater verification code":
    let findings = scanTheaterSource(goodSource, "fixture.nim")
    check findings.len == 0

when defined(theaterLinterEmitWarnings):
  lintTheaterPatterns(currentSourcePath())
