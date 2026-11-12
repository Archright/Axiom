## Rust subject three-case operational acceptance (feat/rust-subject-v1).
##
## The REAL Charon probe fixture tests/fixtures/rust/axiom_rust_probe/
## (measured 2026-10-12, charon 0.1.281 — committed in-repo with its LLBC,
## see the fixture README) carries exactly the three required cases; no
## fixture content is invented:
##   1. POSITIVE     add_u8        — extraction agreement eaAgree (the
##                                    INV-4 path is sound, proceed to
##                                    proof) AND, when rustc is available,
##                                    a REAL Rust execution that satisfies
##                                    the spec f(a,b)=a+b. Assert the
##                                    outcome is NOT UNKNOWN.
##   2. NEGATIVE     add_u8_mutant — the SAME spec f(a,b)=a+b is VIOLATED:
##                                    the mutant canonical differs from the
##                                    positive's, and a concrete
##                                    counterexample (5,3 → 9 ≠ 8) is
##                                    reproduced by the real rustc harness
##                                    → rvAgree. NOTHING equivalent to the
##                                    positive's spec-satisfying observation
##                                    is issued. SCOPE HONESTY: these
##                                    modules issue no seal/certificate at
##                                    all — the positive's only
##                                    success-shaped evidence is the
##                                    replay's rvDisagree + "property
##                                    holds" observation, and this suite
##                                    asserts that exact shape is ABSENT
##                                    for the mutant (the adapter issues
##                                    the violation record instead).
##   3. OUT OF SCOPE is_zero      — the producer rejects the lowered Switch
##                                    (outside the closed straight-line
##                                    grammar, docs/spec/llbc_quirks.md Q2)
##                                    → fail-closed UNKNOWN: NOT reported as
##                                    verified and NOT reported as an
##                                    internal crash.
##
## PLACEMENT / LEVEL (recorded decision): integration-level, NOT an
## `ax`-spawning CLI feature test — the Rust subject path has no ax CLI
## surface yet (this wiring is in-module), so the
## productization_start_vertical_slice_feature_test.nim spawn-ax pattern does
## not apply. The filename intentionally does NOT match the gateway lane's
## `*_feature_test.nim` collection glob (all_gateway_runner.nim:193), so it
## runs standalone (`nim c -d:release -r
## tests/gateway/rust_subject_three_cases_test.nim`) without distorting the
## landing lane until the path gains a CLI surface.
##
## Environment gates (explicit skip, not failure): rustc absent → only the
## replay suites skip. The probe crate is a committed in-repo fixture
## (tests/fixtures/rust/axiom_rust_probe/ — see its README for provenance
## and the recorded regeneration command); there is no fixture-absent skip.

import std/[json, os, osproc, strutils, unittest]

import core/crypto/hash_kernel
import core/trusted/axiom_ir
import core/trusted/axiom_ir_helpers
import core/trusted/rust_canonical          ## RustCanonical + rce*/rsk*/rrv*
import verification/counterexample_replay   ## rv* vocabulary + markers (shared)
import verification/extraction_agreement    ## ea* vocabulary
import verification/llbc_to_canonical       ## rce* vocabulary
import verification/rust_ast_wire           ## canonical wire (byte compare)
import verification/rust_replay_adapter
import verification/rust_rust_pipeline

proc repoRoot(): string =
  ## tests/gateway/<file> -> project root (location-based, so the compiled
  ## binary resolves the fixture from any CWD — the pattern of
  ## hermetic_policy_feature_test.nim)
  absolutePath("../..", currentSourcePath().parentDir)

let
  RepoRoot = repoRoot()
  ProbePath = RepoRoot / "tests" / "fixtures" / "rust" / "axiom_rust_probe" /
      "axiom_rust_probe.llbc"
  ProbeSourcePath = RepoRoot / "tests" / "fixtures" / "rust" /
      "axiom_rust_probe" / "src" / "lib.rs"

let rustcPresent = findExe("rustc").len > 0

if not rustcPresent:
  echo "SKIP: rustc not on PATH — replay suites will be skipped (explicit skip, not a failure)"

let probeText = readFile(ProbePath)

func countAddChecked(c: RustCanonical): int =
  for s in c.body:
    if s.kind == rskAssign and s.rvalue.kind == rrvAddChecked:
      inc result

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
  ## The replay adapter binds subject identity through git (rev-parse
  ## HEAD/tree + porcelain) against the materialized root itself, and the
  ## fixture tree is part of the Axiom repo (it must never be written, nor
  ## bound to Axiom's own git identity) — the fixture's REAL source is
  ## copied UNCHANGED into a throwaway git repo (Zero-Footprint Integrity).
  let root = getTempDir() / dirName
  removeDir(root)
  createDir(root)
  copyFile(ProbeSourcePath, root / "subject.rs")
  discard execCmdEx("git -C \"" & root & "\" init -q")
  discard execCmdEx("git -C \"" & root & "\" add -A")
  discard execCmdEx("git -C \"" & root &
    "\" -c user.name=ax -c user.email=ax@test commit -q -m init")
  root

let bv64 = irTypeBitVec64()
## The spec under test for both add functions: f(a,b) = a+b.
## (proc, not func: it reads the block-scoped `bv64` capture — the test
## files carry no purity pragma.)
proc specAddAdd(): IRExpr =
  irEq(irVar("result", bv64), irAdd(irVar("a", bv64), irVar("b", bv64)))

# ── Case 1: POSITIVE add_u8 ────────────────────────────────────────────────

suite "rust_subject three cases — POSITIVE add_u8 (real probe)":

  test "producer accepts; outcome is eaAgree — the path is NOT UNKNOWN":
    let produced = rustSubjectToCanonical(probeText, "add_u8")
    check produced.ok
    check produced.error == rceNone
    let outcome = rustSubjectOutcome(probeText, "add_u8")
    check outcomeProceedToProof(outcome)
    check not outcomeOutOfScopeUnknown(outcome)
    check not outcomeFailClosed(outcome)
    check outcome.agreement.verdict == eaAgree
    check outcome.agreement.nimDigest.len == 64
    check outcome.agreement.nimDigest == outcome.agreement.leanDigest

  if rustcPresent:
    test "real Rust execution satisfies the spec f(a,b)=a+b (2,3 → 5)":
      let repo = materializeProbeSubject("axiom_rust_subject_pos")
      let rec = runRustCounterexampleReplay(RustReplayConfig(
        subjectRepoRoot: repo,
        subjectModulePath: repo / "subject.rs",
        funcName: "add_u8",
        paramNames: @["a", "b"],
        inputLiterals: @["2", "3"],
        postconditions: @[specAddAdd()]))
      check rec.verdict != rvUnavailable     # the run happened — NOT UNKNOWN
      check rec.exitCode == 0
      # Spec HOLDS on the observed result (rvDisagree + the holds
      # diagnostic = the positive's success-shaped observation).
      check rec.verdict == rvDisagree
      check rec.diagnostics ==
        "property holds on observed result — replay disagrees with solver model"
      check observedValue(rec.observedOutput) == "5"

# ── Case 2: NEGATIVE add_u8_mutant ─────────────────────────────────────────

suite "rust_subject three cases — NEGATIVE add_u8_mutant (real probe)":

  test "mutant canonical differs from the positive canonical (wire bytes)":
    let pos = rustSubjectToCanonical(probeText, "add_u8")
    let mut = rustSubjectToCanonical(probeText, "add_u8_mutant")
    check pos.ok and mut.ok
    check countAddChecked(mut.canonical) == 2   # a+b+1 = two collapses
    check countAddChecked(pos.canonical) == 1
    let posWire = serializeCanonicalWire(pos.canonical)
    let mutWire = serializeCanonicalWire(mut.canonical)
    check posWire.ok and mutWire.ok
    check mutWire.bytes != posWire.bytes

  test "extraction of the mutant is sound (eaAgree) — the SPEC is what fails":
    let outcome = rustSubjectOutcome(probeText, "add_u8_mutant")
    check outcomeProceedToProof(outcome)

  if rustcPresent:
    test "concrete counterexample (5,3) reproduced by rustc → rvAgree; " &
        "no spec-satisfying observation is issued":
      let repo = materializeProbeSubject("axiom_rust_subject_neg")
      let rec = runRustCounterexampleReplay(RustReplayConfig(
        subjectRepoRoot: repo,
        subjectModulePath: repo / "subject.rs",
        funcName: "add_u8_mutant",
        paramNames: @["a", "b"],
        inputLiterals: @["5", "3"],
        postconditions: @[specAddAdd()]))
      check rec.exitCode == 0
      check observedValue(rec.observedOutput) == "9"   # spec says 8
      # The violation is REPRODUCED by the real toolchain: rvAgree. This
      # is the OPPOSITE of the positive's success shape — the adapter
      # issued a violation record, so nothing equivalent to the positive's
      # "property holds" observation exists for the mutant.
      check rec.verdict == rvAgree
      check rec.diagnostics.len == 0

# ── Case 3: OUT OF SCOPE is_zero ───────────────────────────────────────────

suite "rust_subject three cases — OUT OF SCOPE is_zero (real probe)":

  test "producer rejects the lowered Switch with rceUnsupportedGrammar":
    let produced = rustSubjectToCanonical(probeText, "is_zero")
    check not produced.ok
    check produced.error == rceUnsupportedGrammar
    check produced.reason.contains("Switch")

  test "outcome is fail-closed UNKNOWN — NOT verified, NOT an internal crash":
    let outcome = rustSubjectOutcome(probeText, "is_zero")
    check outcomeOutOfScopeUnknown(outcome)
    check not outcomeProceedToProof(outcome)
    check outcome.agreement.verdict == eaUnsupported
    check outcome.agreement.verdict != eaInternalError
    # No differential ever ran: zero partial evidence.
    check outcome.agreement.nimDigest == ""
    check outcome.agreement.leanDigest == ""

# ── Phase 2-E: issuance linkage — the EXISTING issuer (KAA → cert_writer) ─
#
# The well-formed case is driven through the existing issuance path
# (rustSubjectIssuance → closed-template render → canonicalLeanKernelCheck
# → bindReceipt → CanonicalLeanEvidence → writeCertificateFromUapResult
# with the extraction-bounded claim gate). The honest-failure protocol is
# asserted explicitly per case: the POSITIVE case mints (measured live —
# this environment resolves the pinned Lean toolchain and kernel); the
# NEGATIVE case is refused BY THE KERNEL (the falsified spec is exactly
# what omega declines to prove) and writes NOTHING; the OUT-OF-SCOPE case
# never attempts and writes NOTHING.

suite "rust_subject three cases — Phase 2-E issuance linkage (real probe)":

  proc issuanceCertDir(name: string): string =
    result = getTempDir() / ("axiom_rust_iss_" & name & "_" &
      $getCurrentProcessId())
    removeDir(result)
    createDir(result)

  proc countCertFiles(dir: string): int =
    for p in walkPattern(dir / "*.json"):
      inc result

  test "정상 add_u8: the EXISTING issuer mints the extraction-bounded cert":
    let repo = materializeProbeSubject("axiom_rust_subject_iss_pos")
    let certDir = issuanceCertDir("pos")
    let subjectSource = readFile(repo / "subject.rs")
    let rec = rustSubjectIssuance(
      probeText, "add_u8", specAddAdd(), certDir,
      repo / "subject.rs", subjectSource)
    # The full issuance succeeded in this environment — the recorded
    # outcome IS the success path (no blocking point to report).
    check rec.attempted
    check rec.issued
    check rec.blockStage == ""
    check rec.irHash.len == 64
    check fileExists(rec.certPath)
    let cert = parseFile(rec.certPath)
    # kernel truth comes ONLY from the genuine KAA (bindReceipt path)
    check cert["kernel"].getBool() == true
    # the adopted extraction identity: irHash == the differential nimDigest
    let outcome = rustSubjectOutcome(probeText, "add_u8")
    check outcome.agreement.verdict == eaAgree
    check cert["irHash"].getStr() == outcome.agreement.nimDigest
    check cert["irHash"].getStr() == rec.irHash
    # the proposition↔evidence binding is ON the certificate
    check cert["leanProposition"].getStr() == rec.proposition
    check cert["leanSourceHash"].getStr() == sha256Hex(rec.leanSource)
    check cert["propositionHash"].getStr() == sha256Hex(rec.proposition)
    check cert["obligationId"].getStr() == rec.obligationId
    # the fixed reason lexicon; the Rust lane is Lean-only (no Z3 run)
    check cert["status"].getStr() == "certLeanVerified"
    check cert["reason"].getStr() == "uap-lean-verified"
    # self-contained durable evidence + Ed25519 attestation
    check cert["evidenceId"].getStr().len > 0
    check cert["kaaDigest"].getStr().len == 64
    check cert.hasKey("attestation")
    removeDir(certDir)

  test "명세 위반 add_u8_mutant: the kernel refuses the falsified spec — " &
      "NO certificate":
    let repo = materializeProbeSubject("axiom_rust_subject_iss_neg")
    let certDir = issuanceCertDir("neg")
    let rec = rustSubjectIssuance(
      probeText, "add_u8_mutant", specAddAdd(), certDir,
      repo / "subject.rs", readFile(repo / "subject.rs"))
    # The extraction is sound (eaAgree) so the case ATTEMPTS issuance —
    # and the FIRST blocking point is the kernel itself: the spec
    # f(a,b)=a+b is false for the mutant and omega declines the goal.
    check rec.attempted
    check not rec.issued
    check rec.blockStage == "kernel"
    check rec.blockSite.len > 0
    check rec.blockReason.contains("canonicalLeanKernelCheck")
    check rec.blockReason.contains("omega could not prove the goal")
    check rec.irHash.len == 64
    # NOTHING was written — no success certificate exists for the mutant.
    check not fileExists(certDir / (rec.irHash & ".json"))
    check countCertFiles(certDir) == 0
    removeDir(certDir)

  test "범위 밖 is_zero: never attempts — fail-closed, NO certificate":
    let certDir = issuanceCertDir("oos")
    let rec = rustSubjectIssuance(
      probeText, "is_zero", specAddAdd(), certDir,
      "subject.rs", "pub fn is_zero(a: u8, b: u8) -> bool { a == 0 && b == 0 }")
    # the producer rejected the grammar BEFORE anything ran: no attempt,
    # no kernel, no evidence, no certificate.
    check not rec.attempted
    check not rec.issued
    check rec.blockStage == "producer"
    check rec.blockSite.len > 0
    check rec.blockReason.contains("out-of-scope subject grammar")
    check rec.irHash == ""
    check countCertFiles(certDir) == 0
    removeDir(certDir)
