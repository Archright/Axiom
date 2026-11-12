## Negative Test: safeParseInt Enforcement
##
## This file SHOULD fail to compile if axiomSafeParse macro works correctly.
## Run with: nim c --hints:off tests/negative/safe_parse_enforcement_test.nim
## Expected: compile error "DEBT PREVENTION: Use safeParseInt"

discard """
  action: "reject"
  errorMsg: "DEBT PREVENTION: Use safeParseInt"
"""

import core/trusted/axiom_pragmas

proc badParse(s: string): int {.axiomSafeParse.} =
  parseInt(s)  # Should trigger compile error
