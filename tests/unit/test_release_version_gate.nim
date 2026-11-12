import std/unittest
import std/options
import std/strutils
import core/results
import core/release/version_derive

suite "normalizeReleaseTag":
  test "accepts v-prefixed":
    check normalizeReleaseTag("v0.3.7") == some("0.3.7")

  test "accepts bare":
    check normalizeReleaseTag("0.3.7") == some("0.3.7")

  test "trims surrounding whitespace":
    check normalizeReleaseTag("  v0.3.7\n") == some("0.3.7")

  test "rejects partial version":
    check normalizeReleaseTag("v0.3").isNone

  test "rejects four components":
    check normalizeReleaseTag("v0.3.7.1").isNone

  test "rejects pre-release suffix":
    check normalizeReleaseTag("v0.3.7-rc1").isNone

  test "rejects empty":
    check normalizeReleaseTag("").isNone

suite "validateReleaseVersion":
  test "matching tag and package pass":
    check validateReleaseVersion("v0.3.7", "0.3.7").isOk

  test "bare tag passes":
    check validateReleaseVersion("0.3.7", "0.3.7").isOk

  test "v0.5.8 vs 0.3.7 fails":
    let r = validateReleaseVersion("v0.5.8", "0.3.7")
    check r.isErr
    check r.error.contains("0.5.8")

  test "invalid tag fails":
    check validateReleaseVersion("v0.5", "0.3.7").isErr

  test "invalid package version fails":
    check validateReleaseVersion("v0.3.7", "unknown").isErr

suite "validateNimbleVersionString":
  test "accepts 0.3.7":
    let r = validateNimbleVersionString("0.3.7")
    check r.isOk
    check r.get() == "0.3.7"

  test "accepts v0.3.7 and normalizes":
    let r = validateNimbleVersionString("v0.3.7")
    check r.isOk
    check r.get() == "0.3.7"

  test "rejects partial version":
    check validateNimbleVersionString("0.3").isErr

  test "rejects prerelease suffix":
    check validateNimbleVersionString("0.3.7-rc1").isErr

  test "rejects empty":
    check validateNimbleVersionString("").isErr

suite "validateBinaryVersion":
  test "exact v-prefixed output passes":
    check validateBinaryVersion("v0.3.7", "v0.3.7\n").isOk

  test "bare output passes":
    check validateBinaryVersion("v0.3.7", "0.3.7\n").isOk

  test "different patch fails":
    check validateBinaryVersion("v0.3.7", "v0.3.8\n").isErr

  test "decorated output fails":
    check validateBinaryVersion("v0.3.7", "ax v0.3.7\n").isErr

  test "two lines fail":
    check validateBinaryVersion("v0.3.7", "v0.3.7\nnoise\n").isErr

  test "empty output fails":
    check validateBinaryVersion("v0.3.7", "").isErr

  test "invalid expected version fails":
    check validateBinaryVersion("v0.3", "v0.3\n").isErr

suite "parseLakeVersion":
  test "reads quoted version":
    check parseLakeVersion("name = \"axiom\"\nversion = \"0.5.9\"\n") == some("0.5.9")

  test "normalizes v-prefixed value":
    check parseLakeVersion("version = \"v0.5.9\"\n") == some("0.5.9")

  test "ignores commented version lines":
    check parseLakeVersion("# version = \"9.9.9\"\nversion = \"0.5.9\"\n") == some("0.5.9")

  test "missing version returns none":
    check parseLakeVersion("name = \"axiom\"\n").isNone

  test "malformed version returns none":
    check parseLakeVersion("version = \"latest\"\n").isNone

suite "validateLakeVersion":
  test "matching tag and lake pass":
    check validateLakeVersion("v0.5.9", "0.5.9").isOk

  test "mismatch fails and names both values":
    let r = validateLakeVersion("v0.5.9", "0.3.7")
    check r.isErr
    check r.error.contains("0.5.9")
    check r.error.contains("0.3.7")

  test "invalid lake version fails":
    check validateLakeVersion("v0.5.9", "latest").isErr

  test "invalid tag fails":
    check validateLakeVersion("v0.5", "0.5.9").isErr
