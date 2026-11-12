## Source Fingerprint Tests — Content-Addressed Proof Hydration (Phase 0)
##
## Verifies:
##   1. Same source => same fingerprint (determinism)
##   2. Different source => different fingerprint
##   3. Empty string is handled without error
##   4. computeStableSourceFingerprint and computeStableSourceFingerprintSink agree

import std/[unittest]
import core/proof/source_fingerprint

suite "Source Fingerprint":

  test "same source yields same fingerprint":
    let src = "func add(a, b): return a + b"
    let h1 = computeStableSourceFingerprint(src)
    let h2 = computeStableSourceFingerprint(src)
    check h1.len > 0
    check h1 == h2

  test "different source yields different fingerprint":
    let src1 = "func add(a, b): return a + b"
    let src2 = "func mul(a, b): return a * b"
    let h1 = computeStableSourceFingerprint(src1)
    let h2 = computeStableSourceFingerprint(src2)
    check h1 != h2

  test "empty string is handled":
    let h = computeStableSourceFingerprint("")
    check h.len > 0

  test "sink variant agrees with standard variant":
    let src = "func sub(a, b): return a - b"
    let h1 = computeStableSourceFingerprint(src)
    var owned = src
    let h2 = computeStableSourceFingerprintSink(owned)
    check h1 == h2

  test "whitespace-only source is handled":
    let h = computeStableSourceFingerprint("   \n  \n  ")
    check h.len > 0
