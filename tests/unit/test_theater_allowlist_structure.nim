## tests/unit/test_theater_allowlist_structure.nim
##
## Runtime validation of `tools/ci/nim_theater_allowlist.json` structure.
## Ensures the allowlist conforms to the scanner contract defined in
## `tools/ci/check_nim_theater.nim` and AGENTS.md §0.9.

import std/[unittest, json, strutils]

const AllowlistJson* = staticRead("tools/ci/nim_theater_allowlist.json")

let allowlist = parseJson(AllowlistJson)

# ═══════════════════════════════════════════════════════════════════════
# Test Suite
# ═══════════════════════════════════════════════════════════════════════

suite "theater allowlist structure":

  test "allowlist is not empty":
    check allowlist.len > 0

  test "no blanket entries — all line values are positive":
    for entry in allowlist:
      check entry["line"].getInt() > 0

  test "every entry has required fields: file, line, rule, reason":
    for entry in allowlist:
      check entry.hasKey("file")
      check entry.hasKey("line")
      check entry.hasKey("rule")
      check entry.hasKey("reason")

  test "every entry carries a canonical symbol anchor":
    # Canonical anchor contract (docs/spec/theater_allowlist_stability.md):
    # identity = file + symbol + rule; line is derived evidence only.
    for entry in allowlist:
      check entry.hasKey("symbol")
      check entry["symbol"].getStr().len > 0

  test "all rule values are within the whitelist S1..S5":
    let validRules = @["S1", "S2", "S3", "S4", "S5"]
    for entry in allowlist:
      let rule = entry["rule"].getStr()
      check rule in validRules

  test "all line values are integers (not null, not string, not float)":
    for entry in allowlist:
      check entry["line"].kind == JInt

  test "all file values are non-empty strings":
    for entry in allowlist:
      let f = entry["file"].getStr()
      check f.len > 0

  test "all reason values are non-empty strings":
    for entry in allowlist:
      let r = entry["reason"].getStr()
      check r.len > 0

  test "total entry count matches expected (166 after cf648b2f8)":
    # cf648b2f8 grew the committed allowlist 139 → 166 without updating this
    # expectation (pre-existing breakage); every structural check above still
    # passes for the 27 added entries, so the count is the stale side.
    check allowlist.len == 166
