## Rust subject u64 boundary-type acceptance (③ u64-scalar-2026-11-02).
##
## The committed fixture tests/fixtures/rust/axiom_u64_probe/ pins the ③
## slice (docs/spec/rust_certified_subset.md §1 v1.1 row — u64 is
## boundary-type-only): identity/params/returns/constants at width 64 are
## certified; full-width '+' is producer-rejected (the no-overflow
## obligation 'lhs + rhs < 2^64' is unrepresentable in the IR literal
## domain). The four fixtures:
##   A  POSITIVE  u64_echo         — extraction agreement eaAgree AND, when
##                                   rustc is available, a REAL Rust
##                                   execution at the u64 DOMAIN BOUNDARY
##                                   (x = 18446744073709551615 → the same
##                                   value echoes back: the property holds).
##   B  NEGATIVE  u64_seven_mutant — the spec result == 7 is VIOLATED by the
##                                   8 constant: a concrete counterexample
##                                   (0 → 8 ≠ 7) reproduced by the real
##                                   rustc harness → rvAgree.
##   D  CONSTANT  u64_seven        — the u64 constant operand decodes (the
##                                   decodeConstOperand U64 admission) and
##                                   the real run satisfies result == 7.
##   C  ADMITTED u64_add          — v1.2 RETIRED the wall: the producer
##                                   collapses full-width '+' to AddChecked,
##                                   the declared spec discharges via the
##                                   closed-form obligation
##                                   `lhs + rhs ≤ 2^64−1`, and the outcome
##                                   proceeds to proof (eaAgree). The retired
##                                   refusal reason survives only as the
##                                   greppable named constant.
##
## Phase 2-E/P7 linkage (the EXISTING issuer, armed): u64_echo mints the
## extraction-bounded certificate (kernel true, irHash == the differential
## nimDigest); the mutant's kernel decline is CONFIRMED — z3's refuting
## model replayed on the real rustc harness (counterexampleConfirmed ==
## true, no certificate). Zero-Footprint discipline: the fixture tree is
## part of the Axiom repo, so the subject is materialized UNCHANGED into a
## throwaway git repo (crate layout: Cargo.toml, Cargo.lock, src/lib.rs)
## and the ledger talks through the injectable LedgerTransport against an
## in-memory FakeBackend — no network, no real refs touched.
##
## PLACEMENT / LEVEL (recorded decision, same as
## rust_subject_three_cases_test.nim): integration-level, NOT an
## ax-spawning CLI feature test — the filename intentionally does NOT match
## the gateway lane's `*_feature_test.nim` collection glob
## (all_gateway_runner.nim:193), so it runs standalone
## (`nim c -r tests/gateway/rust_subject_u64_boundary_test.nim`).
##
## Environment gates (explicit skip, not failure): rustc absent → the
## replay suites skip; z3 absent → the confirmation suite skips. The probe
## crate is a committed in-repo fixture (see its README for provenance and
## the recorded regeneration command); there is no fixture-absent skip.

import std/[base64, json, os, osproc, sequtils, strutils, options, unittest]

import core/crypto/hash_kernel
import core/results
import core/trusted/axiom_ir
import core/trusted/axiom_ir_helpers
import core/trusted/rust_canonical          ## RustCanonical + rce*/rsk*/rrv*
import verification/counterexample_replay   ## rv* vocabulary + markers (shared)
import verification/evidence_ledger
import verification/extraction_agreement    ## ea* vocabulary
import verification/extraction_provenance
import verification/llbc_to_canonical       ## rce* vocabulary
import verification/ledger_side_ref
import verification/rust_ast_wire           ## canonical wire (byte compare)
import verification/rust_extraction_agreement  ## runRustExtractionAgreement (INV-4 direct)
import verification/rust_replay_adapter
import verification/rust_rust_pipeline

proc repoRoot(): string =
  ## tests/gateway/<file> -> project root (location-based, so the compiled
  ## binary resolves the fixture from any CWD — the pattern of
  ## hermetic_policy_feature_test.nim)
  absolutePath("../..", currentSourcePath().parentDir)

let
  RepoRoot = repoRoot()
  FixtureDir = RepoRoot / "tests" / "fixtures" / "rust" / "axiom_u64_probe"
  ProbePath = FixtureDir / "axiom_u64_probe.llbc"
  ProbeSourcePath = FixtureDir / "src" / "lib.rs"

let rustcPresent = findExe("rustc").len > 0
let z3Present = findExe("z3").len > 0 or
    fileExists(getHomeDir() / ".local" / "bin" / "z3")

if not rustcPresent:
  echo "SKIP: rustc not on PATH — replay suites will be skipped (explicit skip, not a failure)"
if not z3Present:
  echo "SKIP: z3 not found — the counterexample-confirmation suite (P7) " &
    "skips (explicit skip, not a failure)"

let probeText = readFile(ProbePath)

func observedValue(output: string): string =
  ## The value the harness echoed between the shared replay markers.
  var inBlock = false
  for line in output.splitLines():
    let t = line.strip()
    if t == ReplayBeginMarker:
      inBlock = true
    elif t == ReplayEndMarker:
      if inBlock: return ""
    elif inBlock and t.len > 0:
      return t
  ""

proc materializeProbeSubject(dirName: string): string =
  ## The replay adapter binds subject identity through the adapter's
  ## read-only git queries and FAILS CLOSED on an unbindable root, and the
  ## fixture tree is part of the Axiom repo (it must never be written, nor
  ## bound to Axiom's own git identity) — so the fixture's REAL content is
  ## copied UNCHANGED into a throwaway git repo mirroring the crate layout
  ## (Cargo.toml, Cargo.lock, src/lib.rs — the Phase 1-A input contract
  ## requires the Cargo crate identity for the armed provenance stage).
  let root = getTempDir() / dirName
  removeDir(root)
  createDir(root / "src")
  copyFile(ProbeSourcePath, root / "src" / "lib.rs")
  copyFile(FixtureDir / "Cargo.toml", root / "Cargo.toml")
  copyFile(FixtureDir / "Cargo.lock", root / "Cargo.lock")
  discard execCmdEx("git -C \"" & root & "\" init -q")
  discard execCmdEx("git -C \"" & root & "\" add -A")
  discard execCmdEx("git -C \"" & root &
    "\" -c user.name=ax -c user.email=ax@test commit -q -m init")
  root

proc issuanceCertDir(name: string): string =
  result = getTempDir() / ("axiom_u64_iss_" & name & "_" &
    $getCurrentProcessId())
  removeDir(result)
  createDir(result)

proc countCertFiles(dir: string): int =
  for p in walkPattern(dir / "*.json"):
    inc result

let bv64 = irTypeBitVec64()
## The specs under test (the closed post-condition grammar, same shapes as
## tests/fixtures/rust/axiom_u64_probe/axiom.specs.json):
##   u64_echo        — result == x        (identity at the boundary width)
##   u64_seven(_mut) — result == 7        (the constant row; the mutant's 8
##                                        falsifies it)
proc specEcho(): IRExpr =
  irEq(irVar("result", bv64), irVar("x", bv64))

proc specSeven(): IRExpr =
  irEq(irVar("result", bv64), irLit(7))

# ---------------------------------------------------------------------------
# Fake ledger backend (in-memory git object store; proven in
# tests/gateway/rust_subject_provenance_issuance_test.nim and
# tests/unit/test_extraction_provenance.nim).
# ---------------------------------------------------------------------------

type
  EvidenceEntry = object
    path: string
    content: string
    sha: string

  FakeBackend = ref object
    tip: string
    entries: seq[EvidenceEntry]
    counter: int
    pendingSha: string
    pendingPath: string
    pendingContent: string

proc fakeSha(b: FakeBackend; seed: string): string =
  inc b.counter
  sha256Hex(seed & ":" & $b.counter & ":" & $b.tip)

proc makeBackend(b: FakeBackend): LedgerTransport =
  var fetch: JsonFetcher = proc(url: string): Result[JsonNode, string] {.raises: [CatchableError, OSError, Exception].} =
    if url.contains("/git/commits/"):
      let commitSha = url[(url.rfind("/") + 1) .. ^1]
      return ok(%*{"sha": commitSha, "tree": {"sha": b.fakeSha("tree-lookup")}})
    if url.contains("/git/trees/"):
      var entries = newJArray()
      for e in b.entries:
        entries.add(%*{"path": e.path, "type": "blob", "sha": e.sha})
      return ok(%*{"tree": entries})
    if url.contains("/git/blobs/"):
      let sha = url[(url.rfind("/") + 1) .. ^1]
      for e in b.entries:
        if e.sha == sha:
          return ok(%*{"content": encode(e.content), "encoding": "base64"})
      return err("fake fetch: unknown blob " & sha)
    err("fake fetch: unexpected " & url)
  var post: JsonPoster = proc(url: string; body: string): Result[JsonNode, string] {.raises: [CatchableError, OSError, Exception].} =
    if url.contains("/git/blobs"):
      b.pendingContent = parseJson(body).getOrDefault("content").getStr("")
      b.pendingSha = b.fakeSha("blob:" & b.pendingContent)
      return ok(%*{"sha": b.pendingSha})
    if url.contains("/git/trees"):
      let treeEntry = parseJson(body){"tree"}[0]
      b.pendingPath = treeEntry.getOrDefault("path").getStr("")
      return ok(%*{"sha": b.fakeSha("tree")})
    if url.contains("/git/commits"):
      return ok(%*{"sha": b.fakeSha("commit")})
    if url.contains("/git/refs"):
      return ok(%*{"sha": b.fakeSha("ref")})
    err("fake post: unexpected " & url)
  var patch: JsonPatcher = proc(url: string; body: string): Result[JsonNode, string] {.raises: [CatchableError, OSError, Exception].} =
    let newSha = parseJson(body).getOrDefault("sha").getStr("")
    b.entries.add(EvidenceEntry(path: b.pendingPath, content: b.pendingContent,
                                sha: b.pendingSha))
    b.tip = newSha
    ok(%*{"object": {"type": "commit", "sha": newSha}})
  var tip: LedgerTipFetcher = proc(repo: string): Result[string, string] {.raises: [CatchableError, OSError, Exception].} =
    ok(b.tip)
  LedgerTransport(fetch: fetch, post: post, patch: patch, tip: tip)

# ── Case A: POSITIVE u64_echo (boundary identity) ───────────────────────────

suite "rust_subject u64 boundary — POSITIVE u64_echo (real probe)":

  test "producer accepts; outcome is eaAgree at width 64 — NOT UNKNOWN":
    let produced = rustSubjectToCanonical(probeText, "u64_echo")
    check produced.ok
    check produced.error == rceNone
    let outcome = rustSubjectOutcome(probeText, "u64_echo")
    check outcomeProceedToProof(outcome)
    check not outcomeOutOfScopeUnknown(outcome)
    check outcome.agreement.verdict == eaAgree
    check outcome.agreement.nimDigest.len == 64
    check outcome.agreement.nimDigest == outcome.agreement.leanDigest

  if rustcPresent:
    test "real Rust execution satisfies result == x in the replayable " &
        "domain (5 → 5), AND the full u64 domain is replayable since v1.2: " &
        "the 2^64-1 boundary literal observes exactly (parseConcreteLiteral " &
        "accumulates over the full unsigned range — no silent wraparound)":
      let repo = materializeProbeSubject("axiom_u64_subject_echo")
      let rec = runRustCounterexampleReplay(RustReplayConfig(
        subjectRepoRoot: repo,
        subjectModulePath: repo / "src" / "lib.rs",
        funcName: "u64_echo",
        paramNames: @["x"],
        inputLiterals: @["5"],
        postconditions: @[specEcho()]))
      check rec.verdict != rvUnavailable     # the run happened — NOT UNKNOWN
      check rec.exitCode == 0
      # Spec HOLDS on the observed result (rvDisagree + the holds
      # diagnostic = the positive's success-shaped observation).
      check rec.verdict == rvDisagree
      check rec.diagnostics ==
        "property holds on observed result — replay disagrees with solver model"
      check observedValue(rec.observedOutput) == "5"
      # The u64 DOMAIN boundary literal (2^64-1) is INSIDE the replayable
      # concrete domain since the two-part literal form (v1.2): the replay
      # runs the real subject at the exact boundary and the identity holds
      # on the observed result — no refusal, no wraparound, no silent
      # truncation.
      let boundary = runRustCounterexampleReplay(RustReplayConfig(
        subjectRepoRoot: repo,
        subjectModulePath: repo / "src" / "lib.rs",
        funcName: "u64_echo",
        paramNames: @["x"],
        inputLiterals: @["18446744073709551615"],
        postconditions: @[specEcho()]))
      check boundary.verdict == rvDisagree
      check boundary.diagnostics ==
        "property holds on observed result — replay disagrees with solver model"
      check observedValue(boundary.observedOutput) == "18446744073709551615"

# ── Case B: NEGATIVE u64_seven_mutant ───────────────────────────────────────

suite "rust_subject u64 boundary — NEGATIVE u64_seven_mutant (real probe)":

  test "mutant canonical differs from u64_seven (wire bytes — the 8 vs 7 " &
      "constant operand)":
    let seven = rustSubjectToCanonical(probeText, "u64_seven")
    let mut = rustSubjectToCanonical(probeText, "u64_seven_mutant")
    check seven.ok and mut.ok
    let sevenWire = serializeCanonicalWire(seven.canonical)
    let mutWire = serializeCanonicalWire(mut.canonical)
    check sevenWire.ok and mutWire.ok
    check mutWire.bytes != sevenWire.bytes

  test "extraction of the mutant is sound (eaAgree) — the SPEC is what " &
      "fails, not the extraction":
    let outcome = rustSubjectOutcome(probeText, "u64_seven_mutant")
    check outcomeProceedToProof(outcome)
    check outcome.agreement.verdict == eaAgree

  if rustcPresent:
    test "concrete counterexample (0 → 8 ≠ 7) reproduced by rustc → " &
        "rvAgree; no spec-satisfying observation is issued":
      let repo = materializeProbeSubject("axiom_u64_subject_mut")
      let rec = runRustCounterexampleReplay(RustReplayConfig(
        subjectRepoRoot: repo,
        subjectModulePath: repo / "src" / "lib.rs",
        funcName: "u64_seven_mutant",
        paramNames: @["_x"],
        inputLiterals: @["0"],
        postconditions: @[specSeven()]))
      check rec.exitCode == 0
      check observedValue(rec.observedOutput) == "8"   # spec says 7
      # The violation is REPRODUCED by the real toolchain: rvAgree — the
      # adapter issued a violation record, nothing equivalent to the
      # positive's "property holds" observation exists for the mutant.
      check rec.verdict == rvAgree
      check rec.diagnostics.len == 0

# ── Case D: CONSTANT u64_seven ──────────────────────────────────────────────

suite "rust_subject u64 boundary — CONSTANT u64_seven (real probe)":

  test "the u64 constant operand decodes on BOTH differential legs " &
      "(eaAgree — the Lean leg carries the same 7)":
    let outcome = rustSubjectOutcome(probeText, "u64_seven")
    check outcomeProceedToProof(outcome)
    check outcome.agreement.verdict == eaAgree
    check outcome.agreement.nimDigest == outcome.agreement.leanDigest

  if rustcPresent:
    test "real Rust execution satisfies result == 7 (0 → 7)":
      let repo = materializeProbeSubject("axiom_u64_subject_seven")
      let rec = runRustCounterexampleReplay(RustReplayConfig(
        subjectRepoRoot: repo,
        subjectModulePath: repo / "src" / "lib.rs",
        funcName: "u64_seven",
        paramNames: @["_x"],
        inputLiterals: @["0"],
        postconditions: @[specSeven()]))
      check rec.exitCode == 0
      check rec.verdict == rvDisagree
      check observedValue(rec.observedOutput) == "7"

# ── Case C: ADMITTED u64_add (v1.2 wall retirement) ─────────────────────────

suite "rust_subject u64 boundary — ADMITTED u64_add (real probe)":

  test "the producer ACCEPTS full-width '+' (v1.2): the body collapses to " &
      "AddChecked and the retired refusal reason stays greppable only as " &
      "the named constant":
    let produced = rustSubjectToCanonical(probeText, "u64_add")
    check produced.ok
    check produced.error == rceNone
    check validateRustCanonical(produced.canonical) == rceNone
    var addCheckedSeen = false
    for s in produced.canonical.body:
      if s.kind == rskAssign and s.rvalue.kind == rrvAddChecked:
        addCheckedSeen = true
    check addCheckedSeen
    check retiredWidth64WallReason.contains("full-width '+' outside the closed v1 set")

  test "outcome proceeds to proof (declared spec) — eaAgree, NOT " &
      "out-of-scope unknown, NOT an internal crash":
    let outcome = rustSubjectOutcome(probeText, "u64_add")
    check outcomeProceedToProof(outcome)
    check not outcomeOutOfScopeUnknown(outcome)
    check outcome.agreement.verdict == eaAgree
    check outcome.agreement.nimDigest.len == 64
    check outcome.agreement.nimDigest == outcome.agreement.leanDigest

# ── Phase 2-E: issuance linkage (the EXISTING issuer, unarmed) ──────────────

suite "rust_subject u64 boundary — Phase 2-E issuance linkage (real probe)":

  test "정상 u64_echo: the EXISTING issuer mints the extraction-bounded cert " &
      "at width 64":
    let repo = materializeProbeSubject("axiom_u64_subject_iss_pos")
    let certDir = issuanceCertDir("pos")
    let rec = rustSubjectIssuance(
      probeText, "u64_echo", specEcho(), certDir,
      repo / "src" / "lib.rs", readFile(repo / "src" / "lib.rs"))
    check rec.attempted
    check rec.issued
    check rec.blockStage == ""
    check rec.irHash.len == 64
    check fileExists(rec.certPath)
    let cert = parseFile(rec.certPath)
    # kernel truth comes ONLY from the genuine KAA (bindReceipt path)
    check cert{"kernel"}.getBool() == true
    # the adopted extraction identity: irHash == the differential nimDigest
    let outcome = rustSubjectOutcome(probeText, "u64_echo")
    check cert{"irHash"}.getStr() == outcome.agreement.nimDigest
    # the proposition↔evidence binding is ON the certificate
    check cert{"leanProposition"}.getStr() == rec.proposition
    check cert{"leanSourceHash"}.getStr() == sha256Hex(rec.leanSource)
    check cert{"propositionHash"}.getStr() == sha256Hex(rec.proposition)
    check cert{"obligationId"}.getStr() == rec.obligationId
    # the fixed reason lexicon; the Rust lane is Lean-only (no Z3 run)
    check cert{"status"}.getStr() == "certLeanVerified"
    check cert{"reason"}.getStr() == "uap-lean-verified"
    # self-contained durable evidence + Ed25519 attestation
    check cert{"evidenceId"}.getStr().len > 0
    check cert{"kaaDigest"}.getStr().len == 64
    check cert.hasKey("attestation")
    removeDir(certDir)

# ── Phase P7: armed-provenance counterexample confirmation (z3-gated) ───────

if z3Present:
  suite "rust_subject u64 boundary — declared-lane counterexample " &
      "confirmation (real probe, z3-gated)":

    test "P7: u64_seven_mutant + armed provenance → kernel decline CONFIRMED " &
        "by the replayed refuting model; NO certificate":
      let repo = materializeProbeSubject("axiom_u64_subject_confirmed")
      let certDir = issuanceCertDir("confirmed")
      let backend = FakeBackend(tip: "", entries: @[], counter: 0)
      let rec = rustSubjectIssuance(
        probeText, "u64_seven_mutant", specSeven(), certDir,
        repo / "src" / "lib.rs", readFile(repo / "src" / "lib.rs"),
        subjectRoot = repo,
        llbcPath = ProbePath,
        extractionLedger = some(makeBackend(backend)),
        extractionLedgerRepo = "owner/repo")
      # The spec result == 7 is false for the mutant (it returns 8): the
      # FIRST blocking point is the kernel — and the decline is CONFIRMED,
      # not unconfirmed: z3's refuting candidate is replayed on the real
      # rustc harness and reproduces the violation (0 → 8 ≠ 7).
      check rec.attempted
      check not rec.issued
      check rec.blockStage == "kernel"
      check rec.blockSite.len > 0
      check rec.counterexampleConfirmed
      check rec.blockReason.contains("spec declined by kernel; " &
        "counterexample CONFIRMED")
      # the confirmed payload names the replayed input + the reproduced
      # violation (the replay adapter's own record folds — no bare model)
      check rec.confirmedPayload.len > 0
      check rec.confirmedPayload.anyIt(it.startsWith("input._x="))
      check rec.confirmedPayload.anyIt(it == "replay.verdict=rvAgree")
      # NOTHING was written — a confirmed violation mints no certificate.
      check countCertFiles(certDir) == 0
      removeDir(certDir)

    test "P7 control: u64_echo stays ISSUED with nothing to confirm " &
        "(counterexampleConfirmed false, empty payload)":
      let repo = materializeProbeSubject("axiom_u64_subject_ctrl")
      let certDir = issuanceCertDir("ctrl")
      let backend = FakeBackend(tip: "", entries: @[], counter: 0)
      let rec = rustSubjectIssuance(
        probeText, "u64_echo", specEcho(), certDir,
        repo / "src" / "lib.rs", readFile(repo / "src" / "lib.rs"),
        subjectRoot = repo,
        llbcPath = ProbePath,
        extractionLedger = some(makeBackend(backend)),
        extractionLedgerRepo = "owner/repo")
      check rec.attempted
      check rec.issued
      check rec.blockStage == ""
      check not rec.counterexampleConfirmed
      check rec.confirmedPayload.len == 0
      check fileExists(rec.certPath)
      removeDir(certDir)

# ── INV-4: the u64-domain literal differential (≥ 2^63, hand-built) ──────────

proc bigConstCanon(valueU64: uint64): RustCanonical =
  ## The hand-built probe shape `pub fn u64_big(x: u64) -> u64 { <const> }`.
  ## The constant rides the u64-domain two-part literal carrier — a value
  ## ≥ 2^63 is NOT representable in the signed `value` field (the disjoint
  ## domain split, rust_canonical.nim u64DomainLow), so no committed probe
  ## fixture can reach this arm: the differential is driven DIRECTLY here.
  RustCanonical(
    modulePath: "axiom_u64_probe",
    sourceIdentity: "src/lib.rs:1:0-2:1",
    funcName: "u64_big",
    returnPlace: "_0",
    failureMode: rfmNoneObserved,
    params: @[RustParam(name: "x", ty: rustU64Type())],
    retType: rustU64Type(),
    body: @[
      RustStmt(kind: rskAssign, dest: "_0",
               rvalue: RustRvalue(kind: rrvUse,
                                  operand: RustOperand(kind: ropConstant,
                                                       valueU64: valueU64,
                                                       ty: rustU64Type()))),
      RustStmt(kind: rskReturn)])

suite "rust_subject u64 boundary — INV-4 u64-domain literal differential (≥ 2^63)":

  test "2^63: the valueU64 constant agrees on BOTH differential legs " &
      "(eaAgree — the Lean domain arm the probe fixture cannot reach)":
    let canon = bigConstCanon(u64DomainLow)
    check validateRustCanonical(canon) == rceNone
    let verdict = runRustExtractionAgreement(canon)
    check verdict.verdict == eaAgree
    check verdict.reason == agreementVerdictReason(eaAgree)
    check verdict.nimDigest.len == 64
    check verdict.nimDigest == verdict.leanDigest

  test "2^64-1: the DOMAIN CEILING constant agrees on BOTH differential legs " &
      "(eaAgree — the full-range ceiling through the two-part form)":
    let canon = bigConstCanon(u64DomainHigh)
    check validateRustCanonical(canon) == rceNone
    let verdict = runRustExtractionAgreement(canon)
    check verdict.verdict == eaAgree
    check verdict.nimDigest.len == 64
    check verdict.nimDigest == verdict.leanDigest
