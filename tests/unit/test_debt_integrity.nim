import std/[unittest, json, strutils]
import core/debt/debt_integrity

suite "hash invariant - comment-only change":
  test "rawContentHash differs but canonicalSyntaxHash is identical for comment-only change":
    let f1 = "proc f() =\n  result = 1"
    let f2 = "proc f() =\n  # comment\n  result = 1"
    let raw1 = computeRawContentHash(f1)
    let raw2 = computeRawContentHash(f2)
    let canon1 = computeCanonicalSyntaxHash(f1)
    let canon2 = computeCanonicalSyntaxHash(f2)
    check raw1 != raw2
    check canon1 == canon2

suite "hash invariant - whitespace-only change":
  test "rawContentHash differs but canonicalSyntaxHash is identical for whitespace-only change":
    let f1 = "proc f() =\n  result = 1"
    let f2 = "proc f() =\n    result = 1"
    let raw1 = computeRawContentHash(f1)
    let raw2 = computeRawContentHash(f2)
    let canon1 = computeCanonicalSyntaxHash(f1)
    let canon2 = computeCanonicalSyntaxHash(f2)
    check raw1 != raw2
    check canon1 == canon2

suite "hash invariant - code change":
  test "both rawContentHash and canonicalSyntaxHash change for code change":
    let f1 = "proc f() =\n  result = 1"
    let f2 = "proc f() =\n  result = 2"
    let raw1 = computeRawContentHash(f1)
    let raw2 = computeRawContentHash(f2)
    let canon1 = computeCanonicalSyntaxHash(f1)
    let canon2 = computeCanonicalSyntaxHash(f2)
    check raw1 != raw2
    check canon1 != canon2

suite "hash invariant - determinism":
  test "same input produces identical rawContentHash across calls":
    let src = "proc f() =\n  result = 1"
    check computeRawContentHash(src) == computeRawContentHash(src)
    check computeCanonicalSyntaxHash(src) == computeCanonicalSyntaxHash(src)

suite "hash invariant - validateHashBinding":
  test "ok status when both raw and canonical match":
    let src = "proc f() =\n  result = 1"
    let rawHash = computeRawContentHash(src)
    let canonHash = computeCanonicalSyntaxHash(src)
    let entry = %*{"rawContentHash": rawHash, "canonicalSyntaxHash": canonHash}
    check validateHashBinding(entry, rawHash, canonHash) == ok

  test "rawOnly status when only raw differs":
    let src = "proc f() =\n  result = 1"
    let otherSrc = "proc f() =\n  ## comment\n  result = 1"
    let rawHash = computeRawContentHash(src)
    let canonHash = computeCanonicalSyntaxHash(src)
    let entry = %*{"rawContentHash": computeRawContentHash(otherSrc), "canonicalSyntaxHash": canonHash}
    check validateHashBinding(entry, rawHash, canonHash) == rawOnly

  test "substantive status when both differ":
     let src1 = "proc f() =\n  result = 1"
     let src2 = "proc f() =\n  result = 2"
     let rawHash = computeRawContentHash(src1)
     let canonHash = computeCanonicalSyntaxHash(src1)
     let entry = %*{"rawContentHash": computeRawContentHash(src2), "canonicalSyntaxHash": computeCanonicalSyntaxHash(src2)}
     check validateHashBinding(entry, rawHash, canonHash) == substantive

  test "substantive status when canonical has v1 prefix (fail-closed)":
    let src = "proc f() =\n  result = 1"
    let rawHash = computeRawContentHash(src)
    let v1CanonHash = "sha256:v1:abcdef0123456789"
    let entry = %*{"rawContentHash": rawHash, "canonicalSyntaxHash": v1CanonHash}
    check validateHashBinding(entry, rawHash, v1CanonHash) == substantive

  test "substantive status when canonical is empty (fail-closed)":
    let src = "proc f() =\n  result = 1"
    let rawHash = computeRawContentHash(src)
    let entry = %*{"rawContentHash": rawHash, "canonicalSyntaxHash": ""}
    check validateHashBinding(entry, rawHash, "") == substantive

suite "hash invariant - self-describing prefixes":
  test "rawContentHash has sha256: prefix":
    let src = "proc f() =\n  result = 1"
    let h = computeRawContentHash(src)
    check h.startsWith("sha256:")

  test "canonicalSyntaxHash has sha256:v2:nim-pnode-canonical-v2: prefix":
    let src = "proc f() =\n  result = 1"
    let h = computeCanonicalSyntaxHash(src)
    check h.startsWith("sha256:v2:nim-pnode-canonical-v2:")