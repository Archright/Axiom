import std/unittest
import std/sequtils
import core/utils/text_utils
import verification/fingerprint_engine

suite "compactWhitespace contract":
  test "strips leading and trailing whitespace per line":
    let raw = "  line1  \n  line2  "
    check compactWhitespace(raw) == "line1\nline2"

  test "filters out empty lines":
    let raw = "line1\n\n\nline2"
    check compactWhitespace(raw) == "line1\nline2"

  test "empty string returns empty":
    check compactWhitespace("") == ""

  test "all whitespace returns empty":
    check compactWhitespace("   \n   \n   ") == ""

suite "computeFingerprint contract":
  test "same input produces same fingerprint":
    let fp1 = computeFingerprint("proc foo = echo 1", @[])
    let fp2 = computeFingerprint("proc foo = echo 1", @[])
    check fp1 == fp2

  test "different input produces different fingerprint":
    let fp1 = computeFingerprint("proc foo = echo 1", @[])
    let fp2 = computeFingerprint("proc foo = echo 2", @[])
    check fp1 != fp2

  test "constraints affect fingerprint":
    let fp1 = computeFingerprint("proc foo = echo 1", @[])
    let fp2 = computeFingerprint("proc foo = echo 1", @["x > 0"])
    check fp1 != fp2

suite "computeFingerprintCandidates contract":
  test "returns at least one candidate":
    let cands = computeFingerprintCandidates("proc foo = echo 1", @[])
    check cands.len >= 1

  test "candidates are deduplicated":
    let cands = computeFingerprintCandidates("a", @[])
    let unique = cands.deduplicate()
    check cands.len == unique.len

  test "deduplicates normalized original and compact variants":
    let cands = computeFingerprintCandidates("  a  \n  b  ", @[])
    check cands.len == 1
    check cands[0] == computeFingerprint("a\nb", @[])
