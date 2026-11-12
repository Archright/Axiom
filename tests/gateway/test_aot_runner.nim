import std/[unittest, os, osproc, times, strutils]

# AOT execution-contract test — verifies the pre-built canonical CLI surface,
# NOT a build workflow. Source↔binary freshness is enforced separately by
# binary_freshness_gate (run `nimble build`/`make build` first, e.g. ci-bootstrap).
# Rebuilding here was removed because release+LTO linking (~100s) is inherently
# non-incremental, making the test slow and environment-dependent.

suite "AOT integrity test runner":
  test "AOT binary exists at configured path":
    check fileExists("bin/ax")

  test "AOT binary executes and passes within 5 seconds":
    check fileExists("bin/ax")
    let start = epochTime()
    let (output, exitCode) = execCmdEx("bin/ax help")
    let elapsed = epochTime() - start
    check exitCode == 0
    check elapsed < 5.0
    check "usage:" in output
