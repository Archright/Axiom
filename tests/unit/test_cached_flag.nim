import std/unittest
import std/sets
import ../../src/cli/action_plan_cli

suite "Global CLI flag parsing":
  test "stripGlobalFlags removes --cached from args":
    let (processed, flags) = stripGlobalFlags(@["report", "--calculate-asi", "--cached"])
    check processed == @["report", "--calculate-asi"]
    check flags.contains("cached")

  test "stripGlobalFlags preserves unknown flags":
    let (processed, flags) = stripGlobalFlags(@["prove", "--limit", "50"])
    check processed == @["prove", "--limit", "50"]
    check not flags.contains("cached")

  test "stripGlobalFlags handles multiple global flags":
    let (processed, flags) = stripGlobalFlags(@["--cached", "report", "--cached"])
    check processed == @["report"]
    check flags.contains("cached")
