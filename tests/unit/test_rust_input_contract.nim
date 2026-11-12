## Rust subject INPUT CONTRACT tests (feat/rust-subject-v1 Phase 1-A).
##
## Contract under test:
##   1. LLBC file-table pre-validation
##      (verification/llbc_to_canonical.validateLlbcFileTable) — one
##      NEGATIVE test per rejection rule (ids present/non-negative/unique,
##      sole-key `Local` non-empty names, path grammar, unique paths,
##      embedded contents; foreign-crate contents ignored) + the measured
##      probe positive. Every rejection is fail-closed with a reason naming
##      the rule and the offending entry.
##   2. File-set equivalence (verification/rust_input_contract) — LLBC local
##      table vs subject `.rs` set: exact path-set equality + per-path
##      sha256; staleness/mismatch/extra-file diagnostics name the offending
##      paths; Cargo.lock/Cargo.toml digests (§10.2 nimble.lock mirror);
##      absent Cargo.lock → fail-closed.
##   3. `.rs` collection parameterization
##      (core/context/run_context.collectSubjectFileSet + rustSourcePolicy)
##      — .rs set collected, Nim set bit-identical to the default call.
##   4. Pipeline wiring — subjectRoot runs the contract FIRST; a contract
##      rejection is outcomeFailClosed with eaMismatch (the dvcNotCurrent
##      staleness axis), never eaInternalError, never verified.
##
## Standalone runner (the three-cases gateway precedent): the Rust subject
## lane has no ax CLI surface yet, so this file runs via
##   nim c -r -d:release tests/unit/test_rust_input_contract.nim
## and is not registered in the Makefile execution boundary.
## Environment gate (explicit skip, not failure): the real-probe suites
## need /tmp/axiom-rust-probe/axiom_rust_probe.llbc.

import std/[unittest, os, strutils, json, algorithm]

import core/context/run_context
import core/topology/node_filter
import core/crypto/hash_kernel
import core/results
import core/trusted/rust_canonical
import checksums/sha2
import verification/llbc_to_canonical
import verification/rust_input_contract
import verification/extraction_agreement
import verification/rust_rust_pipeline

const ProbePath = "/tmp/axiom-rust-probe/axiom_rust_probe.llbc"
const ProbeDir = "/tmp/axiom-rust-probe"

let probePresent = fileExists(ProbePath)

if not probePresent:
  echo "SKIP: real probe not found at " & ProbePath &
    " — real-probe suites skipped (explicit skip, not a failure)"

# ─── fixtures — the MEASURED probe files-table shape ────────────────────────

const LibRs = "pub fn synth_add(a: u8, b: u8) -> u8 { a.wrapping_add(b) }\n"
  ## subject source embedded in the fixture LLBC (and written to disk for
  ## the equivalence pass case)

proc baseDoc(): JsonNode =
  ## charon 0.1.281 shape: subject-crate local entry WITH embedded contents
  ## + a foreign std-core entry that ALSO carries the `Local` tag but with
  ## an absolute /rustc/... path and null contents (measured on the probe).
  parseJson("""{
   "charon_version": "0.1.281",
   "has_errors": false,
   "translated": {
    "crate_name": "synth",
    "files": [
     {
      "id": 0,
      "name": {"Local": "src/lib.rs"},
      "crate_name": "synth",
      "contents": "pub fn synth_add(a: u8, b: u8) -> u8 { a.wrapping_add(b) }\n"
     },
     {
      "id": 1,
      "name": {"Local": "/rustc/library/core/src/lib.rs"},
      "crate_name": "core",
      "contents": null
     }
    ]
   }
  }""")

func filesTable(doc: JsonNode): JsonNode =
  doc{"translated"}{"files"}

proc subjectRootWith(files: openArray[tuple[rel: string, body: string]];
    withCargo = true): string =
  ## throwaway subject dir (NOT a git repo → the walkDirRec fallback lane,
  ## same as the real probe dir)
  let root = getTempDir() / "axiom_rust_contract_" & $getCurrentProcessId()
  removeDir(root)
  createDir(root)
  for f in files:
    createDir(root / f.rel.splitFile().dir)
    writeFile(root / f.rel, f.body)
  if withCargo:
    writeFile(root / "Cargo.lock",
      "version = 4\n[[package]]\nname = \"synth\"\nversion = \"0.1.0\"\n")
    writeFile(root / "Cargo.toml",
      "[package]\nname = \"synth\"\nversion = \"0.1.0\"\nedition = \"2021\"\n")
  root

# golden §10.2 digests: sha256 of the RAW sha256 bytes cast as a 32-char
# string (the nimble.lock precedent, run_context.nim) — precomputed values
const LockContent =
  "version = 4\n[[package]]\nname = \"synth\"\nversion = \"0.1.0\"\n"
const GoldenLockDigest = "e60f9d807b7406f09341c8455362872f51ae539322f093af7721eb11d9afefa7"
const GoldenManifestDigest = "054f5c05f951c8c5d1a49444b6e65c2c235b35466301d6c8fb5a58d73ca6a443"
const GoldenLibRsSha256 = "7850d87b996acb175d25f7e8ee2941cce6ee6e7093eb9888f2bca091984c276f"
  ## plain sha256 hex of LibRs (the disk-side digest form, comparable with
  ## sha256Hex of the LLBC-embedded contents)

func rawSha256Bytes(payload: string): array[32, byte] =
  let digest = secureHash(Sha_256, payload)
  for i in 0 .. 31:
    result[i] = byte(digest[i])

# ─── Suite 1: file-table pre-validation — rejection matrix (fail-closed) ────

suite "llbc file-table pre-validation — rejection matrix (reject-not-skip)":

  test "POSITIVE: measured shape → ok; foreign entry excluded from the table":
    let r = validateLlbcFileTable(baseDoc())
    check r.ok
    check r.reason == ""
    check r.entries.len == 1
    check r.entries[0].id == 0
    check r.entries[0].relPath == "src/lib.rs"
    check r.entries[0].contents == LibRs

  test "rule 1a: id missing → reject naming the entry":
    var doc = baseDoc()
    doc{"translated"}{"files"}[0].delete("id")
    let r = validateLlbcFileTable(doc)
    check not r.ok
    check r.reason.contains("files[0]")
    check r.reason.contains("'id'")

  test "rule 1b: negative id → reject":
    var doc = baseDoc()
    doc{"translated"}{"files"}[0]{"id"} = newJInt(-1)
    let r = validateLlbcFileTable(doc)
    check not r.ok
    check r.reason.contains("non-negative integer")

  test "rule 1c: non-integer id → reject":
    var doc = baseDoc()
    doc{"translated"}{"files"}[0]{"id"} = newJString("0")
    let r = validateLlbcFileTable(doc)
    check not r.ok
    check r.reason.contains("'id' must be a present non-negative integer")

  test "rule 2a: subject-crate name not sole-key Local → reject":
    var doc = baseDoc()
    doc{"translated"}{"files"}[0]{"name"} = parseJson(
      """{"NotLocal": "src/lib.rs"}""")
    let r = validateLlbcFileTable(doc)
    check not r.ok
    check r.reason.contains("sole-key 'Local'")

  test "rule 2b: empty Local path → reject":
    var doc = baseDoc()
    doc{"translated"}{"files"}[0]{"name"} = parseJson("""{"Local": ""}""")
    let r = validateLlbcFileTable(doc)
    check not r.ok
    check r.reason.contains("non-empty string")

  test "rule 3: duplicate id across the table (foreign entry) → reject":
    var doc = baseDoc()
    doc{"translated"}{"files"}[1]{"id"} = newJInt(0)
    let r = validateLlbcFileTable(doc)
    check not r.ok
    check r.reason.contains("duplicate file id 0")
    check r.reason.contains("unique across the table")

  test "rule 4: duplicate Local path (subject crate) → reject":
    var doc = baseDoc()
    let dup = parseJson(
      """{"id": 7, "name": {"Local": "src/lib.rs"}, "crate_name": "synth",
          "contents": "x"}""")
    doc{"translated"}{"files"}.elems.add(dup)
    let r = validateLlbcFileTable(doc)
    check not r.ok
    check r.reason.contains("duplicate Local path 'src/lib.rs'")

  test "rule 5a-1: subject-crate absolute path + string contents → " &
      "embeddedContentAttested (accepted, classified, excluded)":
    var doc = baseDoc()
    doc{"translated"}{"files"}[0]{"name"} = parseJson(
      """{"Local": "/abs/out/private.rs"}""")
    let r = validateLlbcFileTable(doc)
    check r.ok
    check r.entries.len == 0
      # files[0] is no longer a subject source; foreign files[1] skipped
    check r.embedded.len == 1
    check r.embedded[0].index == 0
    check r.embedded[0].rawPath == "/abs/out/private.rs"
    check r.embedded[0].crateName == "synth"
    check r.embedded[0].contentSha256 == sha256Hex(LibRs)
    check r.embedded[0].contentSha256 == GoldenLibRsSha256
    check r.rejection.rule == ""

  test "rule 5a-2: absolute path + null contents → reject (byte-identical " &
      "path_absolute)":
    var doc = baseDoc()
    doc{"translated"}{"files"}[0]{"name"} = parseJson(
      """{"Local": "/abs/out/private.rs"}""")
    doc{"translated"}{"files"}[0]{"contents"} = newJNull()
    let r = validateLlbcFileTable(doc)
    check not r.ok
    check r.reason.contains("absolute path")
    check r.rejection.rule == "path_absolute"
    check r.rejection.contentSha256 == ""

  test "rule 5a-3: duplicate embedded absolute path → reject":
    var doc = baseDoc()
    doc{"translated"}{"files"}[0]{"name"} = parseJson(
      """{"Local": "/abs/out/private.rs"}""")
    let dup = parseJson(
      """{"id": 7, "name": {"Local": "/abs/out/private.rs"}, "crate_name": "synth",
          "contents": "x"}""")
    doc{"translated"}{"files"}.elems.add(dup)
    let r = validateLlbcFileTable(doc)
    check not r.ok
    check r.reason.contains("duplicate absolute path '/abs/out/private.rs'")
    check r.rejection.rule == "embedded_path_duplicate"

  test "rule 5b: '..' segment → reject":
    var doc = baseDoc()
    doc{"translated"}{"files"}[0]{"name"} = parseJson(
      """{"Local": "src/../lib.rs"}""")
    let r = validateLlbcFileTable(doc)
    check not r.ok
    check r.reason.contains("'..' segment")

  test "rule 5c: empty segment → reject":
    var doc = baseDoc()
    doc{"translated"}{"files"}[0]{"name"} = parseJson(
      """{"Local": "src//lib.rs"}""")
    let r = validateLlbcFileTable(doc)
    check not r.ok
    check r.reason.contains("empty path segment")

  test "rule 5d: non-POSIX separator → reject":
    var doc = baseDoc()
    doc{"translated"}{"files"}[0]{"name"} = parseJson(
      """{"Local": "src\\lib.rs"}""")
    let r = validateLlbcFileTable(doc)
    check not r.ok
    check r.reason.contains("non-POSIX separator")

  test "rule 5e: '.' segment → reject":
    var doc = baseDoc()
    doc{"translated"}{"files"}[0]{"name"} = parseJson(
      """{"Local": "src/./lib.rs"}""")
    let r = validateLlbcFileTable(doc)
    check not r.ok
    check r.reason.contains("'.' segment")

  test "rule 6a: subject-crate contents null → reject":
    var doc = baseDoc()
    doc{"translated"}{"files"}[0]{"contents"} = newJNull()
    let r = validateLlbcFileTable(doc)
    check not r.ok
    check r.reason.contains("'contents' as a string")

  test "rule 6b: subject-crate contents missing → reject":
    var doc = baseDoc()
    doc{"translated"}{"files"}[0].delete("contents")
    let r = validateLlbcFileTable(doc)
    check not r.ok
    check r.reason.contains("'contents' as a string")

  test "rule 6 policy: foreign entry WITH contents → ignored, never read":
    var doc = baseDoc()
    doc{"translated"}{"files"}[1]{"contents"} = newJString("std source text")
    let r = validateLlbcFileTable(doc)
    check r.ok
    check r.entries.len == 1
    check r.entries[0].relPath == "src/lib.rs"

  test "discriminator: missing translated.crate_name → reject":
    var doc = baseDoc()
    doc{"translated"}.delete("crate_name")
    let r = validateLlbcFileTable(doc)
    check not r.ok
    check r.reason.contains("crate_name")

  test "discriminator: missing per-entry crate_name → reject":
    var doc = baseDoc()
    doc{"translated"}{"files"}[0].delete("crate_name")
    let r = validateLlbcFileTable(doc)
    check not r.ok
    check r.reason.contains("files[0]")
    check r.reason.contains("'crate_name'")

  test "producer wiring: table violation fails the WHOLE document before " &
      "any consumption (both producers)":
    var doc = baseDoc()
    doc{"translated"}{"files"}[0]{"contents"} = newJNull()
    doc{"translated"}{"fun_decls"} = newJArray()
    let r1 = llbcFunctionToCanonical(doc, "anything")
    check not r1.ok
    check r1.error == rceMalformed
    check r1.reason.startsWith("LLBC files table pre-validation failed:")
    let r2 = llbcAllToCanonical(doc)
    check r2.len == 1
    check not r2[0].ok
    check r2[0].reason.startsWith("LLBC files table pre-validation failed:")

if probePresent:
  suite "llbc file-table pre-validation — real probe (charon 0.1.281)":
    let f = parseLlbcFile(ProbePath)

    test "real probe passes pre-validation; table = the subject crate only":
      check f.ok
      let r = validateLlbcFileTable(f.root)
      check r.ok
      check r.entries.len == 1
      check r.entries[0].relPath == "src/lib.rs"
      check r.entries[0].contents ==
        readFile(ProbeDir / "src" / "lib.rs")
      check r.embedded.len == 0

    test "real probe producer still extracts add_u8 (no regression)":
      let r = llbcFunctionToCanonical(f.root, "add_u8")
      check r.ok
      check r.canonical.sourceIdentity == "src/lib.rs:3:0-5:1"

# ─── Suite 2: input contract — file-set equivalence + Cargo identity ────────

suite "rust subject input contract — file-set equivalence (fail-closed)":

  test "PASS: LLBC table binds exactly to the subject .rs set":
    let root = subjectRootWith([("src/lib.rs", LibRs)])
    defer: removeDir(root)
    let c = rustSubjectInputContract(baseDoc(), root)
    check c.ok
    check c.reason == ""
    check c.localFiles.len == 1
    check c.subjectFiles.len == 1
    check c.subjectFiles[0].relPath == "src/lib.rs"
    check c.subjectFiles[0].sha256 == GoldenLibRsSha256
    check c.usedFallback
    # D1 record structure: same encoders, byte-lex order, finalize
    let expected = finalizeSourceFingerprint(@[
      encodeFingerprintRecord("src/lib.rs", rawSha256Bytes(LibRs))])
    check c.subjectFingerprint == expected

  test "stale source: disk content differs → fail-closed naming the path":
    let root = subjectRootWith([("src/lib.rs",
      "pub fn synth_add(a: u8, b: u8) -> u8 { a.wrapping_add(b).wrapping_add(1) }\n")])
    defer: removeDir(root)
    let c = rustSubjectInputContract(baseDoc(), root)
    check not c.ok
    check c.reason.contains("not current")
    check c.reason.contains("content hash mismatch")
    check c.reason.contains("src/lib.rs")
    check c.reason.contains("llbc=")
    check c.reason.contains("disk=")

  test "new module on disk, absent from LLBC → fail-closed naming it":
    let root = subjectRootWith([("src/lib.rs", LibRs),
                                ("src/extra.rs", "pub fn e() {}\n")])
    defer: removeDir(root)
    let c = rustSubjectInputContract(baseDoc(), root)
    check not c.ok
    check c.reason.contains("missing from the LLBC local table")
    check c.reason.contains("src/extra.rs")

  test "extra file in LLBC, absent on disk → fail-closed naming it":
    var doc = baseDoc()
    let ghost = parseJson(
      """{"id": 5, "name": {"Local": "src/ghost.rs"}, "crate_name": "synth",
          "contents": "pub fn ghost() {}\n"}""")
    doc{"translated"}{"files"}.elems.add(ghost)
    let root = subjectRootWith([("src/lib.rs", LibRs)])
    defer: removeDir(root)
    let c = rustSubjectInputContract(doc, root)
    check not c.ok
    check c.reason.contains("missing from the subject file set")
    check c.reason.contains("src/ghost.rs")

  test "masquerade: subject .rs listed as an absolute embedded entry → " &
      "missingInLlbc fail-closed":
    var doc = baseDoc()
    doc{"translated"}{"files"}[0]{"name"} = parseJson(
      """{"Local": "/abs/src/lib.rs"}""")
    let root = subjectRootWith([("src/lib.rs", LibRs)])
    defer: removeDir(root)
    let c = rustSubjectInputContract(doc, root)
    check not c.ok
    check c.reason.contains("missing from the LLBC local table")
    check c.reason.contains("src/lib.rs")
    check c.embeddedFiles.len == 1
      # classified — but the contract still fails closed: the disk set has
      # no matching relative entry, so the source set cannot silently shrink

  test "§6d propagation: contract ok carries embeddedFiles":
    # vacuous equality (both sides empty) is a documented pass — the Cargo
    # identity pins the subject (see equivalenceProblems)
    let root = subjectRootWith([], withCargo = true)
    defer: removeDir(root)
    var doc = baseDoc()
    doc{"translated"}{"files"}[0]{"name"} = parseJson(
      """{"Local": "/abs/out/private.rs"}""")
    let c = rustSubjectInputContract(doc, root)
    check c.ok
    check c.localFiles.len == 0
    check c.embeddedFiles.len == 1
    check c.embeddedFiles[0].index == 0
    check c.embeddedFiles[0].rawPath == "/abs/out/private.rs"
    check c.embeddedFiles[0].contentSha256 == sha256Hex(LibRs)

  test "Cargo.lock absent → fail-closed (v1 requires a Cargo crate)":
    let root = subjectRootWith([("src/lib.rs", LibRs)], withCargo = false)
    defer: removeDir(root)
    let c = rustSubjectInputContract(baseDoc(), root)
    check not c.ok
    check c.reason.contains("Cargo.lock absent")

  test "Cargo.toml absent → fail-closed":
    let root = subjectRootWith([("src/lib.rs", LibRs)], withCargo = false)
    writeFile(root / "Cargo.lock", LockContent)
    defer: removeDir(root)
    let c = rustSubjectInputContract(baseDoc(), root)
    check not c.ok
    check c.reason.contains("Cargo.toml absent")

suite "rust subject input contract — dep-info binding (the lane's mode)":

  proc depInfoFor(root: string; rels: openArray[string]): string =
    ## Write a rustc-shaped dep-info under the temp root and return its path.
    let p = root / "libsynth.d"
    var line = root / "libsynth.rlib:"
    for rel in rels:
      line.add(" " & root / rel)
    writeFile(p, line & "\n")
    p

  test "cfg-excluded subject file absent from LLBC → ok (dep-info is the " &
      "authoritative input set)":
    let root = subjectRootWith([("src/lib.rs", LibRs),
                                ("src/extra.rs", "pub fn e() {}\n")])
    defer: removeDir(root)
    let dep = depInfoFor(root, ["src/lib.rs"])
    let c = rustSubjectInputContract(baseDoc(), root, dep)
    check c.ok
    check c.reason == ""
    check c.depInfoFiles == @["src/lib.rs"]
    check c.depInfoDigest.len == 64

  test "LLBC local file absent from the dep-info → fail-closed naming it":
    let root = subjectRootWith([("src/lib.rs", LibRs)])
    defer: removeDir(root)
    let dep = depInfoFor(root, ["src/other.rs"])
    let c = rustSubjectInputContract(baseDoc(), root, dep)
    check not c.ok
    check c.reason.contains("missing from the rustc dep-info")
    check c.reason.contains("src/lib.rs")

  test "dep-info subject input missing on disk → fail-closed naming it":
    let root = subjectRootWith([("src/lib.rs", LibRs)])
    defer: removeDir(root)
    let dep = depInfoFor(root, ["src/lib.rs", "src/ghost.rs"])
    let c = rustSubjectInputContract(baseDoc(), root, dep)
    check not c.ok
    check c.reason.contains("missing on disk")
    check c.reason.contains("src/ghost.rs")

  test "embedded content masquerading as subject source → fail-closed":
    var doc = baseDoc()
    doc{"translated"}{"files"}[0]{"name"} = parseJson(
      """{"Local": "/abs/src/lib.rs"}""")
    let root = subjectRootWith([("src/lib.rs", LibRs)])
    defer: removeDir(root)
    let dep = depInfoFor(root, ["src/lib.rs"])
    let c = rustSubjectInputContract(doc, root, dep)
    check not c.ok
    check c.reason.contains("masquerades")
    check c.reason.contains("src/lib.rs")

  test "dep-info absent → fail-closed (never a widened pass)":
    let root = subjectRootWith([("src/lib.rs", LibRs)])
    defer: removeDir(root)
    let c = rustSubjectInputContract(baseDoc(), root, root / "missing.d")
    check not c.ok
    check c.reason.contains("dep-info absent")

suite "rust subject input contract — Cargo identity digests (§10.2)":

  test "lockfileDigest/manifestDigest mirror the nimble.lock precedent " &
      "(golden values)":
    let root = subjectRootWith([("src/lib.rs", LibRs)])
    defer: removeDir(root)
    let c = rustSubjectInputContract(baseDoc(), root)
    check c.ok
    check c.cargo.lockfileDigest == GoldenLockDigest
    check c.cargo.manifestDigest == GoldenManifestDigest

  test "IDENTICAL DEFINITION cross-check: nimble.lock digest via " &
      "buildVerificationSubject == Cargo.lock digest via the contract":
    let root = subjectRootWith([("src/lib.rs", LibRs)])
    writeFile(root / "nimble.lock", LockContent)
    defer: removeDir(root)
    let subj = buildVerificationSubject(root)
    check subj.isOk()
    let c = rustSubjectInputContract(baseDoc(), root)
    check c.ok
    check subj.get().lockfileDigest == c.cargo.lockfileDigest
    check subj.get().lockfileDigest == GoldenLockDigest

# ─── Suite 3: .rs collection parameterization ───────────────────────────────

suite "collectSubjectFileSet parameterization — .rs lane, Nim lane unchanged":

  test "rustSourcePolicy collects exactly the .rs set (fallback lane)":
    let root = subjectRootWith([("a.rs", "1"), ("sub/b.rs", "2"),
                                ("c.nim", "3"), ("note.txt", "4"),
                                ("target/x.rs", "5")], withCargo = false)
    defer: removeDir(root)
    let rust = collectSubjectFileSet(root, rustSourcePolicy)
    check rust.usedFallback
    check rust.paths.sorted() == @["a.rs", "sub/b.rs"]
    check "target/x.rs" notin rust.paths

  test "default call == explicit nimSourcePolicy call (bit-identical A/B)":
    let root = subjectRootWith([("a.rs", "1"), ("c.nim", "3"),
                                ("d.nims", "4")], withCargo = false)
    defer: removeDir(root)
    let def = collectSubjectFileSet(root)
    let nim = collectSubjectFileSet(root, nimSourcePolicy)
    check def.usedFallback == nim.usedFallback
    check def.paths == nim.paths
    check def.paths.sorted() == @["c.nim", "d.nims"]

  test "rustSourcePolicy extension filtering":
    check isValidSourceNode("src/lib.rs", rustSourcePolicy)
    check not isValidSourceNode("src/lib.nim", rustSourcePolicy)
    check not isValidSourceNode("target/debug/x.rs", rustSourcePolicy)
    check not isValidSourceNode("src/lib.rs", nimSourcePolicy)
    check isValidSourceNode("src/lib.nim", nimSourcePolicy)

# ─── Suite 4: pipeline wiring — contract first, staleness classification ────

suite "rust pipeline — input contract wiring (subjectRoot)":

  test "stale subject → outcomeFailClosed with eaMismatch BEFORE any " &
      "differential (zero partial evidence)":
    let root = subjectRootWith([("src/lib.rs",
      "pub fn changed() {}\n")])
    defer: removeDir(root)
    let outcome = rustSubjectOutcome($baseDoc(), "synth_add",
      subjectRoot = root)
    check outcomeFailClosed(outcome)
    check not outcomeProceedToProof(outcome)
    check not outcomeOutOfScopeUnknown(outcome)
    check not outcome.producer.ok
    check outcome.agreement.verdict == eaMismatch
    check outcome.agreement.verdict != eaInternalError
    check outcome.agreement.nimDigest == ""
    check outcome.agreement.leanDigest == ""
    check outcome.agreement.reason.contains("not current")
    check outcome.agreement.reason.contains("content hash mismatch")

  test "Cargo.lock absent → same fail-closed staleness lane":
    let root = subjectRootWith([("src/lib.rs", LibRs)], withCargo = false)
    defer: removeDir(root)
    let outcome = rustSubjectOutcome($baseDoc(), "synth_add",
      subjectRoot = root)
    check outcomeFailClosed(outcome)
    check outcome.agreement.verdict == eaMismatch
    check outcome.agreement.reason.contains("Cargo.lock absent")

  test "table violation surfaces through the pipeline (pre-validation " &
      "prefix preserved)":
    var doc = baseDoc()
    doc{"translated"}{"files"}[0].delete("contents")
    let root = subjectRootWith([("src/lib.rs", LibRs)])
    defer: removeDir(root)
    let outcome = rustSubjectOutcome($doc, "synth_add", subjectRoot = root)
    check outcomeFailClosed(outcome)
    check outcome.agreement.verdict == eaMismatch
    check outcome.agreement.reason.contains(
      "LLBC files table pre-validation failed:")
    check outcome.agreement.reason.contains("'contents'")

  test "§6d outcome wiring: embeddedFiles survive a later contract " &
      "sub-check refusal (the file table itself passed)":
    var doc = baseDoc()
    doc{"translated"}{"files"}[0]{"name"} = parseJson(
        """{"Local": "/abs/out/private.rs"}""")
    let root = subjectRootWith([("src/lib.rs", LibRs)])
    defer: removeDir(root)
    let outcome = rustSubjectOutcome($doc, "synth_add", subjectRoot = root)
    check outcomeFailClosed(outcome)
    check outcome.agreement.verdict == eaMismatch
    check outcome.agreement.reason.contains("missing from the LLBC local table")
      # the masquerade fail-closed holds: the disk set keeps src/lib.rs, so
      # the source set cannot silently shrink
    check outcome.embeddedFiles.len == 1
    check outcome.embeddedFiles[0].index == 0
    check outcome.embeddedFiles[0].rawPath == "/abs/out/private.rs"
    check outcome.embeddedFiles[0].contentSha256 == sha256Hex(LibRs)
    check outcome.rejection.rule == ""
      # no files-table violation — the attestation stands, the verdict fails

  test "no subjectRoot → legacy behavior preserved (contract skipped)":
    let outcome = rustSubjectOutcome($baseDoc(), "synth_add")
    # producer runs (no contract): empty fun_decls → not-found rejection,
    # the PRE-EXISTING producer classification (eaInternalError axis)
    check not outcome.producer.ok
    check outcome.agreement.verdict == eaInternalError

if probePresent:
  suite "rust pipeline — input contract wiring (real probe)":
    let probeText = readFile(ProbePath)

    test "real measured binding: contract passes → outcome proceeds to " &
          "proof (contents byte-identical to disk, measured)":
      let outcome = rustSubjectOutcome(probeText, "add_u8",
        subjectRoot = ProbeDir)
      check outcomeProceedToProof(outcome)
      check not outcomeFailClosed(outcome)
      check outcome.agreement.verdict == eaAgree
      check outcome.agreement.nimDigest.len == 64

    test "real stale binding: modified subject copy → eaMismatch, no " &
        "differential":
      let root = subjectRootWith([("src/lib.rs",
        "pub fn add_u8(a: u8, b: u8) -> u8 { a.wrapping_add(b).wrapping_add(1) }\n")])
      defer: removeDir(root)
      let outcome = rustSubjectOutcome(probeText, "add_u8",
        subjectRoot = root)
      check outcomeFailClosed(outcome)
      check outcome.agreement.verdict == eaMismatch
      check outcome.agreement.nimDigest == ""
