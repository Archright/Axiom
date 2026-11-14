## Identity-axis parser contract (`extractBuildEnvField`,
## src/core/utils/build_provenance.nim).
##
## Pins the contract that the `--check-provenance` identity axis depends on
## (docs/spec/verifier_build_identity.md §6a):
##   F1 exact field  — the requested field's value is returned verbatim.
##   F2 field boundary — a longer field name that ENDS with the requested name
##                       (`VerifierBuildSourceHash` vs `BuildSourceHash`) is not
##                       a match; the prefix includes the `* = "` separator.
##   F3 absence      — a missing field yields "" (callers treat it as
##                       "no observation", never as a matching identity).
##   F4 malformed    — a line without a closing quote yields "", never a
##                       truncated value.
##
## All assertions are behavioral; no compiler-guaranteed behavior (§0.7).

import std/unittest

import core/utils/build_provenance

const sampleBody = """
const BuildEnvBuildDate* = "2026-11-14"
const BuildSourceHash* = "vs1-tree-hash/1:111"
  BuildSourceHash* = "vs1-tree-hash/1:222"
  VerifierBuildSourceHash* = "vs1-tree-hash/1:333"
  VerifierBuildId* = "abc123"
"""

suite "extractBuildEnvField":
  test "F1 returns the requested field value":
    check extractBuildEnvField("  VerifierBuildId* = \"deadbeef\"\n", "VerifierBuildId") == "deadbeef"

  test "F2 longer field names are not a match":
    check extractBuildEnvField(sampleBody, "BuildSourceHash") == "vs1-tree-hash/1:222"
    check extractBuildEnvField(sampleBody, "VerifierBuildSourceHash") == "vs1-tree-hash/1:333"
    check extractBuildEnvField(sampleBody, "VerifierBuildId") == "abc123"

  test "F3 absent field yields empty":
    check extractBuildEnvField(sampleBody, "NoSuchField") == ""
    check extractBuildEnvField("", "VerifierBuildId") == ""

  test "F4 malformed line yields empty, never a truncation":
    check extractBuildEnvField("  VerifierBuildId* = \"unterminated\n", "VerifierBuildId") == ""
    check extractBuildEnvField("  VerifierBuildId* = \n", "VerifierBuildId") == ""

  test "F3 the .default seed is observable as a value, not as absence":
    check extractBuildEnvField("  VerifierBuildId* = \"unmeasured\"\n", "VerifierBuildId") == "unmeasured"