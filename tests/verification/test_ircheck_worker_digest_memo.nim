import std/[os, strutils]
import core/crypto/hash_kernel
import verification/obligation/measured_digests
import verification/obligation/canonical_verification

## ═══════════════════════════════════════════════════════════════════════
## ircheckWorkerBinaryDigest memoization — performance fix (2026-11-14).
##
## measureExtractionAgreement seals the ircheck worker binary's sha256 into
## every SubjectParseBoundComponents. The binary is ~119 MB; one debug-mode
## digest costs ~60 s, and the s1a golden lane measures it once per golden
## subject in the SAME process (three times per run). The digest now flows
## through `ircheckWorkerBinaryDigest` → `measuredBinaryDigest` (stat-identity
## memo: path + size + mtimeNs/ctimeNs + dev/ino), so repeat measurements in
## one process reuse the first digest.
##
## Behavior guarantee under test (identity-preserving, fail-closed):
##   1. same bytes → same digest string, byte-identical to
##      sha256Hex(readFile(file)) — the memo never changes the VALUE, and a
##      memo HIT is machine-observed (measuredDigestStats).
##   2. different bytes → different digest (memo invalidated: a rebuilt
##      worker must never reuse a stale digest — that is why the memo key
##      carries size + mtime, not just the path).
##   3. absent / empty file → "" (unbound, fail-closed — unchanged).
##   4. integration: measureExtractionAgreement (AXIOM_IRCHECK_CMD override)
##      returns the same digest for the same worker file across calls and a
##      changed digest after the file's bytes change.
## ═══════════════════════════════════════════════════════════════════════

var passCount = 0

proc checkTrue(name: string; cond: bool) =
  if cond:
    echo "  [PASS] ", name
    inc passCount
  else:
    echo "  [FAIL] ", name
    quit(1)

proc checkEq(name: string; got, exp: string) =
  checkTrue(name & " (got " & (if got.len > 12: got[0 ..< 12] & "…" else: got) &
    ", exp " & (if exp.len > 12: exp[0 ..< 12] & "…" else: exp) & ")", got == exp)

let tmpA = getTempDir() / ("axiom_digest_memo_" & $getCurrentProcessId() & "_a.bin")
let tmpB = getTempDir() / ("axiom_digest_memo_" & $getCurrentProcessId() & "_b.bin")
let tmpEmpty = getTempDir() / ("axiom_digest_memo_" & $getCurrentProcessId() & "_empty.bin")

# ---------------------------------------------------------------------------
echo "=== P1: memo value-stability (same file → identical digest) ==="
writeFile(tmpA, "worker-bytes-v1")
resetMeasuredDigestStats()
let dA1 = ircheckWorkerBinaryDigest(tmpA)
let missStats = measuredDigestStats()
let dA2 = ircheckWorkerBinaryDigest(tmpA)
let hitStats = measuredDigestStats()
checkTrue("digest is a 64-hex sha256", dA1.len == 64)
checkEq("two consecutive calls return the identical digest", dA2, dA1)
checkEq("memoized digest is byte-identical to sha256Hex(readFile(file))",
  dA1, sha256Hex(readFile(tmpA)))
checkTrue("first call was a memo MISS (measured, not fabricated)",
  missStats.misses == 1 and missStats.hits == 0)
checkTrue("second call was a memo HIT (the memo is actually used)",
  hitStats.hits == 1 and hitStats.misses == 1)

# ---------------------------------------------------------------------------
echo "=== P2: memo invalidation (changed bytes → changed digest) ==="
# Same path, same SIZE, different bytes — the memo key must not let a stale
# digest through (stat mtime + small-file content probe both guard this).
writeFile(tmpA, "worker-bytes-v2")
let dA3 = ircheckWorkerBinaryDigest(tmpA)
checkTrue("same-size rewrite produces a different digest", dA3 != dA1)
checkEq("re-measured digest is byte-identical to sha256Hex(readFile(file))",
  dA3, sha256Hex(readFile(tmpA)))
# Different path, different bytes → different digest.
writeFile(tmpB, "worker-bytes-v3")
let dB1 = ircheckWorkerBinaryDigest(tmpB)
checkTrue("different file with different bytes → different digest", dB1 != dA3)
# Different path, SAME bytes → the digest VALUE is path-independent.
writeFile(tmpB, "worker-bytes-v2")
let dB2 = ircheckWorkerBinaryDigest(tmpB)
checkEq("same bytes at a different path → same digest value", dB2, dA3)
checkEq("repeated call on the second path is stable too",
  ircheckWorkerBinaryDigest(tmpB), dB2)

# ---------------------------------------------------------------------------
echo "=== P3: fail-closed shape preserved ==="
checkEq("empty file → \"\" (unbound, as before the memo)",
  ircheckWorkerBinaryDigest(tmpEmpty), "")
writeFile(tmpEmpty, "")
checkEq("empty file after write → \"\" (empty content is never sealed)",
  ircheckWorkerBinaryDigest(tmpEmpty), "")
checkEq("absent file → \"\"",
  ircheckWorkerBinaryDigest(getTempDir() / "axiom_digest_memo_nonexistent.bin"), "")
checkEq("empty path → \"\"", ircheckWorkerBinaryDigest(""), "")

# ---------------------------------------------------------------------------
echo "=== P4: integration — measureExtractionAgreement seals the same digest ==="
# AXIOM_IRCHECK_CMD points the EA worker resolution at a small temp file, so
# the full measureExtractionAgreement surface (not just the helper) is
# exercised hermetically. The extraction differential itself fails fast
# (non-executable worker → eaUnsupported), and the binary digest is still
# measured from the override file.
const TinySubject = "func tinySubject(x: int): int =\n  x + 1\n"
writeFile(tmpA, "worker-bytes-v1")
putEnv("AXIOM_IRCHECK_CMD", tmpA)
let ea1 = measureExtractionAgreement(TinySubject, "tinySubject")
let ea2 = measureExtractionAgreement(TinySubject, "tinySubject")
checkEq("EA seals the digest of the AXIOM_IRCHECK_CMD file",
  ea1.ircheckBinaryDigest, sha256Hex(readFile(tmpA)))
checkEq("two EA calls return the identical worker digest",
  ea2.ircheckBinaryDigest, ea1.ircheckBinaryDigest)
writeFile(tmpA, "worker-bytes-v2")
let ea3 = measureExtractionAgreement(TinySubject, "tinySubject")
checkTrue("EA digest changes when the worker bytes change",
  ea3.ircheckBinaryDigest != ea1.ircheckBinaryDigest)
checkEq("changed EA digest is byte-identical to sha256Hex(readFile(file))",
  ea3.ircheckBinaryDigest, sha256Hex(readFile(tmpA)))
putEnv("AXIOM_IRCHECK_CMD", "")

for f in [tmpA, tmpB, tmpEmpty]:
  try:
    removeFile(f)
  except CatchableError:
    discard

echo ""
echo "ALL IRCHECK WORKER DIGEST MEMO TESTS PASSED (" & $passCount & " checks)"
