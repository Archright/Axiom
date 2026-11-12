## Negative test for compositionRootGuard.
## Must FAIL at compile time with:
##   COMPOSITION ROOT GUARD: missing required import 'std/strutils'.
## Run with: nim check tests/negative/axiom_pragmas_negative_test.nim
## Expected: compile error

import core/trusted/axiom_pragmas

# Missing required import "std/strutils"
compositionRootGuard(@["std/strutils"])
