## B2 — Readiness feature test wrapper.
##
## Single canonical entry point that runs the full B2 readiness suite from
## repo root:
##   nim c -r --hints:off tests/readiness/readiness_feature_test.nim
##
## The heavy suites live in readiness_policy_test.nim (imported here, which
## registers every suite at import time; std/unittest auto-executes on module
## exit). This wrapper adds a thin meta-suite so the run has one command and a
## single PASS/FAIL summary line.

import std/unittest
import readiness_policy_test

suite "B2 readiness feature entry point":
  test "readiness_policy_test module loaded and suites registered":
    check true
  echo "  [feature] readiness_policy_test.nim imported; suites registered"