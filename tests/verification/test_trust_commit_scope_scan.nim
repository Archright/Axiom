import std/os
import std/strutils
import core/results
import core/gate/trust_commit_scope_scan

## Unit test for trust_commit_scope_scan (I7 authority-based scanner).
##
## The scanner is SINK-CENTRIC: only raw persistence effects targeting an
## AUTHORITATIVE trust representation (data/trusted/journal) outside the TrustCommit
## closure are flagged. Derived certificate / cache / transient writes are OUT
## of the I7 universe. Closed-world: a trust-relevant durable write whose class
## cannot be resolved (decUnknown) fails.

var failures = 0

proc expect(cond: bool; msg: string) =
  if not cond:
    inc failures
    echo "  FAIL: " & msg

var tmpCounter = 0
proc nextTmpDir(): string =
  inc tmpCounter
  getTempDir() / "axiom_scope_scan_test" & "_" & $getCurrentProcessId() & "_" & $tmpCounter

proc writeFixture(d: string; name, content: string): string =
  if not dirExists(d):
    createDir(d)
  let p = d / name
  writeFile(p, content)
  p

# --- Positive: append_store.writeRecord is closure-routed, not flagged ---
proc testAllowedWriterNotFlagged() =
  let d = nextTmpDir()
  discard writeFixture(d, "positive_fixture.nim", """
    let ok = append_store.writeRecord(journalPath, jsonContent)
    """)
  let res = scanForDirectWrites(d)
  expect(
    res.ok and res.value.len == 0,
    "positive case: append_store.writeRecord should not be flagged; got " &
      $res.value.len & " findings")

# --- I7-A/I7-B: raw writeFile to an authoritative literal path is flagged ---
proc testAuthoritativeLiteralFlagged() =
  let d = nextTmpDir()
  discard writeFixture(d, "auth_literal.nim", """
proc evil(baseDir: string) =
  writeFile(baseDir / "data/trusted/journal/commit.json", "{}")
""")
  let res = scanForDirectWrites(d)
  expect(
    res.ok and res.value.len == 1,
    "authoritative literal case: raw writeFile to data/trusted/journal must be flagged; got " &
      $res.value.len & " findings")
  if res.ok and res.value.len >= 1:
    expect(
      res.value[0].call == "writeFile",
      "authoritative literal case: call should be 'writeFile', got '" &
        res.value[0].call & "'")

# --- Closed-world: raw writeFile to a journal-named dynamic path is flagged ---
proc testJournalVariableFlagged() =
  let d = nextTmpDir()
  discard writeFixture(d, "journal_var.nim", """
proc evil2(baseDir: string) =
  let journalPath = baseDir / "trusted" / "journal"
  writeFile(journalPath / "commit.json", "{}")
""")
  let res = scanForDirectWrites(d)
  expect(
    res.ok and res.value.len == 1,
    "closed-world case: raw writeFile to a journal-named path (decUnknown) must be flagged; got " &
      $res.value.len & " findings")

# --- Derived: raw writeFile to the certificate area is NOT flagged (I7-A exempt) ---
proc testDerivedCertNotFlagged() =
  let d = nextTmpDir()
  discard writeFixture(d, "derived_cert.nim", """
proc writeCert(certPath: string) =
  writeFile(certPath, renderedCert)
""")
  # Add a derived literal target line in the same dir.
  discard writeFixture(d, "derived_cert2.nim", """
proc writeCert2() =
  writeFile("src/verification/certificates/proof.json", renderedCert)
""")
  let res = scanForDirectWrites(d)
  expect(
    res.ok and res.value.len == 0,
    "derived cert case: raw writeFile to certificate area must be exempt (I7-A); got " &
      $res.value.len & " findings")

# --- Cache: raw writeFile to cache area is NOT flagged (out of I7 universe) ---
proc testCacheWriteNotFlagged() =
  let d = nextTmpDir()
  discard writeFixture(d, "cache.nim", """
proc cacheIt(baseDir: string) =
  writeFile(baseDir / ".cache/proof_cache.json", "{}")
""")
  let res = scanForDirectWrites(d)
  expect(
    res.ok and res.value.len == 0,
    "cache case: raw writeFile to cache area must be exempt; got " &
      $res.value.len & " findings")

# --- Line-number correctness: real source line index reported ---
proc testLineNumberCorrect() =
  let d = nextTmpDir()
  discard writeFixture(d, "line_bug.nim", """
proc a() =
  discard 1
proc evil3(baseDir: string) =
  writeFile(baseDir / "data/trusted/journal/x.json", "{}")
proc c() =
  discard 2
""")
  let res = scanForDirectWrites(d)
  expect(
    res.ok and res.value.len == 1,
    "line-number case: exactly one finding expected; got " & $res.value.len)
  if res.ok and res.value.len == 1:
    # evil3's writeFile is on source line 4.
    expect(
      res.value[0].line == 4,
      "line-number case: finding must be at line 4, got " & $res.value[0].line)

# --- DEBT#471: import-aware routing — bare writeFileOpt under an io_utils
# --- import is io_utils.writeFileOpt, hence closure-routed. The dormant
# --- false positive at src/verification/vault_index.nim:124 (best-effort
# --- comment mentioning "journal") must stay disarmed even when the comment
# --- is reworded to drop "cache" (the re-armament mutation).
proc testImportAwareRoutingDisarmsDormantFP() =
  let d = nextTmpDir()
  discard writeFixture(d, "vault_like.nim", """
import core/utils/io_utils

proc saveIndex(path: string) =
  discard writeFileOpt(path, pretty(root))  # axiom:best-effort(vault index is derived; authoritative state is TrustCommit journal)
""")
  let res = scanForDirectWrites(d)
  expect(
    res.ok and res.value.len == 0,
    "import-aware routing: bare writeFileOpt under io_utils import must be routed; got " &
      $res.value.len & " findings")

# --- DEBT#471: classification is TARGET-based — a comment word ("journal")
# --- must not classify a write whose target carries no authoritative
# --- vocabulary. This is the re-armament pin: the old line-based classifier
# --- flagged this fixture, the target-based one does not.
proc testTargetBasedIgnoresCommentVocabulary() =
  let d = nextTmpDir()
  discard writeFixture(d, "comment_vocab.nim", """
proc saveIndex(path: string) =
  discard writeFileOpt(path, pretty(root))  # authoritative state is TrustCommit journal
""")
  let res = scanForDirectWrites(d)
  expect(
    res.ok and res.value.len == 0,
    "target-based classification: comment vocabulary must not flag an unrelated target; got " &
      $res.value.len & " findings")

# --- DEBT#471: import-aware routing must NOT over-exempt non-allowlisted
# --- sinks: bare stdlib writeFile stays flagged even in an io_utils-importing
# --- file when the target denotes the journal.
proc testImportAwareDoesNotOverExempt() =
  let d = nextTmpDir()
  discard writeFixture(d, "stdlib_sink.nim", """
import core/utils/io_utils

proc evil4(baseDir: string) =
  writeFile(baseDir / "trusted" / "journal" / "commit.json", "{}")
""")
  let res = scanForDirectWrites(d)
  expect(
    res.ok and res.value.len == 1,
    "import-aware routing must not over-exempt: stdlib writeFile to journal must be flagged; got " &
      $res.value.len & " findings")

# --- DEBT#471: a bare allowlisted leaf call counts as routed only when the
# --- provider module is actually imported. A bare writeFileOpt with no
# --- io_utils import is an unrouted raw sink and must flag on an
# --- authoritative target; with the import it is closure-routed.
proc testBareAllowlistedRequiresProviderImport() =
  let unrouted = nextTmpDir()
  discard writeFixture(unrouted, "bare_opt.nim", """
proc evil5(baseDir: string) =
  discard writeFileOpt(baseDir / "data/trusted/journal/commit.json", rendered)
""")
  let resUnrouted = scanForDirectWrites(unrouted)
  expect(
    resUnrouted.ok and resUnrouted.value.len == 1,
    "bare writeFileOpt without io_utils import must be flagged on journal target; got " &
      $resUnrouted.value.len & " findings")
  let routed = nextTmpDir()
  discard writeFixture(routed, "routed_opt.nim", """
import core/utils/io_utils

proc moveJournal(path: string) =
  discard writeFileOpt(path, rendered)
""")
  let resRouted = scanForDirectWrites(routed)
  expect(
    resRouted.ok and resRouted.value.len == 0,
    "bare writeFileOpt under io_utils import must be routed; got " &
      $resRouted.value.len & " findings")

# --- DEBT#471: scan-scope SSOT + judgment closure digest determinism ---
proc testScanScopeAndClosureDigest() =
  let stagedDir = nextTmpDir()
  createDir(stagedDir)
  let otherDir = nextTmpDir()
  createDir(otherDir)
  # Digest binds scope + staged axis; identical inputs → identical digest.
  let d1 = judgmentClosureDigest("/nonexistent-repo-root", @[stagedDir / "a.nim"])
  let d2 = judgmentClosureDigest("/nonexistent-repo-root", @[stagedDir / "a.nim"])
  expect(d1.len > 0 and d1 == d2,
    "judgment closure digest: identical inputs must yield identical digest")
  # Different staged axis → different digest.
  let d3 = judgmentClosureDigest("/nonexistent-repo-root", @[otherDir / "b.nim"])
  expect(d3 != d1,
    "judgment closure digest: different scope must yield different digest")
  # Staged-file directory wins over the src fallback.
  expect(
    resolveScanScope("/nonexistent-repo-root", @[stagedDir / "a.nim"]) == stagedDir,
    "scan-scope SSOT: staged-file directory must win")
  # Multi-dir staged set: scope is the COMMON ANCESTOR, not the first parent —
  # a first-parent scope lets violations in sibling staged dirs escape (the
  # hollow-PASS hole observed in DEBT#471 evidence).
  createDir(stagedDir / "sub1")
  createDir(stagedDir / "sub2")
  expect(
    resolveScanScope("/nonexistent-repo-root",
      @[stagedDir / "sub1" / "a.nim", stagedDir / "sub2" / "b.nim"]) == stagedDir,
    "scan-scope SSOT: multi-dir staged set resolves to the common ancestor")
  # Scope resolution is order-independent → the closure digest is too.
  let dUnion1 = judgmentClosureDigest("/nonexistent-repo-root",
    @[stagedDir / "sub1" / "a.nim", stagedDir / "sub2" / "b.nim"])
  let dUnion2 = judgmentClosureDigest("/nonexistent-repo-root",
    @[stagedDir / "sub2" / "b.nim", stagedDir / "sub1" / "a.nim"])
  expect(dUnion1.len > 0 and dUnion1 == dUnion2,
    "judgment closure digest: staged-set order must not change the digest")
  # Environment-dependent discovery — save and restore AXIOM_ROOT.
  let origRoot = getEnv("AXIOM_ROOT")
  let fakeRoot = nextTmpDir()
  createDir(fakeRoot / "src")
  putEnv("AXIOM_ROOT", fakeRoot)
  expect(
    resolveScanScope("", @[]) == fakeRoot / "src",
    "scan-scope SSOT: repo-root discovery resolves <root>/src")
  # Scope unresolvable (AXIOM_ROOT without src, no staged dirs) → "" — the
  # fail-closed closure signal.
  let bareRoot = nextTmpDir()
  createDir(bareRoot)
  putEnv("AXIOM_ROOT", bareRoot)
  expect(
    resolveScanScope("", @[]) == "",
    "scan-scope SSOT: unresolvable scope must be empty (fail-closed closure)")
  if origRoot.len > 0:
    putEnv("AXIOM_ROOT", origRoot)
  else:
    delEnv("AXIOM_ROOT")

# --- Run all ---
echo "  trust_commit_scope_scan tests:"
testAllowedWriterNotFlagged()
testAuthoritativeLiteralFlagged()
testJournalVariableFlagged()
testDerivedCertNotFlagged()
testCacheWriteNotFlagged()
testLineNumberCorrect()
testImportAwareRoutingDisarmsDormantFP()
testTargetBasedIgnoresCommentVocabulary()
testImportAwareDoesNotOverExempt()
testBareAllowlistedRequiresProviderImport()
testScanScopeAndClosureDigest()

if failures == 0:
  echo "    ALL PASSED"
else:
  echo "    FAILED: " & $failures & " assertion(s)"
  quit(1)
