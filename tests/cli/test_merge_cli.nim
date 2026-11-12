{.push raises: [CatchableError].}

## Unit tests for cli/merge_cli — MergeAdmissible pure predicate.
##
## Platform check evidence (required checks, workflow identity, verdict
## runs) is GitHub's merge-time authority (ruleset delegation, P12) and is
## NOT re-tested here. This file covers the Axiom product passes: snapshot
## presence, base freshness (Pass 0), trust surface, change graph, candidate
## binding, certificate continuity, rotation/closure adjudication, the
## dry-run exit contract (verdict → check conclusion) and the dry-run JSON
## shape.
##
## P12 RETAINED (re-affirmed 2026-10-21, ADR-0035 §1): the predicate
## deliberately does NOT collect check-runs, does NOT re-derive required
## status checks and does NOT re-verify producer identity. That is the
## platform's merge-time authority (repository ruleset required status
## checks + the org ruleset's sha-pinned required workflow); re-implementing
## it here would be a duplicate of a platform guarantee — and, per ADR-0025
## Amendment B, was removed on 2026-09-29 for exactly that reason. The four
## walls against re-introducing it are recorded in ADR-0035 §1.
##
## SSOT SPLIT (ADR-0035 §3 — three copies of one fact are not an SSOT):
##   * config/policy/merge_admission.json is the NORMATIVE machine-readable
##     SSOT — the required-check set and the recorded producer identities.
##   * src/cli/merge_cli.nim RequiredChecks / RequiredWorkflowIds are the
##     DERIVED source-level mirror of that policy (runtime consumers: none —
##     they declare identity, they do not enforce it). Since policy v1.19.0
##     (hybrid authority rotation) the RequiredWorkflowIds binding is
##     (job, workflowPath) — the path identity; the numeric workflow id
##     survives in the policy only as workflowIdObservation, an observed-at
##     record (repository-scoped ids are reassigned on repository
##     recreation).
##   * tools/merge_ruleset_drift_monitor.nim is the THREE-WAY checker
##     (policy ↔ constants ↔ live ruleset ↔ live producer) that keeps the
##     mirror honest; it is POST-HOC monitoring, never merge-time
##     enforcement.
## The tests below therefore assert the Axiom-side predicate passes; the
## policy↔mirror↔live agreement is asserted by
## tests/unit/test_merge_ruleset_drift_monitor.nim.
##
## All other CLI wiring is exercised implicitly via the
## planAxActions / action_interpreter_cli test suite.

import std/[strutils, unittest, options, sets, tables, base64, os]
import std/algorithm
import std/json

import cli/action_plan_cli
import cli/cli_types
import cli/merge_cli
import ci/rotation_pin_anchor_check
import core/policy/change_graph_facts
import core/policy/rotation_closure_facts
import core/results
import infrastructure/certificate_attestation
import verification/ledger_side_ref

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

const okCheck = CheckStatus(name: "admission-check", conclusion: "success")

# ---------------------------------------------------------------------------
# MergeAdmissionResult enum values are first-class
# ---------------------------------------------------------------------------

suite "MergeAdmissionResult — enum values":
  test "all four variants exist and are distinct":
    check mergeGo != mergeRebaseRequired
    check mergeGo != mergeChecksIncomplete
    check mergeGo != mergeAborted
    check mergeRebaseRequired != mergeChecksIncomplete
    check mergeRebaseRequired != mergeAborted
    check mergeChecksIncomplete != mergeAborted

# ---------------------------------------------------------------------------
# planAxActions routes "merge" to a CliAction
# ---------------------------------------------------------------------------

suite "planAxActions — ax merge subcommand":
  test "merge subcommand dispatches to cliCommandMerge":
    let actions = planAxActions(@["merge", "42"])
    var foundMerge = false
    for a in actions:
      if a.commandKind == cliCommandMerge: foundMerge = true
    check foundMerge

  test "merge --dry-run routes through planAxActions":
    let actions = planAxActions(@["merge", "42", "--dry-run"])
    var foundMerge = false
    for a in actions:
      if a.commandKind == cliCommandMerge: foundMerge = true
    check foundMerge

  test "help entry for ax merge exists":
    var found = false
    for entry in axCommandHelpEntries():
      if entry.name == "ax merge": found = true
    check found

  test "unknown subcommand still falls through":
    let actions = planAxActions(@["merge"])
    check actions.len > 0

# ---------------------------------------------------------------------------
# Admission contract suite — v8 invariants (docs/spec/merge_admission_controller.md)
# ---------------------------------------------------------------------------

func factsWith(headSha: string; validations: seq[ValidationAttempt];
               hits: seq[TrustSurfaceHit] = @[]; complete: bool = true;
               fileCount: int = 3; graphValid: bool = true): AdmissionFacts {.raises: [].} =
  AdmissionFacts(
    headSha: headSha, baseSha: "current-main",
    validations: validations,
    prFileCount: fileCount, listingComplete: complete,
    trustSurfaceHits: hits,
    changeGraph: ChangeGraphStatus(valid: graphValid, nodeCount: 1),
    mergeableState: "clean")

let goValidations = @[
  ValidationAttempt(jobName: "admission-check", workflowId: 365692388, runId: 10, attempt: 1, conclusion: "success")]

# ---------------------------------------------------------------------------
# Rotation-fact fixtures (Pass 2.97) — the verdict fail-closes on UNSPECIFIED
# (DEBT#501 closed FIXED), so fixtures that test a NON-rotation pass attach a
# NORMAL adjudication (closure equal — the ordinary qualification) to keep
# their GO assertions scoped to the pass under test.
# ---------------------------------------------------------------------------

func normalRotation(): RotationAdjudication {.raises: [].} =
  var s = initHashSet[string]()
  s.incl("100644 blob a1\tci/checker.mk")
  # The candidate-delta leg (Amendment F): a fixture closure-neutral PR —
  # derived(M) == derived(B) → rqNormal, the ordinary qualification.
  adjudicateRotation(s, s, s, some(s), some(s), @[])

# ---------------------------------------------------------------------------
# Certificate-continuity (Pass 2.96) fixtures — Phase 5 INV-1 snapshot binding
# ---------------------------------------------------------------------------

proc certFacts(headSha: string; signatureOk: bool = true;
               certHeadSha: string = headSha;
               certBaseSha: string = "current-main";
               policyDigest: string = "pol-now"; scopeDigest: string = "sc-now";
               currentPolicyDigest: string = "pol-now";
               currentScopeDigest: string = "sc-now";
               certRequired: bool = true): AdmissionFacts {.raises: [].} =
  var f = factsWith(headSha, goValidations)
  f.certificate = some(CertificateContinuityFacts(
    subjectId: "ab12cd34ef56ab12cd34ef56ab12cd34ef56ab12cd34ef56ab12cd34ef56ab12",
    baseSha: certBaseSha, headSha: certHeadSha,
    headTreeDigest: "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcd",
    policyDigest: policyDigest, scopeDigest: scopeDigest,
    evidenceDigest: "fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210",
    signatureOk: signatureOk,
    currentPolicyDigest: currentPolicyDigest,
    currentScopeDigest: currentScopeDigest))
  f.certRequired = certRequired
  f.rotation = some(normalRotation())
  f

suite "Admission contract — certificate continuity (Pass 2.96)":
  test "certRequired=true with no certificate → DENY (NO_CERT)":
    var f = factsWith("h", goValidations)
    f.certRequired = true
    let rec = VerificationRecord(headSha: "h", baseSha: "current-main",
      requiredChecks: @[okCheck],
      admission: some(f))
    let o = MergeAdmissible(rec, "current-main")
    check o.result == mergeAborted
    check o.reasonCode == "NO_CERT"

  test "certificate with invalid signature → DENY (CERT_INVALID)":
    let rec = VerificationRecord(headSha: "h", baseSha: "current-main",
      requiredChecks: @[okCheck],
      admission: some(certFacts("h", signatureOk = false)))
    let o = MergeAdmissible(rec, "current-main")
    check o.result == mergeAborted
    check o.reasonCode == "CERT_INVALID"

  test "certificate bound to a different head → DENY (SUBJECT_MISMATCH)":
    let rec = VerificationRecord(headSha: "h", baseSha: "current-main",
      requiredChecks: @[okCheck],
      admission: some(certFacts("h", certHeadSha = "old-head-sha")))
    let o = MergeAdmissible(rec, "current-main")
    check o.result == mergeAborted
    check o.reasonCode == "SUBJECT_MISMATCH"

  test "certificate policyDigest drift → DENY (POLICY_MISMATCH)":
    let rec = VerificationRecord(headSha: "h", baseSha: "current-main",
      requiredChecks: @[okCheck],
      admission: some(certFacts("h", policyDigest = "pol-old")))
    let o = MergeAdmissible(rec, "current-main")
    check o.result == mergeAborted
    check o.reasonCode == "POLICY_MISMATCH"

  test "certificate scopeDigest drift → DENY (SCOPE_MISMATCH)":
    let rec = VerificationRecord(headSha: "h", baseSha: "current-main",
      requiredChecks: @[okCheck],
      admission: some(certFacts("h", scopeDigest = "scope-old")))
    let o = MergeAdmissible(rec, "current-main")
    check o.result == mergeAborted
    check o.reasonCode == "SCOPE_MISMATCH"

  test "bound certificate matching the environment → GO":
    let rec = VerificationRecord(headSha: "h", baseSha: "current-main",
      requiredChecks: @[okCheck],
      admission: some(certFacts("h")))
    check MergeAdmissible(rec, "current-main").result == mergeGo

suite "Admission contract — the certificate requirement is ON (flag-flip fixture)":
  ## The predicate reads `CertRequired` (src/cli/merge_cli.nim), NOT the
  ## certRequired field of config/policy/merge_admission.json — the policy entry
  ## was a mirror with no checker between it and the constant
  ## (tools/ci/merge_admission_cert_mirror_gate.nim closes the mirror half; it
  ## deliberately does NOT decide the value). These cases pin the VALUE from the
  ## predicate side so that flipping the constant fails here: the certificate
  ## requirement is an independent Trust Fact, not a temporary bootstrap that can
  ## be switched off without a failing test saying so.
  test "the effective constant is ON — CertRequired == true":
    check CertRequired == true

  test "the shipped constant is ON — collectAdmissionFacts defaults to it":
    var f = factsWith("h", goValidations)
    f.certRequired = CertRequired
    let rec = VerificationRecord(headSha: "h", baseSha: "current-main",
      requiredChecks: @[okCheck],
      admission: some(f))
    let o = MergeAdmissible(rec, "current-main")
    check o.result == mergeAborted
    check o.reasonCode == "NO_CERT"

  test "no certificate bound + certRequired=false → GO (the requirement is what denies)":
    ## The negative twin of the case above: it fixes what `certRequired=false`
    ## MEANS, so the deny above is attributable to the flag rather than to some
    ## unrelated missing fact. Without it a future flip could be dismissed as
    ## "the certificate was already optional".
    var f = factsWith("h", goValidations)
    f.certRequired = false
    f.certificate = none(CertificateContinuityFacts)
    f.rotation = some(normalRotation())
    let rec = VerificationRecord(headSha: "h", baseSha: "current-main",
      requiredChecks: @[okCheck],
      admission: some(f))
    check MergeAdmissible(rec, "current-main").result == mergeGo

# ---------------------------------------------------------------------------
# Vault-certificate continuity (Pass 2.96b) fixtures — proof-required
# admission contract §3/§4.3. The sibling of Pass 2.96: Option fact +
# required-flag, same mirror convention (VaultCertRequired const ↔ policy
# key ↔ this facts field), journal-string reason vocabulary, and the
# TRUST_SURFACE_MODIFIED manual-merge exception untouched (the combined
# trust-surface case below pins the precedence).
# ---------------------------------------------------------------------------

func vaultTarget(modulePath: string; functionName: string; irHash: string;
                 present: bool = true; match: bool = true): VaultCertTarget {.raises: [].} =
  VaultCertTarget(modulePath: modulePath, functionName: functionName, irHash: irHash,
    certPresent: present, irHashMatch: (if present: match else: false))

proc vaultFacts(headSha: string; targets: seq[VaultCertTarget];
                policyEpoch: string = "pol-epoch"; scopeEpoch: string = "scope-epoch";
                currentPolicy: string = "pol-epoch"; currentScope: string = "scope-epoch";
                vaultRequired: bool = true;
                hits: seq[TrustSurfaceHit] = @[]): AdmissionFacts {.raises: [].} =
  ## A Pass 2.96-satisfied + rotation-NORMAL snapshot with the vault fact
  ## bound, so the GO/deny assertions stay scoped to Pass 2.96b.
  var f = certFacts(headSha)
  f.vaultCert = some(VaultCertContinuityFacts(
    targets: targets, policyEpochDigest: policyEpoch, scopeEpochDigest: scopeEpoch,
    currentPolicyDigest: currentPolicy, currentScopeDigest: currentScope))
  f.vaultCertRequired = vaultRequired
  if hits.len > 0:
    f.trustSurfaceHits = hits
  f

suite "Admission contract — vault certificate continuity (Pass 2.96b)":
  test "required + bound targets all present and identity-matching → GO":
    let rec = VerificationRecord(headSha: "h", baseSha: "current-main",
      requiredChecks: @[okCheck],
      admission: some(vaultFacts("h", @[vaultTarget(
        "src/core/orchestrator/orchestrator_api.nim", "normalizeMaxWorkers",
        "c14243cdc6d5628d64cb11ff38a9b7cf5cd04a817c5ed28979cc1b0f28c24e39")])))
    let o = MergeAdmissible(rec, "current-main")
    check o.result == mergeGo
    check o.reasonCode == "GO"

  test "required + manifest target without a vault certificate → DENY (NO_CERT)":
    let rec = VerificationRecord(headSha: "h", baseSha: "current-main",
      requiredChecks: @[okCheck],
      admission: some(vaultFacts("h", @[vaultTarget(
        "src/core/orchestrator/orchestrator_api.nim", "normalizeMaxWorkers",
        "c14243cdc6d5628d64cb11ff38a9b7cf5cd04a817c5ed28979cc1b0f28c24e39",
        present = false)])))
    let o = MergeAdmissible(rec, "current-main")
    check o.result == mergeAborted
    check o.reasonCode == "NO_CERT"
    check o.reason.contains("Pass 2.96b")
    check o.reason.contains("normalizeMaxWorkers")

  test "required + vault cert identity mismatch → DENY (SUBJECT_MISMATCH)":
    let rec = VerificationRecord(headSha: "h", baseSha: "current-main",
      requiredChecks: @[okCheck],
      admission: some(vaultFacts("h", @[vaultTarget(
        "src/core/orchestrator/orchestrator_api.nim", "normalizeMaxWorkers",
        "c14243cdc6d5628d64cb11ff38a9b7cf5cd04a817c5ed28979cc1b0f28c24e39",
        match = false)])))
    let o = MergeAdmissible(rec, "current-main")
    check o.result == mergeAborted
    check o.reasonCode == "SUBJECT_MISMATCH"
    check o.reason.contains("Pass 2.96b")

  test "policy epoch drift → DENY (POLICY_MISMATCH)":
    let rec = VerificationRecord(headSha: "h", baseSha: "current-main",
      requiredChecks: @[okCheck],
      admission: some(vaultFacts("h", @[vaultTarget(
        "src/core/orchestrator/orchestrator_api.nim", "normalizeMaxWorkers",
        "c14243cdc6d5628d64cb11ff38a9b7cf5cd04a817c5ed28979cc1b0f28c24e39")],
        policyEpoch = "pol-at-b")))
    let o = MergeAdmissible(rec, "current-main")
    check o.result == mergeAborted
    check o.reasonCode == "POLICY_MISMATCH"
    check o.reason.contains("Pass 2.96b")

  test "scope epoch drift → DENY (SCOPE_MISMATCH)":
    let rec = VerificationRecord(headSha: "h", baseSha: "current-main",
      requiredChecks: @[okCheck],
      admission: some(vaultFacts("h", @[vaultTarget(
        "src/core/orchestrator/orchestrator_api.nim", "normalizeMaxWorkers",
        "c14243cdc6d5628d64cb11ff38a9b7cf5cd04a817c5ed28979cc1b0f28c24e39")],
        scopeEpoch = "scope-at-b")))
    let o = MergeAdmissible(rec, "current-main")
    check o.result == mergeAborted
    check o.reasonCode == "SCOPE_MISMATCH"
    check o.reason.contains("Pass 2.96b")

  test "first sorted target wins the deny (deterministic)":
    let rec = VerificationRecord(headSha: "h", baseSha: "current-main",
      requiredChecks: @[okCheck],
      admission: some(vaultFacts("h", @[
        vaultTarget("src/a.nim", "alphaFunc", "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          present = false),
        vaultTarget("src/b.nim", "betaFunc", "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
          match = false)])))
    let o = MergeAdmissible(rec, "current-main")
    check o.reasonCode == "NO_CERT"
    check o.reason.contains("alphaFunc")

  test "vaultCertRequired=false + failing fact → GO (the requirement is what denies)":
    let rec = VerificationRecord(headSha: "h", baseSha: "current-main",
      requiredChecks: @[okCheck],
      admission: some(vaultFacts("h", @[vaultTarget(
        "src/core/orchestrator/orchestrator_api.nim", "normalizeMaxWorkers",
        "c14243cdc6d5628d64cb11ff38a9b7cf5cd04a817c5ed28979cc1b0f28c24e39",
        present = false)], vaultRequired = false)))
    check MergeAdmissible(rec, "current-main").result == mergeGo

  test "required + fact none (no in-scope targets) → GO (recorded skip)":
    var f = certFacts("h")
    f.vaultCert = none(VaultCertContinuityFacts)
    f.vaultCertRequired = true
    let rec = VerificationRecord(headSha: "h", baseSha: "current-main",
      requiredChecks: @[okCheck],
      admission: some(f))
    check MergeAdmissible(rec, "current-main").reasonCode == "GO"

  test "COMBINED — trust-surface hit + vaultCertRequired + failing vault fact → TRUST_SURFACE_MODIFIED wins (exit 0)":
    ## Contract §3 HARD: the TRUST_SURFACE_MODIFIED manual-merge exception is
    ## untouched by Pass 2.96b — the trust-surface pass (2.7/2.8) precedes it,
    ## so a PR that both touches a trust-surface file and fails the vault
    ## demand routes to the manual path (exit 0), never to a vault deny.
    let rec = VerificationRecord(headSha: "h", baseSha: "current-main",
      requiredChecks: @[okCheck],
      admission: some(vaultFacts("h", @[vaultTarget(
        "src/core/orchestrator/orchestrator_api.nim", "normalizeMaxWorkers",
        "c14243cdc6d5628d64cb11ff38a9b7cf5cd04a817c5ed28979cc1b0f28c24e39",
        present = false)],
        hits = @[TrustSurfaceHit(path: "src/cli/merge_cli.nim", renamedFrom: "")])))
    let o = MergeAdmissible(rec, "current-main")
    check o.result == mergeAborted
    check o.reasonCode == "TRUST_SURFACE_MODIFIED"
    check dryRunExit(o) == 0

  test "Pass 0 outranks 2.96b (stale base still the deny with a failing vault fact)":
    var f = vaultFacts("h", @[vaultTarget(
      "src/core/orchestrator/orchestrator_api.nim", "normalizeMaxWorkers",
      "c14243cdc6d5628d64cb11ff38a9b7cf5cd04a817c5ed28979cc1b0f28c24e39",
      present = false)])
    f.certRequired = false
    let rec = VerificationRecord(headSha: "h", baseSha: "old-base",
      requiredChecks: @[okCheck],
      admission: some(f))
    check MergeAdmissible(rec, "current-main").reasonCode == "STALE_BASE"

  test "2.96b deny codes keep the fail-closed exit binding":
    for code in ["NO_CERT", "SUBJECT_MISMATCH", "POLICY_MISMATCH", "SCOPE_MISMATCH"]:
      check dryRunExit(MergeAdmissionOutcome(result: mergeAborted, reason: "",
                                             reasonCode: code)) == 1

  test "dry-run JSON marks the 2.96b state (bound targets / recorded skip)":
    let bound = buildDryRunJson(42, "h", "b",
      MergeAdmissionOutcome(result: mergeGo, reasonCode: "GO", reason: "all green"),
      none(RotationAdjudication), preflight = false,
      vaultCertRequired = true, vaultCertTargets = 2)
    check bound["vaultCert"]["required"].getBool == true
    check bound["vaultCert"]["targets"].getInt == 2

    let skipped = buildDryRunJson(42, "h", "b",
      MergeAdmissionOutcome(result: mergeGo, reasonCode: "GO", reason: "all green"),
      none(RotationAdjudication), preflight = false,
      vaultCertRequired = true, vaultCertTargets = -1)
    check skipped["vaultCert"]["required"].getBool == true
    check skipped["vaultCert"]["targets"].kind == JNull

    let off = buildDryRunJson(42, "h", "b",
      MergeAdmissionOutcome(result: mergeGo, reasonCode: "GO", reason: "all green"),
      none(RotationAdjudication))
    check off["vaultCert"]["required"].getBool == false

suite "Admission contract — the vault certificate requirement is ON (flag-flip fixture)":
  test "the effective constant is ON — VaultCertRequired == true":
    check VaultCertRequired == true

  test "the shipped collection fills the const":
    var f = factsWith("h", goValidations)
    f.vaultCertRequired = VaultCertRequired
    check f.vaultCertRequired == true

suite "Admission contract — missing facts never admit":
  test "admission = None → DENY (FACTS_MISSING)":
    let rec = VerificationRecord(headSha: "h", baseSha: "b",
      requiredChecks: @[okCheck],
      admission: none(AdmissionFacts))
    let outcome = MergeAdmissible(rec, "b")
    check outcome.result == mergeAborted
    check outcome.reasonCode == "FACTS_MISSING"

# ---------------------------------------------------------------------------
# Base freshness (Pass 0) — Axiom decides freshness at evaluation time;
# GitHub re-binds the same fact at merge time (strict / queue invalidation).
# ---------------------------------------------------------------------------

suite "Admission contract — base freshness (Pass 0)":
  test "verified base != current main → DENY (STALE_BASE)":
    let rec = VerificationRecord(headSha: "h", baseSha: "abcdef0123456789",
      requiredChecks: @[okCheck],
      admission: some(factsWith("h", goValidations)))
    let outcome = MergeAdmissible(rec, "fedcba9876543210")
    check outcome.result == mergeAborted
    check outcome.reasonCode == "STALE_BASE"
    check outcome.reason.contains("abcdef012345")
    check outcome.reason.contains("fedcba987654")
    check outcome.reason.contains("freshness")

  test "verified base == current main → GO":
    var f = factsWith("h", goValidations)
    f.rotation = some(normalRotation())
    let rec = VerificationRecord(headSha: "h", baseSha: "abcdef0123456789",
      requiredChecks: @[okCheck],
      admission: some(f))
    check MergeAdmissible(rec, "abcdef0123456789").result == mergeGo

  test "unrecorded base → DENY (BASE_UNRECORDED — never admit on missing facts)":
    let rec = VerificationRecord(headSha: "h", baseSha: "",
      requiredChecks: @[okCheck],
      admission: some(factsWith("h", goValidations)))
    let outcome = MergeAdmissible(rec, "abcdef0123456789")
    check outcome.result == mergeAborted
    check outcome.reasonCode == "BASE_UNRECORDED"

  test "unrecorded base outranks the later passes (freshness is evaluated early)":
    # Trust surface would deny too — the verdict must still be the freshness
    # one, i.e. Pass 0 precedes the product passes.
    var hitFacts = factsWith("h", goValidations)
    hitFacts.trustSurfaceHits = @[TrustSurfaceHit(path: ".github/workflows/ci.yml",
                                                  renamedFrom: "")]
    let hit = hitFacts
    let rec = VerificationRecord(headSha: "h", baseSha: "",
      requiredChecks: @[okCheck], admission: some(hit))
    check MergeAdmissible(rec, "abcdef0123456789").reasonCode == "BASE_UNRECORDED"

# ---------------------------------------------------------------------------
# Freshness anchor — the EVENT-FROZEN base, not the live PR API `base.sha`.
# `AXIOM_MAIN_SHA` (`github.event.pull_request.base.sha ||
# github.event.merge_group.base_sha`) is the base the run's evidence was
# produced against and the base the certificate was minted against. Binding
# the live `pulls/N` value instead made every landing PR invalidate every
# other queued PR with a STALE_BASE false deny (~247 min of wasted CI
# measured 2026-10-04). The anchor is therefore the same declared value on
# both sides of Pass 0, and the certificate's construction base is checked
# against it so the actuator's (base, head) ledger lookup resolves the very
# certificate admission approved.
# ---------------------------------------------------------------------------

const QueueBase = "1111111111111111111111111111111111111111"
const MovedMain = "2222222222222222222222222222222222222222"

suite "Admission contract — freshness anchor (event-frozen base)":
  test "queue-event anchor (merge_group base_sha) == recorded base → GO":
    let rec = VerificationRecord(headSha: "h", baseSha: QueueBase,
      requiredChecks: @[okCheck],
      admission: some(certFacts("h", certBaseSha = QueueBase)))
    let o = MergeAdmissible(rec, QueueBase)
    check o.result == mergeGo
    check o.reasonCode == "GO"

  test "genuinely stale anchor (recorded base != declared main) → DENY (STALE_BASE)":
    # The queue-path identity does NOT make the deny unreachable: a declared
    # main that differs from the recorded anchor (re-verification after the
    # base moved) still denies.
    let rec = VerificationRecord(headSha: "h", baseSha: QueueBase,
      requiredChecks: @[okCheck],
      admission: some(certFacts("h", certBaseSha = QueueBase)))
    let o = MergeAdmissible(rec, MovedMain)
    check o.result == mergeAborted
    check o.reasonCode == "STALE_BASE"

  test "unrecorded anchor → DENY (BASE_UNRECORDED kept for callers with no anchor)":
    let rec = VerificationRecord(headSha: "h", baseSha: "",
      requiredChecks: @[okCheck],
      admission: some(factsWith("h", goValidations)))
    check MergeAdmissible(rec, MovedMain).reasonCode == "BASE_UNRECORDED"

suite "Admission contract — ledger cert key alignment (base, head) PAIR":
  test "certified base == anchor → GO (loadLedgerCertFor's pair key resolves)":
    # The actuator keys the ledger on (baseSha, headSha). Admission approves a
    # certificate only when its certified base IS the anchor the actuator will
    # look it up with, so an approved admission never reaches the post-merge
    # continuity check with an unresolvable certificate.
    let rec = VerificationRecord(headSha: "h", baseSha: QueueBase,
      requiredChecks: @[okCheck],
      admission: some(certFacts("h", certBaseSha = QueueBase)))
    check MergeAdmissible(rec, QueueBase).result == mergeGo

  test "certified base != anchor → DENY (SUBJECT_MISMATCH — pair key would miss)":
    let rec = VerificationRecord(headSha: "h", baseSha: QueueBase,
      requiredChecks: @[okCheck],
      admission: some(certFacts("h", certBaseSha = MovedMain)))
    let o = MergeAdmissible(rec, QueueBase)
    check o.result == mergeAborted
    check o.reasonCode == "SUBJECT_MISMATCH"
    check o.reason.contains("certified baseSha")
    check o.reason.contains("admission base")

  test "head drift still outranks the base check (INV-1 head is checked first)":
    let rec = VerificationRecord(headSha: "h", baseSha: QueueBase,
      requiredChecks: @[okCheck],
      admission: some(certFacts("h", certHeadSha = "old-head-sha", certBaseSha = QueueBase)))
    check MergeAdmissible(rec, QueueBase).reasonCode == "SUBJECT_MISMATCH"

suite "Dry-run exit contract (verdict → check conclusion)":
  test "GO → exit 0":
    check dryRunExit(MergeAdmissionOutcome(result: mergeGo, reason: "", reasonCode: "GO")) == 0

  test "NOT-ADMIT → exit 1 (fail-closed binding)":
    for code in ["STALE_BASE", "BASE_UNRECORDED", "FACTS_MISSING",
                 "GRAPH_INVALID", "BINDING_MISMATCH",
                 "NO_CERT", "CERT_INVALID", "SUBJECT_MISMATCH",
                 "ROT_UNSPECIFIED"]:
      check dryRunExit(MergeAdmissionOutcome(result: mergeAborted, reason: "",
                                             reasonCode: code)) == 1

  test "TRUST_SURFACE_MODIFIED → exit 0 (policy: architect manual-merge path — the check must not seal it)":
    check dryRunExit(MergeAdmissionOutcome(result: mergeAborted, reason: "",
                                           reasonCode: "TRUST_SURFACE_MODIFIED")) == 0

  test "dry-run exit equals the predicate verdict for the stale case":
    let rec = VerificationRecord(headSha: "h", baseSha: "old-base",
      requiredChecks: @[okCheck],
      admission: some(factsWith("h", goValidations)))
    let outcome = MergeAdmissible(rec, "new-main")
    check dryRunExit(outcome) == 1
    check outcome.reasonCode == "STALE_BASE"

suite "Admission contract — trust surface":
  test "trust-surface file modified → DENY (TRUST_SURFACE_MODIFIED)":
    var hitFacts = factsWith("h", goValidations)
    hitFacts.rotation = some(normalRotation())   # machine pin-anchor facts present (landing venue always supplies them)
    hitFacts.trustSurfaceHits = @[TrustSurfaceHit(path: ".github/workflows/ci.yml",
                                                  renamedFrom: "")]
    let hit = hitFacts
    let rec = VerificationRecord(headSha: "h", baseSha: "b",
      requiredChecks: @[okCheck],
      admission: some(hit))
    let outcome = MergeAdmissible(rec, "b")
    check outcome.result == mergeAborted
    check outcome.reasonCode == "TRUST_SURFACE_MODIFIED"

  test "rename FROM a trust-surface path → DENY (rename detection)":
    var renamedFacts = factsWith("h", goValidations)
    renamedFacts.rotation = some(normalRotation())   # same: ④ holds → the exit-0 manual route
    renamedFacts.trustSurfaceHits = @[TrustSurfaceHit(path: "moved/elsewhere.yml",
                                                      renamedFrom: ".github/workflows/ci.yml")]
    let renamed = renamedFacts
    let rec = VerificationRecord(headSha: "h", baseSha: "b",
      requiredChecks: @[okCheck],
      admission: some(renamed))
    let outcome = MergeAdmissible(rec, "b")
    check outcome.result == mergeAborted
    check outcome.reasonCode == "TRUST_SURFACE_MODIFIED"
    check outcome.reason.contains("renamed")

  test "incomplete PR-files listing (pagination not clean / cap reached) → DENY":
    var incFacts = factsWith("h", goValidations)
    incFacts.listingComplete = false
    incFacts.prFileCount = 3000
    let incomplete = incFacts
    let rec = VerificationRecord(headSha: "h", baseSha: "b",
      requiredChecks: @[okCheck],
      admission: some(incomplete))
    let outcome = MergeAdmissible(rec, "b")
    check outcome.result == mergeAborted
    check outcome.reasonCode == "TRUST_SURFACE_INCOMPLETE"

suite "Admission contract — change graph":
  test "invalid change graph → DENY (GRAPH_INVALID)":
    var badFacts = factsWith("h", goValidations)
    badFacts.changeGraph = ChangeGraphStatus(valid: false, nodeCount: 1)
    let badGraph = badFacts
    let rec = VerificationRecord(headSha: "h", baseSha: "b",
      requiredChecks: @[okCheck],
      admission: some(badGraph))
    let outcome = MergeAdmissible(rec, "b")
    check outcome.result == mergeAborted
    check outcome.reasonCode == "GRAPH_INVALID"

suite "Admission contract — snapshot idempotency":
  test "same snapshot evaluated twice → identical verdict and reason code":
    let rec = VerificationRecord(headSha: "h", baseSha: "b",
      requiredChecks: @[okCheck],
      admission: some(factsWith("h", goValidations)))
    let o1 = MergeAdmissible(rec, "b")
    let o2 = MergeAdmissible(rec, "b")
    check o1.result == o2.result
    check o1.reasonCode == o2.reasonCode
    check o1.reason == o2.reason

  test "complete valid facts → GO":
    var f = factsWith("h", goValidations)
    f.rotation = some(normalRotation())
    let rec = VerificationRecord(headSha: "h", baseSha: "b",
      requiredChecks: @[okCheck],
      admission: some(f))
    check MergeAdmissible(rec, "b").result == mergeGo

suite "Admission contract — glob matching":
  test "pathMatchesGlob directory pattern matches nested paths":
    check pathMatchesGlob(".github/actions/setup-axiom-toolchain/action.yml",
                          ".github/actions/setup-axiom-toolchain/**")
    check pathMatchesGlob(".github/actions/setup-axiom-toolchain", ".github/actions/setup-axiom-toolchain/**")
    check not pathMatchesGlob(".github/workflows/ci.yml", ".github/actions/setup-axiom-toolchain/**")
    check pathMatchesGlob(".github/workflows/ci.yml", ".github/workflows/ci.yml")

  test "trustSurfaceMatch detects rename source (tombstone path)":
    let hit = trustSurfaceMatch("new-location.yml",
                                ".github/workflows/readiness_start.yml",
                                TrustSurfaceTombstones)
    check hit.isSome
    check hit.get.renamedFrom == ".github/workflows/readiness_start.yml"
    let clean = trustSurfaceMatch("src/main.nim", "", TrustSurfaceTombstones)
    check clean.isNone

  test "trustSurface covers the Rust-subject TCB register (policy SSOT v1.14.0)":
    let root = currentSourcePath().parentDir().parentDir().parentDir()
    let loaded = loadTrustSurface(root / "config" / "policy" / "merge_admission.json")
    check loaded.isOk
    check "src/core/trusted/trust_boundary.nim" in loaded.get
    check "src/cli/merge_cli.nim" in loaded.get
    check trustSurfaceMatch("src/core/trusted/trust_boundary.nim", "",
                            loaded.get).isSome

  # U1 observation suite removed with the required-workflow verdict pass
  # (AXIOM_ADMISSION_OBSERVATION machinery deleted — P12 delegation).
  # (AXIOM_ADMISSION_OBSERVATION machinery deleted — P12 delegation).

# ---------------------------------------------------------------------------
# Trust surface — policy SSOT single-source (B-anchored)
# ---------------------------------------------------------------------------
## The runtime classification consumes loadTrustSurface's policy load, which
## resolves config/policy/merge_admission.json against the workspace cwd —
## the B checkout in the MG verdict job ("Checkout executor tree = B").
## These tests simulate two workspaces (two temp CWDs) and pin the anchor
## property: the consumed set is exactly the evaluating CWD's file, so a PR
## editing the policy cannot re-classify itself. Motivation: the removed
## compiled surface had drifted from the policy — 2026-10-14 06:47
## arbitrary-deny incident (MG run 38524327637).

func policyJsonWith(trustSurface: seq[string]): string {.raises: [].} =
  ## Minimal merge_admission.json fixture — only the key loadTrustSurface
  ## consumes; the SSOT's other keys are irrelevant to this evaluation.
  $(%*{"schemaVersion": 1, "trustSurface": trustSurface})

proc tsTempDir(prefix: string): string {.raises: [CatchableError].} =
  ## Unique temp workspace directory — stands in for a workspace cwd. The
  ## pinned toolchain's std/os has no createTempDir, so uniqueness comes from
  ## the prefix + test-process id.
  let dir = getTempDir() & prefix & $getCurrentProcessId()
  createDir(dir)
  dir

suite "trustSurface — policy SSOT single-source (B-anchored)":
  test "consumed set == the evaluating CWD's policy file (B anchor wins; self-exemption impossible)":
    let cwdAtStart = getCurrentDir()
    let dirA = tsTempDir("ax_ts_cwd_a_")
    let dirB = tsTempDir("ax_ts_cwd_b_")
    defer:
      setCurrentDir(cwdAtStart)
      removeDir(dirA)
      removeDir(dirB)
    # Workspace A: the PR's own edited policy — merge_cli.nim NOT protected.
    # (Non-empty: an EMPTY surface is itself a fail-closed loader error, and
    # a real edited policy would still protect its other paths.)
    createDir(dirA / "config" / "policy")
    writeFile(dirA / "config" / "policy" / "merge_admission.json",
      policyJsonWith(@[".github/workflows/admission-check.yml"]))
    # Workspace B: the landed base policy — merge_cli.nim IS protected.
    createDir(dirB / "config" / "policy")
    writeFile(dirB / "config" / "policy" / "merge_admission.json",
      policyJsonWith(@["src/cli/merge_cli.nim"]))

    # Evaluated in B (the MG verdict-job anchor): the PR's candidate copy of
    # the policy (A's file) is NOT consulted — merge_cli.nim stays protected.
    setCurrentDir(dirB)
    let surfaceB = loadTrustSurface(TrustSurfacePolicyPath)
    check surfaceB.isOk
    check trustSurfaceMatch("src/cli/merge_cli.nim", "", surfaceB.get).isSome
    # The same load anchored in A consumes A's file: NOT protected there —
    # the consumed set is exactly the evaluating CWD's file.
    setCurrentDir(dirA)
    let surfaceA = loadTrustSurface(TrustSurfacePolicyPath)
    check surfaceA.isOk
    check trustSurfaceMatch("src/cli/merge_cli.nim", "", surfaceA.get).isNone
    check "src/cli/merge_cli.nim" in surfaceB.get
    check "src/cli/merge_cli.nim" notin surfaceA.get

  test "tombstone-only path still matches (protection retention)":
    let dirC = tsTempDir("ax_ts_tomb_")
    defer: removeDir(dirC)
    createDir(dirC / "config" / "policy")
    # The surviving policy surface does NOT list the deleted workflow paths.
    writeFile(dirC / "config" / "policy" / "merge_admission.json",
      policyJsonWith(@[".github/workflows/admission-check.yml"]))
    let surface = loadTrustSurface(dirC / "config" / "policy" /
                                   "merge_admission.json")
    check surface.isOk
    check trustSurfaceMatch(".github/workflows/readiness_start.yml", "",
                            surface.get).isSome
    check trustSurfaceMatch("new-name.yml", ".github/workflows/auto_merge.yml",
                            surface.get).isSome
    check trustSurfaceMatch(
      ".github/actions/canonical-bootstrap/x/action.yml", "",
      surface.get).isSome
    check trustSurfaceMatch(".github/workflows/admission-check.yml", "",
                            surface.get).isSome
    check trustSurfaceMatch("docs/evidence/anything.md", "",
                            surface.get).isNone

  test "fail-closed: missing or corrupt policy is an error, never an empty set":
    let missing = loadTrustSurface(getTempDir() / "ax_ts_no_such_policy_dir" /
                                   "merge_admission.json")
    check missing.isErr
    check "fail-closed" in missing.error
    check "not found in workspace cwd" in missing.error

    let dirD = tsTempDir("ax_ts_corrupt_")
    defer: removeDir(dirD)
    createDir(dirD / "config" / "policy")
    let policyPath = dirD / "config" / "policy" / "merge_admission.json"

    writeFile(policyPath, "{ not json at all")
    let corrupt = loadTrustSurface(policyPath)
    check corrupt.isErr
    check "fail-closed" in corrupt.error

    writeFile(policyPath, """{"schemaVersion": 1, "version": "999.0.0"}""")
    let noKey = loadTrustSurface(policyPath)
    check noKey.isErr
    check "no trustSurface array" in noKey.error

    writeFile(policyPath, """{"trustSurface": "not-an-array"}""")
    check loadTrustSurface(policyPath).isErr

    writeFile(policyPath, """{"trustSurface": []}""")
    let empty = loadTrustSurface(policyPath)
    check empty.isErr
    check "empty" in empty.error

# ---------------------------------------------------------------------------
# Rotation/closure adjudication (ADR-0025 §7/§13, plan Phase 4) — pure core
# ---------------------------------------------------------------------------
## Fixtures use deriver-format lines (`<mode> <type> <sha>\t<path>`, byte
## equality — the same wire format the gate's closure job produces and the
## pin constructor emits).

func lineSet(lines: varargs[string]): HashSet[string] {.raises: [].} =
  result = initHashSet[string]()
  for ln in lines:
    result.incl(ln)

suite "adjudicateRotation — candidate-delta unchanged → NORMAL":
  test "derived(M) == derived(B) with anchors exact → NORMAL (subject changes fine)":
    # A Tier-S subject change (docs/spec) with a closure-unchanged candidate
    # tree is ordinary NORMAL — a closure change BY THE CANDIDATE DELTA is
    # exactly what rotation authorizes (Amendment F classification).
    let h = lineSet("100644 blob a1\tci/checker.mk",
                    "100644 blob b2\ttools/ci/derive_checker_closure.nim")
    let b = lineSet("100644 blob a1\tci/checker.mk",
                    "100644 blob b2\ttools/ci/derive_checker_closure.nim")
    let pinB = some(lineSet("100644 blob a1\tci/checker.mk",
                            "100644 blob b2\ttools/ci/derive_checker_closure.nim"))
    let adj = adjudicateRotation(h, b, b, pinB, some(h),
      @["docs/spec/productization_contract.md"])
    check adj.qualification == rqNormal
    check not adj.check.closureChange   # the PR's own delta changes no member
    check adj.check.allowlistOk
    check adj.check.oldAnchorOk
    check adj.check.newAnchorOk
    check not adj.check.genesis
    check adj.check.delegatedToPlatform
    check adj.reasonCode.len == 0

suite "adjudicateRotation — candidate delta changes closure + conditions OK → ROTATION":
  test "candidate tree changes a member (derivedM != derivedB); allowlist + anchors OK → ROTATION":
    let b = lineSet("100644 blob a1\tci/checker.mk",
                    "100644 blob b2\ttools/ci/derive_checker_closure.nim")
    # ci/checker.mk content changed BY THE PR → tree(M) carries the new sha in
    # derived(M) (Tier C content rotation — path already a closure member).
    let h = lineSet("100644 blob a2\tci/checker.mk",
                    "100644 blob b2\ttools/ci/derive_checker_closure.nim")
    let pinB = some(b)
    let pinH = some(h)
    let adj = adjudicateRotation(h, b, h, pinB, pinH,
      @["ci/checker.mk", "docs/adr/0025-gateway-landing-authority.md"])
    check adj.qualification == rqRotation
    check adj.check.closureChange
    check adj.check.allowlistOk
    check adj.check.subjectDeltaZero
    check adj.check.oldAnchorOk
    check adj.check.newAnchorOk
    check not adj.check.genesis
    check adj.check.delegatedToPlatform
    check adj.reasonCode.len == 0

suite "adjudicateRotation — allowlist violation (①/② → NOT-ADMIT)":
  test "candidate delta changes closure + changed outside closure∪ADR∪pin → NONE (ROT_ALLOWLIST)":
    let b = lineSet("100644 blob a1\tci/checker.mk")
    let h = lineSet("100644 blob a2\tci/checker.mk")
    let pinB = some(b)
    let adj = adjudicateRotation(h, b, h, pinB, some(h),
      @["src/regular_subject_change.nim"])
    check adj.qualification == rqNone
    check adj.reasonCode == "ROT_ALLOWLIST"
    check not adj.check.allowlistOk
    check not adj.check.subjectDeltaZero
    check adj.check.newAnchorOk  # ④ is an every-path fact — computed, not the deny (Pass 2.75 owns ④)
    check adj.reason.contains("allowlist")

suite "adjudicateRotation — Amendment A5 companion paths (rust lane landing)":
  test "the rust lane landing's candidate delta (16 paths) → ROTATION (allowlist OK)":
    # prereg rotation_allowlist_a5_prereg_2026-10-14 / ADR-0025 Amendment A5:
    # the landing's candidate delta changes closure member src/cli/merge_cli.nim
    # (the RotationAllowlistExtra SSOT itself) and companions the rust
    # certified-subset surface (rust_lane_cli, charon_runner, the probe
    # fixtures, the gateway/unit tests, the two spec docs, the evidence prereg
    # and verification_scope.lock) — every changed path inside
    # closure ∪ Extra ∪ pin after A5, so the rotation qualifies instead of
    # deadlocking on ① ROT_ALLOWLIST.
    let b = lineSet("100644 blob c1\tsrc/cli/merge_cli.nim",
                    "100644 blob a1\tci/checker.mk")
    let h = lineSet("100644 blob c2\tsrc/cli/merge_cli.nim",
                    "100644 blob a1\tci/checker.mk")
    let pinB = some(b)
    let pinH = some(h)
    let adj = adjudicateRotation(h, b, h, pinB, pinH,
      @["data/verification_scope.lock",
        "docs/evidence/rotation_allowlist_a5_prereg_2026-10-14.md",
        "docs/spec/rust_certified_subset.md",
        "docs/spec/rust_toolchain_quirks.md",
        "src/cli/rust_lane_cli.nim",
        "src/verification/charon_runner.nim",
        "tests/fixtures/rust/axiom_rust_probe/Cargo.lock",
        "tests/fixtures/rust/axiom_rust_probe/Cargo.toml",
        "tests/fixtures/rust/axiom_rust_probe/README.md",
        "tests/fixtures/rust/axiom_rust_probe/axiom.specs.json",
        "tests/fixtures/rust/axiom_rust_probe/axiom_rust_probe.llbc",
        "tests/fixtures/rust/axiom_rust_probe/src/lib.rs",
        "tests/gateway/rust_lane_cli_acceptance_test.nim",
        "tests/gateway/rust_subject_provenance_issuance_test.nim",
        "tests/gateway/rust_subject_three_cases_test.nim",
        "tests/unit/test_charon_runner.nim"])
    check adj.qualification == rqRotation
    check adj.check.closureChange
    check adj.check.allowlistOk
    check adj.check.subjectDeltaZero
    check adj.check.oldAnchorOk
    check adj.check.newAnchorOk
    check not adj.check.genesis
    check adj.check.delegatedToPlatform
    check adj.reasonCode.len == 0

  test "un-enumerated rust fixture path still fails closed (ROT_ALLOWLIST — no glob widening)":
    # A5 enumerates exactly the 16 rust-lane paths; any other rust fixture
    # companion keeps the rotation deadlocked (A2 (i) fail-closed preserved).
    let b = lineSet("100644 blob c1\tsrc/cli/merge_cli.nim")
    let h = lineSet("100644 blob c2\tsrc/cli/merge_cli.nim")
    let adj = adjudicateRotation(h, b, h, some(b), some(h),
      @["src/cli/rust_lane_cli.nim",
        "tests/fixtures/rust/other_probe/src/lib.rs"])
    check adj.qualification == rqNone
    check adj.reasonCode == "ROT_ALLOWLIST"
    check not adj.check.allowlistOk
    check not adj.check.subjectDeltaZero

suite "adjudicateRotation — stale old anchor (③ → NOT-ADMIT, single deny point)":
  test "pin@B key present but != derived(B) → NONE (ROT_OLD_PIN)":
    let b = lineSet("100644 blob a1\tci/checker.mk")
    let h = lineSet("100644 blob a2\tci/checker.mk")
    let pinB = some(lineSet("100644 blob STALE\tci/checker.mk"))
    # changed path stays inside the allowlist so ③ is what fires.
    let adj = adjudicateRotation(h, b, h, pinB, some(h), @["ci/checker.mk"])
    check adj.qualification == rqNone
    check adj.reasonCode == "ROT_OLD_PIN"
    # Amendment F ladder: ③ (step 2) precedes ① (step 5) — the allowlist is
    # NOT evaluated on the ③ deny (flag keeps its unreachable default).
    check not adj.check.allowlistOk
    check not adj.check.oldAnchorOk

  test "③ outranks ① — stale pin + allowlist violation → ROT_OLD_PIN (not ROT_ALLOWLIST)":
    # Ladder reorder regression (Amendment F §3): the OLD formula evaluated
    # ① before ③ and recorded ROT_ALLOWLIST here. The candidate delta DID
    # change the closure (derivedM != derivedB) and the changed path is
    # outside the allowlist — yet the ladder-selected deny is the
    # classification-independent old-anchor fact (step 2 < step 5).
    let b = lineSet("100644 blob a1\tci/checker.mk")
    let h = lineSet("100644 blob a2\tci/checker.mk")
    let pinB = some(lineSet("100644 blob STALE\tci/checker.mk"))
    let adj = adjudicateRotation(h, b, h, pinB, some(h),
      @["src/regular_subject_change.nim"])
    check adj.qualification == rqNone
    check adj.reasonCode == "ROT_OLD_PIN"
    check not adj.check.oldAnchorOk
    check not adj.check.allowlistOk    # not evaluated — ③ fired first

  test "④ annotation outranks ① — ④ fail + allowlist fail → ROT_NEW_PIN recorded (deny at Pass 2.75)":
    # Amendment F ladder: ④ (step 3) is ABOVE ① (step 5), so the allowlist
    # deny never overwrites the ④ annotation — the recorded reason stays the
    # ladder-selected one, and Pass 2.75 (which fires before Pass 2.97)
    # denies with it verbatim.
    let b = lineSet("100644 blob a1\tci/checker.mk")
    let h = lineSet("100644 blob a2\tci/checker.mk")
    let pinB = some(b)
    let pinH = some(lineSet("100644 blob WRONG\tci/checker.mk"))
    let adj = adjudicateRotation(h, b, h, pinB, pinH,
      @["src/regular_subject_change.nim"])
    check adj.check.closureChange
    check not adj.check.allowlistOk
    check not adj.check.newAnchorOk
    check adj.qualification == rqNone     # a ladder condition failed (①)
    check adj.reasonCode == "ROT_NEW_PIN" # ④ annotation preserved — never overwritten

suite "adjudicateRotation — genesis exception (③ ADR §7 1회)":
  test "pin@B key absent + pin@H == derived(H) → ROTATION (genesis=true)":
    let b = lineSet("100644 blob a1\tci/checker.mk")
    let h = lineSet("100644 blob a1\tci/checker.mk",
                    "100644 blob b2\ttools/ci/derive_checker_closure.nim")
    let pinB = none(HashSet[string])   # trustedCheckerTreeClosure key ABSENT
    let pinH = some(h)
    # Genesis allowlist = docs/adr/** ∪ the pin file only (pin installation).
    let adj = adjudicateRotation(h, b, h, pinB, pinH,
      @["config/trusted_writer_set.json",
        "docs/adr/0025-gateway-landing-authority.md"])
    check adj.qualification == rqRotation
    check adj.check.genesis
    check adj.check.oldAnchorOk      # ③ satisfied via the genesis exception
    check adj.check.newAnchorOk
    check adj.reasonCode.len == 0

  test "genesis claimed but pin@H missing → ROTATION-class fact + annotation (ROT_GENESIS_INVALID; deny = Pass 2.75)":
    let b = lineSet("100644 blob a1\tci/checker.mk")
    let h = lineSet("100644 blob a1\tci/checker.mk",
                    "100644 blob b2\ttools/ci/derive_checker_closure.nim")
    let pinB = none(HashSet[string])
    let adj = adjudicateRotation(h, b, h, pinB, none(HashSet[string]),
      @["config/trusted_writer_set.json"])
    # ④ never denies inside the adjudication (H2 is the single policy deny) —
    # the fact stays ROTATION-class with the genesis-selected annotation.
    check adj.qualification == rqRotation
    check adj.reasonCode == "ROT_GENESIS_INVALID"
    check adj.check.genesis
    check not adj.check.newAnchorOk

suite "adjudicateRotation — new anchor mismatch (④ fact annotation; deny at Pass 2.75)":
  test "pin@H != derived(H) → ROTATION-class fact + annotation (ROT_NEW_PIN)":
    let b = lineSet("100644 blob a1\tci/checker.mk")
    let h = lineSet("100644 blob a2\tci/checker.mk")
    let pinB = some(b)
    let pinH = some(lineSet("100644 blob WRONG\tci/checker.mk"))
    let adj = adjudicateRotation(h, b, h, pinB, pinH, @["ci/checker.mk"])
    check adj.qualification == rqRotation
    check adj.reasonCode == "ROT_NEW_PIN"
    check adj.check.oldAnchorOk
    check not adj.check.newAnchorOk

  test "③ is classification-independent — NORMAL candidate delta + stale pin → rqNone ROT_OLD_PIN":
    # Amendment F §2: pin@B == derived(B) is evaluated on EVERY path. The
    # PR's own delta changes no member (derivedM == derivedB — the class
    # WOULD be rqNormal), but the stale old anchor denies first (step 2).
    # This is the S1' contract: the stale-base-pin ROT_OLD_PIN deny survives
    # the classification replacement.
    let b = lineSet("100644 blob a1\tci/checker.mk")
    let h = b   # pin-only PR: no closure member changed
    let pinB = some(lineSet("100644 blob STALE\tci/checker.mk"))
    let adj = adjudicateRotation(h, b, b, pinB, some(h), @["ci/checker.mk"])
    check not adj.check.closureChange   # the candidate delta itself is neutral
    check adj.qualification == rqNone   # yet ③ denies — classification-independent
    check adj.reasonCode == "ROT_OLD_PIN"
    check not adj.check.oldAnchorOk

# ---------------------------------------------------------------------------
# S1' regression — the real measured incident state at old base 73ed69a5a
# (docs/evidence/trust_root_reaudit_2026-10-10.md §2): the genesis pin@B
# (7c6a3370, 2026-09-26, 840 members) went stale against the actual tree
# (derived@B = 857 members: 17 path additions, 0 removals, 101 common-member
# sha drifts). A pin-only re-anchor PR on top of that base must be rejected
# on ③ — the old anchor no longer describes B — even though everything else
# (allowlist, new anchor) is fine.
# ---------------------------------------------------------------------------

suite "adjudicateRotation — stale base pin + pin-only re-anchor PR (S1' regression, ROT_OLD_PIN)":
  test "pin-only PR over stale base 73ed69a5a → closureChange=false, ③ alone fails, ④ holds":
    # Actual trees: a pin-only PR changes no closure member, so set(H) == set(B).
    let b = lineSet("100644 blob a1\tci/checker.mk",
                    "100644 blob b2\ttools/ci/derive_checker_closure.nim",
                    "100644 blob c3\tsrc/cli/merge_cli.nim")
    let h = b
    # pin@B = the measured stale genesis pin: 101 drifted shas + 17 missing
    # paths (here: one drift on ci/checker.mk + one missing member).
    let pinB = some(lineSet("100644 blob STALE\tci/checker.mk",
                            "100644 blob b2\ttools/ci/derive_checker_closure.nim"))
    # The PR re-anchors pin@H to exactly the actual H tree.
    let pinH = some(h)
    let adj = adjudicateRotation(h, b, b, pinB, pinH,
      @[RotationPinBPath])
    check not adj.check.closureChange  # candidate delta neutral — the class WOULD be NORMAL
    check adj.qualification == rqNone
    check adj.reasonCode == "ROT_OLD_PIN"  # ③ is classification-independent (Amendment F step 2) — deny preserved
    # Amendment F ladder: ① is step 5, BELOW ③ — not evaluated on this deny.
    check not adj.check.allowlistOk
    check not adj.check.subjectDeltaZero
    check not adj.check.oldAnchorOk    # line-set(pin@B) != set(B) — measured 840 != 857
    check adj.check.newAnchorOk        # ④ holds: line-set(pin@H) == set(H)
    check not adj.check.genesis

# ---------------------------------------------------------------------------
# S1-C/D — the NORMAL hole (docs/evidence/trust_root_reaudit_2026-10-10.md §6,
# measured 2026-10-10): closureEqual is true whenever the TREE and pin@B are
# untouched, so a PR that tampers ONLY with pin@H content lands NORMAL(GO) —
# ④ is vacuous-true under NORMAL and nobody verifies line-set(pin@H) == set(H).
# Integrity stays fail-closed (the next rotation ③-denies on the now-stale
# anchor), but availability is attackable: the queue freezes from the next PR
# on, and recovery requires a direct push to main (the pin file sits outside
# the TWS file_path_restriction). This test PINS THE CURRENT BEHAVIOR as the
# repair anchor — when the follow-up rotation PR makes NORMAL evaluate ④,
# this expectation flips to deny (T2b precedent: an anchor test that inverts
# with the fix). Until then the closure-watcher workflow is the detection
# gap-closer.
# ---------------------------------------------------------------------------

suite "adjudicateRotation — NORMAL hole S1-C/D stays repaired: pin@H content-only tamper is annotated (deny at Pass 2.75)":
  test "candidate delta neutral + pin@B valid, pin@H tampered → NORMAL-class fact, ④ truthful, ROT_NEW_PIN annotated":
    let b = lineSet("100644 blob a1\tci/checker.mk",
                    "100644 blob b2\ttools/ci/derive_checker_closure.nim")
    let h = b                     # no closure member changed
    let pinB = some(b)            # old anchor valid
    # Tampered pin@H: content edited without any tree change.
    let pinH = some(lineSet("100644 blob EVIL\tci/checker.mk",
                            "100644 blob b2\ttools/ci/derive_checker_closure.nim"))
    let adj = adjudicateRotation(h, b, b, pinB, pinH, @[RotationPinBPath])
    check not adj.check.closureChange  # candidate delta neutral (Amendment F fact)
    check adj.qualification == rqNormal        # SUBJECT CLASS — not a judgment
    check not adj.check.newAnchorOk            # ④ is evaluated truthfully on the NORMAL path
    check adj.reasonCode == "ROT_NEW_PIN"      # fact annotation; the deny is Pass 2.75 (H2)
    check not adj.check.genesis

# ---------------------------------------------------------------------------
# S1 — stale-base misclassification: FIXED by the candidate-delta formula
# (docs/evidence/s1-stale-base-repro-2026-10-12.md; ADR-0025 Amendment F,
# 2026-10-12). The retired formula
#   closureEqual = (derivedH == derivedB) and (derivedB == pinBSet)
# misclassified a NEUTRAL PR (the PR itself changed no closure member)
# whenever the BASE drifted after the PR branched — the drift leg
# (derivedH != derivedB) flipped the class to ROTATION and the PR's own
# closure-neutral paths then failed ① → rqNone ROT_ALLOWLIST: a merge-blocking
# judgment about a change the PR never made (S1 FAIL evidence, 2026-10-12).
#
# The landed formula classifies by the PR's OWN candidate delta:
#   closureChange = (derived(M) != derived(B)), M = merge(B, H)
# — a neutral PR is rqNormal REGARDLESS of base drift (attribution
# invariance), while ③ (old anchor, pin@B vs derived(B)) is evaluated BEFORE
# classification as a classification-independent fact, so the stale-base-pin
# deny (ROT_OLD_PIN, the S1' suite above) is preserved.
#
# S2 FLIP (landed): these two tests pinned the RETIRED formula's verdict
# (rqNone / ROT_ALLOWLIST / allowlistOk=false) as a characterization; the
# assertions are now inverted to the post-fix expectation per the S2 FLIP
# markers, and the suite name no longer says "CURRENT-formula
# characterization" (S1 evidence §4 completion condition).
# ---------------------------------------------------------------------------

suite "adjudicateRotation — stale-base neutral PR (S1 repro, closure candidate delta) — FIXED: NORMAL":
  test "① base drifted by a landed pin rotation (860→864), PR neutral → NORMAL":
    # (b) Base drift: the rotation that landed first on main enrolled two new
    # closure members, so set(derived B) != set(derived H) even though the PR
    # changed no closure member.
    let b = lineSet("100644 blob a1\tci/checker.mk",
                    "100644 blob b2\ttools/ci/derive_checker_closure.nim",
                    "100644 blob n1\tbuild/certificates/epoch.manifest.json",
                    "100644 blob n2\tconfig/policy/rotation_baseline.json")
    # (a) PR neutral: H is the 860-era member set; the PR's own changed paths
    # (below) are closure-neutral subject files — so tree(M) = tree(B) on the
    # closure members: derived(M) == derived(B).
    let h = lineSet("100644 blob a1\tci/checker.mk",
                    "100644 blob b2\ttools/ci/derive_checker_closure.nim")
    # (c) pin@B anchors B exactly (the landed rotation re-anchored) — ③ holds.
    let pinB = some(b)
    let pinH = some(h)            # ④ holds too: line-set(pin@H) == set(H)
    let adj = adjudicateRotation(h, b, b, pinB, pinH,
      @["src/cli/merge_cli.nim", "docs/spec/productization_contract.md"])
    # FIXED verdict (S2 FLIP landed): the drift leg no longer classifies —
    # the candidate delta is closure-neutral → NORMAL, no ROT_* code, ①
    # vacuous-true under NORMAL (A2 ii).
    check not adj.check.closureChange
    check adj.qualification == rqNormal
    check adj.reasonCode.len == 0
    check adj.check.allowlistOk            # vacuous-true under NORMAL (A2 ii)
    check adj.check.subjectDeltaZero
    check adj.check.oldAnchorOk            # ③ holds — re-anchored by the landed rotation
    check adj.check.newAnchorOk            # ④ holds
    check not adj.check.genesis

  test "⑥ neutral follower after a queue predecessor's approved closure rotation → NORMAL (attribution-invariant)":
    # Attribution invariance: whether a PRECEDING PR in the merge queue
    # rotated the closure must not change a neutral FOLLOWER's class. The
    # predecessor changed a member's content (approved rotation) and
    # re-anchored pin@B; the follower branched before it landed and is tested
    # against the predecessor-inclusive base — the same drift shape as ①.
    let b = lineSet("100644 blob a2\tci/checker.mk",
                    "100644 blob b2\ttools/ci/derive_checker_closure.nim")
    let h = lineSet("100644 blob a1\tci/checker.mk",
                    "100644 blob b2\ttools/ci/derive_checker_closure.nim")
    let pinB = some(b)            # ③ holds: predecessor's rotation re-anchored
    let pinH = some(h)            # ④ holds
    let adj = adjudicateRotation(h, b, b, pinB, pinH,
      @["docs/guides/queue.md"])
    check not adj.check.closureChange
    check adj.qualification == rqNormal     # attribution-invariant (S2 FLIP landed)
    check adj.reasonCode.len == 0
    check adj.check.allowlistOk
    check adj.check.oldAnchorOk
    check adj.check.newAnchorOk

# ---------------------------------------------------------------------------
# Rotation Pass — env-absent skip + run-level errors (I/O boundary)
# ---------------------------------------------------------------------------

suite "Rotation Pass — env absent (legacy/local invocations)":
  test "no closure env → ok(none) — Pass skipped entirely":
    let res = collectRotationInputs("", "", "", "", @["x.nim"], true)
    check res.isOk
    check res.get.isNone

  test "dry-run JSON without rotation facts → qualification UNSPECIFIED + deny verdict":
    let j = buildDryRunJson(42, "h", "b",
      MergeAdmissionOutcome(result: mergeAborted, reasonCode: "ROT_UNSPECIFIED",
        reason: "rotation qualification UNSPECIFIED"),
      none(RotationAdjudication), none(LayerAdmissibilityFacts))
    check j["qualification"].getStr == "UNSPECIFIED"
    check j["rotationCheck"].kind == JNull
    check j["rotationNote"].getStr.contains("UNSPECIFIED")
    check j["verdict"]["reasonCode"].getStr == "ROT_UNSPECIFIED"
    check j["layerAdmissibility"].kind == JNull

  test "rotation absent (UNSPECIFIED) → DENY (ROT_UNSPECIFIED — fail-closed contract)":
    let rec = VerificationRecord(headSha: "h", baseSha: "b",
      requiredChecks: @[okCheck],
      admission: some(factsWith("h", goValidations)))
    let o = MergeAdmissible(rec, "b")
    check o.result == mergeAborted
    check o.reasonCode == "ROT_UNSPECIFIED"
    check o.reason.contains("UNSPECIFIED")

  test "dry-run JSON with rotation facts → qualification + rotationCheck":
    let h = lineSet("100644 blob a1\tci/checker.mk")
    let adj = adjudicateRotation(h, h, h, some(h), some(h), @[])
    let j = buildDryRunJson(7, "h", "b",
      MergeAdmissionOutcome(result: mergeGo, reasonCode: "GO", reason: ""), some(adj),
      none(LayerAdmissibilityFacts))
    check j["qualification"].getStr == "NORMAL"
    check j["rotationCheck"]["closureChange"].getBool == false  # candidate-delta-neutral fixture
    check j["rotationCheck"]["genesis"].getBool == false
    check j["rotationCheck"]["delegatedToPlatform"].getBool
    check j["rotationCheck"]["changed"].kind == JArray
    check j["layerAdmissibility"].kind == JNull

suite "Rotation Pass — run-level errors (fail-closed, distinct from verdicts)":
  test "partial supply (one derived path only) → err":
    let res = collectRotationInputs("/tmp/derived-H.txt", "", "", "", @[], true)
    check res.isErr
    check res.error.contains("partially supplied")

  test "derived line-file missing → err (never a verdict)":
    let res = collectRotationInputs("/nonexistent-h", "/nonexistent-b", "/nonexistent-m", "", @[], true)
    check res.isErr
    check res.error.contains("missing")

  test "derived-M env absent while H/B supplied → partial-supply err (Amendment F third leg, fail-closed)":
    let res = collectRotationInputs("/tmp/derived-H.txt", "/tmp/derived-B.txt", "", "", @[], true)
    check res.isErr
    check res.error.contains("partially supplied")
    check res.error.contains("derivedM")

suite "Admission contract — rotation UNSPECIFIED fail-closed (Pass 2.97, DEBT#501)":
  ## The committed verdict-stage contract (admission-check.yml :1446/:1541):
  ## qualification UNSPECIFIED — the SL-02 pre-gate state (scope_sl02 never
  ## true, the derived-closure artifact never fetched) or a post-gate
  ## transient download loss — MUST deny at the gate verdict because
  ## UNSPECIFIED != NORMAL/ROTATION. Informational absence never reads as
  ## clean (missing ≠ valid empty, spec §2). Deny vocabulary is unchanged:
  ## MergeAdmissionResult mergeAborted (existing enum), reasonCode joins the
  ## ROT_* family.
  test "qualification UNSPECIFIED → DENY (ROT_UNSPECIFIED)":
    let rec = VerificationRecord(headSha: "h", baseSha: "b",
      requiredChecks: @[okCheck],
      admission: some(factsWith("h", goValidations)))
    let o = MergeAdmissible(rec, "b")
    check o.result == mergeAborted
    check o.reasonCode == "ROT_UNSPECIFIED"
    check dryRunExit(o) == 1

  test "scope isolation — NORMAL closure keeps the GO path":
    var f = factsWith("h", goValidations)
    f.rotation = some(normalRotation())
    let rec = VerificationRecord(headSha: "h", baseSha: "b",
      requiredChecks: @[okCheck],
      admission: some(f))
    check MergeAdmissible(rec, "b").result == mergeGo
    check MergeAdmissible(rec, "b").reasonCode == "GO"

  test "scope isolation — ROTATION-qualified adjudication still continues to GO":
    let b = lineSet("100644 blob a1\tci/checker.mk")
    let h = lineSet("100644 blob a2\tci/checker.mk")
    let rot = adjudicateRotation(h, b, h, some(b), some(h), @["ci/checker.mk"])
    check rot.qualification == rqRotation
    var f = factsWith("h", goValidations)
    f.rotation = some(rot)
    let rec = VerificationRecord(headSha: "h", baseSha: "b",
      requiredChecks: @[okCheck],
      admission: some(f))
    check MergeAdmissible(rec, "b").result == mergeGo

  test "scope isolation — rqNone NOT-ADMIT keeps its own ROT_* code (untouched path)":
    let b = lineSet("100644 blob a1\tci/checker.mk")
    let h = lineSet("100644 blob a2\tci/checker.mk")
    let rot = adjudicateRotation(h, b, h, some(b), some(h),
      @["src/regular_subject_change.nim"])
    check rot.qualification == rqNone
    check rot.reasonCode == "ROT_ALLOWLIST"
    var f = factsWith("h", goValidations)
    f.rotation = some(rot)
    let rec = VerificationRecord(headSha: "h", baseSha: "b",
      requiredChecks: @[okCheck],
      admission: some(f))
    let o = MergeAdmissible(rec, "b")
    check o.result == mergeAborted
    check o.reasonCode == "ROT_ALLOWLIST"

  test "precedence — Pass 0 freshness outranks the UNSPECIFIED deny":
    let rec = VerificationRecord(headSha: "h", baseSha: "old-base",
      requiredChecks: @[okCheck],
      admission: some(factsWith("h", goValidations)))
    check MergeAdmissible(rec, "new-main").reasonCode == "STALE_BASE"

  test "precedence — trust-surface hit WITHOUT rotation inputs → upper fail-closed (ROT_UNSPECIFIED, exit 1)":
    # 4-class contract: the manual-merge route is "human ceremony + machine
    # pin-anchor check". With no rotation facts the machine check cannot run,
    # so the unverifiable state must NOT land (upper fail-closed boundary) —
    # this closes the invariant "every landing verifies pin@H == derived(H)".
    var f = factsWith("h", goValidations)
    f.trustSurfaceHits = @[TrustSurfaceHit(path: ".github/workflows/ci.yml",
                                           renamedFrom: "")]
    let rec = VerificationRecord(headSha: "h", baseSha: "b",
      requiredChecks: @[okCheck],
      admission: some(f))
    let o = MergeAdmissible(rec, "b")
    check o.reasonCode == "ROT_UNSPECIFIED"
    check dryRunExit(o) == 1

# ---------------------------------------------------------------------------
# Rotation helpers — pin/line parsing (pure)
# ---------------------------------------------------------------------------

suite "Rotation helpers — deriver lines / pin parsing":
  test "parseDerivedSet: malformed line → err (fail-closed)":
    check parseDerivedSet("garbage-without-tab").isErr
    check parseDerivedSet("only-tab\t").isErr
    check parseDerivedSet("").isOk
    check parseDerivedSet("100644 blob ab\tci/checker.mk\n").isOk
    check parseDerivedSet("100644 blob ab\tci/checker.mk\n\n").isOk

  test "stripJsoncComments removes // comments but keeps in-string slashes":
    let s = stripJsoncComments("{\n  // whole-line comment\n  \"url\": \"https://x//y\", // trailing\n  \"b\": 1\n}")
    check s.contains("\"url\": \"https://x//y\"")
    check not s.contains("// whole-line")
    check not s.contains("// trailing")
    discard parseJson(s)  # must remain valid JSON

  test "pinClosureLineSet: key absent → ok(none) (genesis state)":
    let r = pinClosureLineSet(%*{"schemaVersion": "axiom.trusted-writer-set.v1"})
    check r.isOk
    check r.get.isNone

  test "pinClosureLineSet: entries become deriver-format line-set":
    let r = pinClosureLineSet(%*{"trustedCheckerTreeClosure": {
      "ci/checker.mk": {"mode": "100644", "type": "blob", "sha": "a1b2"},
      "tools/ci/derive_checker_closure.nim": {"mode": "100644", "type": "blob", "sha": "c3d4"}}})
    check r.isOk
    check r.get.get == lineSet("100644 blob a1b2\tci/checker.mk",
                               "100644 blob c3d4\ttools/ci/derive_checker_closure.nim")

  test "pinClosureLineSet: malformed entry → err (fail-closed)":
    check pinClosureLineSet(%*{"trustedCheckerTreeClosure": {"ci/x.nim": {"mode": "100644"}}}).isErr
    check pinClosureLineSet(%*{"trustedCheckerTreeClosure": "not-an-object"}).isErr
    check pinClosureLineSet(%*"not-an-object-at-all").isErr   # non-object pin node

  test "rotationAllowlistOk: closure keys ∪ docs/adr/** ∪ pin file":
    let pinB = some(lineSet("100644 blob a1\tci/checker.mk"))
    check rotationAllowlistOk("ci/checker.mk", pinB)
    check rotationAllowlistOk("docs/adr/0025-gateway-landing-authority.md", pinB)
    check rotationAllowlistOk("docs/adr/sub/other.md", pinB)
    check rotationAllowlistOk("config/trusted_writer_set.json", pinB)
    check not rotationAllowlistOk("src/regular_change.nim", pinB)
    check rotationAllowlistOk("docs/spec/x.md", none(HashSet[string])) == false
    check rotationAllowlistOk("config/trusted_writer_set.json", none(HashSet[string]))

  test "rotationAllowlistOk: A2 amendment rotation-companion paths allowed (ADR-0025 A2, 2026-09-27)":
    # Amendment A2 minimal consistent set: trust workflow pair, rotation data,
    # rotation tests — 회전 PR이 반드시 동반하는 파일들 (PR #295 STOP-BLOCKED
    # 근거: tws↔admission-check ATOMICITY 페어 · check-debt arch rawContentHash ·
    # 회전 테스트). NON-member production src/는 여전히 allowlist 밖.
    let pinB = some(lineSet("100644 blob a1\tci/checker.mk"))
    for extra in RotationAllowlistExtra:
      check rotationAllowlistOk(extra, pinB)
    # closure member (fixture member) + A2 tails still OK; NON-member src/ 거부.
    check rotationAllowlistOk("ci/checker.mk", pinB)
    check not rotationAllowlistOk("src/regular_change.nim", pinB)
    # A2 확장 (2026-10-10): the epoch pin twin is a rotation companion — the
    # epoch gate requires productionExecutionPin == trustedAdmissionWorkflowSha,
    # so a pin rotation cannot land without it (PR #699 ROT_ALLOWLIST 실측).
    check rotationAllowlistOk("config/policy/epoch_manifest.json", pinB)

# ---------------------------------------------------------------------------
# SL-02 wire path (ADR-0033) — TWS pin JSON → line-set → pure adjudication.
# The consumer composition collectRotationInputs uses (:1132/:1155): pin@B
# and pin@H are READ as trusted_writer_set.json (JSONC) and folded through
# pinClosureLineSet into adjudicateRotation. These fixtures mirror the REAL
# pin entry shape ({mode, type, sha}) and drive the tamper/positive vectors
# through that exact chain — merge_cli itself is untouched (workstream #653).
# ---------------------------------------------------------------------------
func pinAt(entries: JsonNode): Option[HashSet[string]] {.raises: [].} =
  ## TWS pin JSON → trustedCheckerTreeClosure line-set (production shape).
  let pin = %*{"schemaVersion": "axiom.trusted-writer-set.v1"}
  pin["trustedCheckerTreeClosure"] = entries
  let r = pinClosureLineSet(pin)
  doAssert r.isOk, "pinClosureLineSet fixture error: " & r.error
  r.get

suite "SL-02 wire path — pin JSON → line-set → adjudication (ADR-0033)":
  test "T4: pin@B entry tampered (blob sha of a member forged) → NONE (ROT_OLD_PIN)":
    # A tampered pin@B no longer anchors B: line-set(pin@B) != set(derived B)
    # → old-anchor condition ③ fails → NOT-ADMIT ROT_OLD_PIN (the deny the
    # verdict stage reports verbatim).
    let b = lineSet("100644 blob a1b2\tci/checker.mk")
    let h = lineSet("100644 blob a1b2\tci/checker.mk")
    let pinB = pinAt(%*{"ci/checker.mk": {"mode": "100644", "type": "blob",
                                          "sha": "TAMPERED-sha-not-a1b2"}})
    let pinH = pinAt(%*{"ci/checker.mk": {"mode": "100644", "type": "blob",
                                          "sha": "a1b2"}})
    let adj = adjudicateRotation(h, b, b, pinB, pinH, @["ci/checker.mk"])
    check adj.qualification == rqNone
    check adj.reasonCode == "ROT_OLD_PIN"
    check not adj.check.oldAnchorOk
    check adj.reason.contains("old anchor invalid")

  test "T4b: pin@H entry tampered (new-anchor forged) → ROTATION-class fact + annotation (ROT_NEW_PIN)":
    let b = lineSet("100644 blob a1b2\tci/checker.mk")
    let h = lineSet("100644 blob NEW1\tci/checker.mk")
    let pinB = pinAt(%*{"ci/checker.mk": {"mode": "100644", "type": "blob",
                                          "sha": "a1b2"}})
    let pinH = pinAt(%*{"ci/checker.mk": {"mode": "100644", "type": "blob",
                                          "sha": "WRONG"}})
    let adj = adjudicateRotation(h, b, h, pinB, pinH, @["ci/checker.mk"])
    check adj.qualification == rqRotation
    check adj.reasonCode == "ROT_NEW_PIN"
    check adj.check.oldAnchorOk
    check not adj.check.newAnchorOk

  test "positive: pin lag wire path (pin@B anchors B, pin@H re-anchors H) → ROTATION":
    # The pin-rotation promotion flow: the checker closure changed at H, the
    # OLD pin (still in main/B) correctly anchors B (③), and the pin carried
    # by the candidate (H) correctly re-anchors H (④) — both read through
    # pinClosureLineSet exactly as collectRotationInputs does. ROTATION.
    let b = lineSet("100644 blob a1b2\tci/checker.mk",
                    "100644 blob c3d4\ttools/ci/derive_checker_closure.nim")
    let h = lineSet("100644 blob a2b2\tci/checker.mk",
                    "100644 blob c3d4\ttools/ci/derive_checker_closure.nim")
    let pinB = pinAt(%*{"ci/checker.mk": {"mode": "100644", "type": "blob",
                                          "sha": "a1b2"},
                        "tools/ci/derive_checker_closure.nim": {
                                          "mode": "100644", "type": "blob",
                                          "sha": "c3d4"}})
    let pinH = pinAt(%*{"ci/checker.mk": {"mode": "100644", "type": "blob",
                                          "sha": "a2b2"},
                        "tools/ci/derive_checker_closure.nim": {
                                          "mode": "100644", "type": "blob",
                                          "sha": "c3d4"}})
    let adj = adjudicateRotation(h, b, h, pinB, pinH,
      @["ci/checker.mk", "config/trusted_writer_set.json"])
    check adj.qualification == rqRotation
    check adj.check.allowlistOk
    check adj.check.oldAnchorOk
    check adj.check.newAnchorOk
    check adj.check.closureChange   # the candidate delta carries the member change
    check adj.reasonCode.len == 0

  test "genesis wire path: pin@B key absent → ok(none) → ROTATION (one-time §7)":
    let b = lineSet("100644 blob a1b2\tci/checker.mk")
    let h = lineSet("100644 blob a1b2\tci/checker.mk",
                    "100644 blob c3d4\ttools/ci/derive_checker_closure.nim")
    let pinBNone = pinClosureLineSet(%*{
      "schemaVersion": "axiom.trusted-writer-set.v1"})
    check pinBNone.isOk and pinBNone.get.isNone
    let pinH = pinAt(%*{"ci/checker.mk": {"mode": "100644", "type": "blob",
                                          "sha": "a1b2"},
                        "tools/ci/derive_checker_closure.nim": {
                                          "mode": "100644", "type": "blob",
                                          "sha": "c3d4"}})
    let adj = adjudicateRotation(h, b, h, pinBNone.get, pinH,
      @["config/trusted_writer_set.json", "docs/adr/0033-sl02-consumer-binding.md"])
    check adj.qualification == rqRotation
    check adj.check.genesis
    check adj.check.oldAnchorOk
    check adj.check.newAnchorOk

suite "buildGhArmCommand — exec boundary (command construction, no network)":
  test "exact gh auto-merge command with match-head-commit":
    let sha = "abcd1234abcd1234abcd1234abcd1234abcd1234"
    let cmd = buildGhArmCommand(42, sha)
    check cmd == "gh pr merge 42 --auto --match-head-commit " & sha

  test "NO strategy flag (MERGE authority = the queue, not the CLI)":
    let cmd = buildGhArmCommand(42, "abcd1234abcd1234abcd1234abcd1234abcd1234")
    check "--merge" notin cmd
    check "--squash" notin cmd
    check "--rebase" notin cmd
    check cmd.contains("--auto")

# ---------------------------------------------------------------------------
# scanLedgerContinuityCertNode — the transport-injectable full-ledger scan
# core (cert-fact-minimize Slice B). The live collectCertificateContinuityFacts
# wraps this with the real transport; these fixtures pin the verdict-relevant
# semantics through the refactor: 3+N request budget, INV-13 latest-createdAt
# adoption, download-failure skip (absence stays a fact), present-but-tampered
# cert fails closed.
# ---------------------------------------------------------------------------

const ScanSubject = "ab12cd34ef56ab12cd34ef56ab12cd34ef56ab12cd34ef56ab12cd34ef56ab12"
const ScanSubject2 = "cd34ef56ab12cd34ef56ab12cd34ef56ab12cd34ef56ab12cd34ef56ab12cd34"
const ScanHead = "1111111111111111111111111111111111111111"

proc scanCert(id: string; head: string; createdAt: string; signed: bool = false): JsonNode =
  var node = %*{
    "kind": "subject-continuity",
    "subjectId": id,
    "baseSha": "base111111111111111111111111111111111111111",
    "headSha": head,
    "headTreeDigest": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcd",
    "policyDigest": "pol", "scopeDigest": "scope", "evidenceDigest": "ev",
    "createdAt": createdAt}
  if signed:
    let sig = signCertificatePayload(node)
    node["attestation"] = %*{"algorithm": AxiomAttestationAlgorithm,
      "publicKeyId": sig.get.publicKeyId, "signature": sig.get.signature}
  node

type ScanFixture = object
  transport: LedgerTransport

proc scanFixture(blobs: Table[string, JsonNode]): ScanFixture =
  ## Fake side-ref ledger: 1 tip read + 1 commit + 1 recursive tree serve the
  ## full listing; each blob sha serves its cert bytes (base64).
  var bodyById: Table[string, string]
  for sha, node in blobs:
    bodyById[sha] = $node
  let fetcher: JsonFetcher = proc(url: string): Result[JsonNode, string] {.raises: [CatchableError, OSError, Exception].} =
    if url.contains("/git/commits/"):
      return ok(%*{"sha": url[(url.rfind("/") + 1) .. ^1], "tree": {"sha": "treeaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}})
    if url.contains("/git/trees/"):
      var entries = newJArray()
      for sha, body in bodyById.pairs:
        entries.add(%*{"path": parseJson(body){"subjectId"}.getStr("") & ".json",
                       "type": "blob", "sha": sha})
      return ok(%*{"tree": entries})
    if url.contains("/git/blobs/"):
      let sha = url[(url.rfind("/") + 1) .. ^1]
      if bodyById.hasKey(sha):
        return ok(%*{"sha": sha, "content": encode(bodyById[sha])})
      return err("fixture: unknown blob " & sha)
    err("fixture: unexpected " & url)
  let tipper: LedgerTipFetcher = proc(repo: string): Result[string, string] {.raises: [CatchableError, OSError, Exception].} =
    ok("tipaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
  let dummypost: JsonPoster = proc(url: string; body: string): Result[JsonNode, string] {.raises: [CatchableError, OSError, Exception].} =
    err("fixture: post not used")
  let dummypatch: JsonPatcher = proc(url: string; body: string): Result[JsonNode, string] {.raises: [CatchableError, OSError, Exception].} =
    err("fixture: patch not used")
  ScanFixture(transport: LedgerTransport(fetch: fetcher, post: dummypost,
    patch: dummypatch, tip: tipper))

proc brokenBlobFixture(): LedgerTransport =
  ## Listing serves one cert; every blob read fails — the scan must skip it
  ## (historical continue semantics), never fail and never invent a match.
  let fetcher: JsonFetcher = proc(url: string): Result[JsonNode, string] {.raises: [CatchableError, OSError, Exception].} =
    if url.contains("/git/commits/"):
      return ok(%*{"sha": url[(url.rfind("/") + 1) .. ^1], "tree": {"sha": "treebbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}})
    if url.contains("/git/trees/"):
      return ok(%*{"tree": [{"path": ScanSubject & ".json", "type": "blob",
                             "sha": "blobccccccccccccccccccccccccccccccccccccc"}]})
    if url.contains("/git/blobs/"):
      return err("fixture: blob transport down")
    err("fixture: unexpected " & url)
  let tipper: LedgerTipFetcher = proc(repo: string): Result[string, string] {.raises: [CatchableError, OSError, Exception].} =
    ok("tipbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")
  let dummypost: JsonPoster = proc(url: string; body: string): Result[JsonNode, string] {.raises: [CatchableError, OSError, Exception].} =
    err("fixture: post not used")
  let dummypatch: JsonPatcher = proc(url: string; body: string): Result[JsonNode, string] {.raises: [CatchableError, OSError, Exception].} =
    err("fixture: patch not used")
  LedgerTransport(fetch: fetcher, post: dummypost, patch: dummypatch, tip: tipper)

suite "scanLedgerContinuityCertNode — 3+N scan core (fixture transport)":
  test "matching signed cert found via the pinned blob map":
    var fx = scanFixture({
      "blobaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa": scanCert(ScanSubject, ScanHead, "2026-10-01T00:00:00Z", signed = true),
      "blobbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb": scanCert(ScanSubject2, "2222222222222222222222222222222222222222", "2026-10-02T00:00:00Z", signed = true)}.toTable)
    let res = scanLedgerContinuityCertNode(fx.transport, ScanHead, "owner/repo")
    check res.isOk
    check res.get.isSome
    check res.get.get{"subjectId"}.getStr("") == ScanSubject
    check res.get.get{"headSha"}.getStr("") == ScanHead

  test "INV-13 duplicates adopt the latest createdAt cert (warn, not deny)":
    var fx = scanFixture({
      "blocaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa": scanCert(ScanSubject, ScanHead, "2026-09-01T00:00:00Z"),
      "blocbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb": scanCert(ScanSubject2, ScanHead, "2026-10-05T00:00:00Z")}.toTable)
    let res = scanLedgerContinuityCertNode(fx.transport, ScanHead, "owner/repo")
    check res.isOk
    check res.get.isSome
    check res.get.get{"subjectId"}.getStr("") == ScanSubject2

  test "no matching head → ok(none) — absence is a fact (predicate: NO_CERT)":
    var fx = scanFixture({
      "blodaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa": scanCert(ScanSubject, "3333333333333333333333333333333333333333", "2026-10-01T00:00:00Z")}.toTable)
    let res = scanLedgerContinuityCertNode(fx.transport, ScanHead, "owner/repo")
    check res.isOk
    check res.get.isNone

  test "download failure skips the cert (historical continue semantics)":
    let res = scanLedgerContinuityCertNode(brokenBlobFixture(), ScanHead, "owner/repo")
    check res.isOk
    check res.get.isNone

  test "present-but-invalid attestation on a matching cert → err (fail-closed)":
    var tampered = scanCert(ScanSubject, ScanHead, "2026-10-01T00:00:00Z", signed = true)
    tampered["createdAt"] = %"2020-01-01T00:00:00Z"  # post-sign tamper → signature invalid
    var fx = scanFixture({"blofeaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa": tampered}.toTable)
    let res = scanLedgerContinuityCertNode(fx.transport, ScanHead, "owner/repo")
    check res.isErr
    check res.error.contains("attestation signature invalid")

  test "empty ledger (absent ref) → ok(none)":
    let fetcher: JsonFetcher = proc(url: string): Result[JsonNode, string] {.raises: [CatchableError, OSError, Exception].} =
      err("no reads expected")
    let tipper: LedgerTipFetcher = proc(repo: string): Result[string, string] {.raises: [CatchableError, OSError, Exception].} =
      ok("")
    let dummypost: JsonPoster = proc(url: string; body: string): Result[JsonNode, string] {.raises: [CatchableError, OSError, Exception].} =
      err("fixture: post not used")
    let dummypatch: JsonPatcher = proc(url: string; body: string): Result[JsonNode, string] {.raises: [CatchableError, OSError, Exception].} =
      err("fixture: patch not used")
    let empty = LedgerTransport(fetch: fetcher, post: dummypost, patch: dummypatch, tip: tipper)
    let res = scanLedgerContinuityCertNode(empty, ScanHead, "owner/repo")
    check res.isOk
    check res.get.isNone

# ---------------------------------------------------------------------------
# ADR-0032 admission venue split — preflight is an explicit, NON-canonical
# opt-in: certRequired is suppressed only there, the machine line marks the
# venue, and preflight can never actuate a merge.
# ---------------------------------------------------------------------------

suite "ADR-0032 preflight — effectiveCertRequired + --preflight handling":
  test "canonical path keeps the certificate demand (fail-closed default unchanged)":
    check effectiveCertRequired(false) == CertRequired
    check effectiveCertRequired(false) == true

  test "explicit --preflight suppresses certRequired on the preflight venue only":
    check effectiveCertRequired(true) == false

  test "dry-run JSON marks the venue — canonical false / preflight true":
    let canonical = buildDryRunJson(42, "h", "b",
      MergeAdmissionOutcome(result: mergeGo, reasonCode: "GO", reason: "all green"),
      none(RotationAdjudication))
    check canonical["preflight"].getBool == false

    let preflight = buildDryRunJson(42, "h", "b",
      MergeAdmissionOutcome(result: mergeGo, reasonCode: "GO", reason: "all green"),
      none(RotationAdjudication), preflight = true)
    check preflight["preflight"].getBool == true

  test "--preflight + --apply is rejected outright — preflight never actuates (ADR-0032 (c))":
    check mergeCli(@["5", "--preflight", "--apply"]) == 1

# ---------------------------------------------------------------------------
# collectVaultCertFactsCore — the transport-injectable vault collector core
# (proof-required admission contract §1/§2.2, new I/O primitives ①+②).
# The live wrapper binds the GitHub contents API; these fixtures pin the
# verdict-relevant semantics: target set = changed ∩ active kernel ∩ manifest,
# per-target existence/identity facts, epoch sides from B-tree bytes vs the
# LOCAL file projection, and fail-closed reads (an error is never absence).
# ---------------------------------------------------------------------------

const VaultIrA = "c14243cdc6d5628d64cb11ff38a9b7cf5cd04a817c5ed28979cc1b0f28c24e39"
const VaultIrB = "93079fe23d613d467a95b3950f3100b89c4bf3806f3bc8ce56bad978d50acf0e"
const KernelApi = "src/core/orchestrator/orchestrator_api.nim"
const KernelTopo = "src/core/orchestrator/orchestrator_topology_worker.nim"
const KernelExempt = "src/core/sorter/sorter_core_index_table.nim"
const BaseShaFix = "base111111111111111111111111111111111111111"
const HeadShaFix = "head111111111111111111111111111111111111111"

proc localPolicyBytes(): string {.raises: [CatchableError, OSError].} =
  ## The LOCAL policy file bytes — served as the @B tree body so the epoch
  ## equality holds by construction; drift tests serve modified bytes.
  readFile("config/policy/merge_admission.json")

proc localScopeBytes(): string {.raises: [CatchableError, OSError].} =
  readFile("data/verification_scope.lock")

func scopeLockNode(kernel: seq[string]; exempt: seq[string]): JsonNode =
  %*{"schema_version": 3,
      "kernel_symbols": kernel,
      "kernel_exempt_symbols": exempt}

proc vaultFixture(scopeH: JsonNode; manifestH: JsonNode; certs: Table[string, JsonNode];
                  policyB: string = ""; scopeB: string = ""): VaultCertFetch {.raises: [CatchableError, OSError].} =
  ## Fixture transport: H serves the scope lock + manifest + cert map; B
  ## serves the given policy/scope BYTES (empty = the local file bytes —
  ## the epoch-equal construction). Missing cert path = none (404 fact).
  let policyBBytes = if policyB.len == 0: localPolicyBytes() else: policyB
  let scopeBBytes = if scopeB.len == 0: localScopeBytes() else: scopeB
  let policyNode = %*{"content": encode(policyBBytes)}
  let scopeBNode = %*{"content": encode(scopeBBytes)}
  let scopeHNode = %*{"content": encode($scopeH)}
  let manifestHNode = %*{"content": encode($manifestH)}
  let fetch: VaultCertFetch = proc(refSha: string; path: string): Result[Option[JsonNode], string]
      {.raises: [CatchableError, OSError, Exception].} =
    if refSha == BaseShaFix:
      if path == "config/policy/merge_admission.json": return ok(some(policyNode))
      if path == "data/verification_scope.lock": return ok(some(scopeBNode))
      return err("fixture: unexpected B path " & path)
    if refSha == HeadShaFix:
      if path == "data/verification_scope.lock": return ok(some(scopeHNode))
      if path == "src/verification/certificates/manifest.json": return ok(some(manifestHNode))
      if path.startsWith("src/verification/certificates/") and path.endsWith(".json"):
        let name = path[("src/verification/certificates/").len .. ^6]
        if certs.hasKey(name): return ok(some(%*{"content": encode($certs[name])}))
        return ok(none(JsonNode))
      return err("fixture: unexpected H path " & path)
    err("fixture: unexpected ref " & refSha)
  fetch

suite "collectVaultCertFactsCore — target set + identity + epoch (fixture transport)":
  let manifestH = %*{"entries": [
    {"modulePath": KernelApi, "functionName": "normalizeMaxWorkers", "irHash": VaultIrA},
    {"modulePath": KernelTopo, "functionName": "calcDynamicTimeoutCore", "irHash": VaultIrB}]}
  let goodCertA = %*{"irHash": VaultIrA, "modulePath": KernelApi}
  let goodCertB = %*{"irHash": VaultIrB, "modulePath": KernelTopo}
  let activeScope = scopeLockNode(
    @[KernelApi & "::normalizeMaxWorkers", KernelTopo & "::calcDynamicTimeoutCore",
      KernelExempt & "::hasVaultEntry"],
    @[KernelExempt & "::hasVaultEntry"])

  test "no changed files → ok(none) (recorded skip)":
    let res = collectVaultCertFactsCore(BaseShaFix, HeadShaFix, @[], vaultFixture(activeScope, manifestH, initTable[string, JsonNode]()))
    check res.isOk
    check res.get.isNone

  test "changed kernel module with present matching cert → bound fact, epoch equal":
    var certs = initTable[string, JsonNode]()
    certs[VaultIrA] = goodCertA
    let res = collectVaultCertFactsCore(BaseShaFix, HeadShaFix, @["docs/x.md", KernelApi],
      vaultFixture(activeScope, manifestH, certs))
    check res.isOk
    check res.get.isSome
    let fact = res.get.get
    check fact.targets.len == 1
    check fact.targets[0].modulePath == KernelApi
    check fact.targets[0].functionName == "normalizeMaxWorkers"
    check fact.targets[0].certPresent == true
    check fact.targets[0].irHashMatch == true
    check fact.policyEpochDigest == fact.currentPolicyDigest
    check fact.scopeEpochDigest == fact.currentScopeDigest

  test "cert absent at H → certPresent=false fact (predicate: NO_CERT)":
    let res = collectVaultCertFactsCore(BaseShaFix, HeadShaFix, @[KernelApi],
      vaultFixture(activeScope, manifestH, initTable[string, JsonNode]()))
    check res.isOk
    let fact = res.get.get
    check fact.targets.len == 1
    check fact.targets[0].certPresent == false
    check fact.targets[0].irHashMatch == false

  test "cert present but content irHash != manifest irHash → irHashMatch=false (predicate: SUBJECT_MISMATCH)":
    var certs = initTable[string, JsonNode]()
    certs[VaultIrA] = %*{"irHash": "deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"}
    let res = collectVaultCertFactsCore(BaseShaFix, HeadShaFix, @[KernelApi],
      vaultFixture(activeScope, manifestH, certs))
    check res.isOk
    let fact = res.get.get
    check fact.targets[0].certPresent == true
    check fact.targets[0].irHashMatch == false

  test "exempt symbol excluded; non-kernel manifest entry excluded":
    # manifest entry for an EXEMPT symbol must not become a target even when
    # its module changes; a changed module with NO manifest entry is silent.
    let manifestH2 = %*{"entries": [
      {"modulePath": KernelExempt, "functionName": "hasVaultEntry", "irHash": VaultIrA}]}
    var certs = initTable[string, JsonNode]()
    certs[VaultIrA] = goodCertA
    let res = collectVaultCertFactsCore(BaseShaFix, HeadShaFix, @[KernelExempt, KernelApi],
      vaultFixture(activeScope, manifestH2, certs))
    check res.isOk
    check res.get.isNone  # exempt entry excluded; KernelApi has no manifest entry

  test "multiple targets sorted by (modulePath, functionName)":
    var certs = initTable[string, JsonNode]()
    certs[VaultIrA] = goodCertA
    certs[VaultIrB] = goodCertB
    let res = collectVaultCertFactsCore(BaseShaFix, HeadShaFix, @[KernelTopo, KernelApi],
      vaultFixture(activeScope, manifestH, certs))
    check res.isOk
    let fact = res.get.get
    check fact.targets.len == 2
    check fact.targets[0].modulePath == KernelApi
    check fact.targets[1].modulePath == KernelTopo

  test "policy@B drift → epoch inequality (predicate: POLICY_MISMATCH)":
    var certs = initTable[string, JsonNode]()
    certs[VaultIrA] = goodCertA
    let res = collectVaultCertFactsCore(BaseShaFix, HeadShaFix, @[KernelApi],
      vaultFixture(activeScope, manifestH, certs, policyB = localPolicyBytes() & "\n"))
    check res.isOk
    let fact = res.get.get
    check fact.policyEpochDigest != fact.currentPolicyDigest

  test "scope lock absent at H → err (run-level, never absence)":
    let fetch: VaultCertFetch = proc(refSha: string; path: string): Result[Option[JsonNode], string]
        {.raises: [CatchableError, OSError, Exception].} =
      ok(none(JsonNode))
    let res = collectVaultCertFactsCore(BaseShaFix, HeadShaFix, @[KernelApi], fetch)
    check res.isErr
    check res.error.contains("verification_scope.lock absent")

  test "cert read failure → err (fail-closed: an error is never a 404 fact)":
    let fetch: VaultCertFetch = proc(refSha: string; path: string): Result[Option[JsonNode], string]
        {.raises: [CatchableError, OSError, Exception].} =
      if refSha == HeadShaFix and path == "data/verification_scope.lock":
        return ok(some(%*{"content": encode($activeScope)}))
      if refSha == HeadShaFix and path == "src/verification/certificates/manifest.json":
        return ok(some(%*{"content": encode($manifestH)}))
      if refSha == BaseShaFix:
        return ok(some(%*{"content": encode(localPolicyBytes())}))
      err("fixture: transport down")
    let res = collectVaultCertFactsCore(BaseShaFix, HeadShaFix, @[KernelApi], fetch)
    check res.isErr
    check res.error.contains("vault cert read failed")

  test "parseActiveKernelSymbols: missing list / malformed entry → err":
    check parseActiveKernelSymbols(%*{"kernel_symbols": ["a::b"]}).isErr
    check parseActiveKernelSymbols(%*{"kernel_symbols": ["a::b"], "kernel_exempt_symbols": "nope"}).isErr
    check parseActiveKernelSymbols(%*{"kernel_symbols": [42], "kernel_exempt_symbols": []}).isErr
    let r = parseActiveKernelSymbols(scopeLockNode(@["a::b", "c::d"], @["c::d"]))
    check r.isOk
    check (not r.get.contains("c::d")) and r.get.contains("a::b")

  test "vaultManifestIndex: malformed entry → err; well-formed sorted":
    check vaultManifestIndex(%*{"entries": [{"modulePath": "a"}]}).isErr
    check vaultManifestIndex(%*{"entries": "nope"}).isErr
    let r = vaultManifestIndex(%*{"entries": [
      {"modulePath": "z.nim", "functionName": "b", "irHash": "i2"},
      {"modulePath": "a.nim", "functionName": "c", "irHash": "i1"},
      {"modulePath": "z.nim", "functionName": "a", "irHash": "i3"}]})
    check r.isOk
    check r.get.len == 3
    check r.get[0].modulePath == "a.nim"
    check r.get[1].functionName == "a"
    check r.get[2].irHash == "i2"

# ---------------------------------------------------------------------------
# Pass 2.75 (H2) — the single ④ POLICY DENY SITE, asserted at the verdict
# level (the judgment layer). 4-class contract (see adjudicateRotation /
# MergeAdmissible docstrings): policy deny @H2 · policy deny @ladder/passes ·
# upper fail-closed boundary · policy route exit-0 (TRUST_SURFACE_MODIFIED).
# ---------------------------------------------------------------------------

func tamperRotation(): RotationAdjudication {.raises: [].} =
  ## NORMAL-class subject with a tampered pin@H — the hole being closed.
  var s = initHashSet[string]()
  s.incl("100644 blob a1\tci/checker.mk")
  let evil = initHashSet[string]()
  adjudicateRotation(s, s, s, some(s), some(evil), @[RotationPinBPath])

suite "Pass 2.75 — H2 single ④ policy deny (verdict level)":
  test "NORMAL + ④-pass + isSome → GO (H2 silent — ordinary NORMAL is not denied)":
    var f = factsWith("h", goValidations)
    f.rotation = some(normalRotation())
    let rec = VerificationRecord(headSha: "h", baseSha: "b",
      requiredChecks: @[okCheck], admission: some(f))
    let o = MergeAdmissible(rec, "b")
    check o.result == mergeGo
    check dryRunExit(o) == 0

  test "NORMAL + ④-fail + isSome → DENY ROT_NEW_PIN, exit 1 (the repaired hole)":
    var f = factsWith("h", goValidations)
    f.rotation = some(tamperRotation())
    let rec = VerificationRecord(headSha: "h", baseSha: "b",
      requiredChecks: @[okCheck], admission: some(f))
    let o = MergeAdmissible(rec, "b")
    check o.result == mergeAborted
    check o.reasonCode == "ROT_NEW_PIN"
    check dryRunExit(o) == 1

  test "trust-surface hit + ④-fail + isSome → DENY ROT_NEW_PIN (H2 outranks the exit-0 manual route)":
    var f = factsWith("h", goValidations)
    f.rotation = some(tamperRotation())
    f.trustSurfaceHits = @[TrustSurfaceHit(path: ".github/workflows/ci.yml",
                                           renamedFrom: "")]
    let rec = VerificationRecord(headSha: "h", baseSha: "b",
      requiredChecks: @[okCheck], admission: some(f))
    let o = MergeAdmissible(rec, "b")
    check o.result == mergeAborted
    check o.reasonCode == "ROT_NEW_PIN"
    check dryRunExit(o) == 1

  test "ROTATION + ④-fail + ①-fail → DENY with the ladder-selected code (④ outranks ①: ROT_NEW_PIN)":
    # Precedence pin (Amendment F ladder: ③ → ④ → classification → ①): when
    # ④ AND ① both fail, the recorded reason is the LADDER's — the ④
    # annotation (step 3) is ABOVE the ① allowlist (step 5), so it is NOT
    # overwritten; Pass 2.75 (which runs before Pass 2.97) reuses it verbatim.
    # The RETIRED contract recorded ROT_ALLOWLIST here (old order ①→③→④);
    # the fixture pins ③ as holding (pinB == derivedB) so the ④-vs-①
    # selection is isolated.
    var s = initHashSet[string]()
    s.incl("100644 blob a1\tci/checker.mk")
    var h = initHashSet[string]()
    h.incl("100644 blob a1\tci/checker.mk")
    var extra = initHashSet[string]()
    extra.incl("100644 blob a1\tci/checker.mk")
    extra.incl("100644 blob b2\ttools/ci/derive_checker_closure.nim")
    let adj = adjudicateRotation(s, h, extra, some(h), some(initHashSet[string]()),
      @["src/not_in_allowlist.nim"])
    check adj.check.closureChange      # derivedM(extra) != derivedB(h) → ROTATION subject
    check adj.check.oldAnchorOk        # ③ holds — isolated from the selection
    check not adj.check.newAnchorOk    # ④ failed (pin@H ∅ != derived H)
    check not adj.check.allowlistOk    # ① failed too — but below ④ in the ladder
    check adj.qualification == rqNone  # a ladder condition failed (①)
    check adj.reasonCode == "ROT_NEW_PIN"  # the ④ annotation survives
    var f = factsWith("h", goValidations)
    f.rotation = some(adj)
    let rec = VerificationRecord(headSha: "h", baseSha: "b",
      requiredChecks: @[okCheck], admission: some(f))
    let o = MergeAdmissible(rec, "b")
    check o.reasonCode == "ROT_NEW_PIN"
    check dryRunExit(o) == 1

  test "judge.source fingerprint is present and deterministic (SHA-256 of the judged source)":
    let j = buildDryRunJson(42, "h", "b",
      MergeAdmissionOutcome(result: mergeGo), some(normalRotation()))
    check j.hasKey("judge")
    check j["judge"].hasKey("source")
    check j["judge"]["source"].getStr.len == 64   # SHA-256 hex
    # Deterministic and bound to THIS source: the same bytes always hash alike.
    check j["judge"]["source"].getStr == judgeSourceFingerprint()

# ---------------------------------------------------------------------------
# VS-1 single-judgment refactor: the H2 (④ new anchor) judgment lives ONCE —
# newAnchorVerdict in core/policy/rotation_closure_facts — and BOTH the
# landing predicate (annotateNewAnchor fact annotation + the Pass 2.75 deny)
# and the rotation preflight checker (tools/ci/rotation_pin_anchor_check.nim)
# consume that one compiled implementation. The suites below pin (a) the
# exact semantics + reason strings and (b) the drift-proof invariant:
# checker exit==0 ⇔ adjudicateRotation(...).check.newAnchorOk.
# ---------------------------------------------------------------------------

proc pinDocText(keyPresent: bool; lines: HashSet[string]): string =
  ## Serialize a trusted_writer_set document from a line-set — the JSON the
  ## shared pinClosureLineSet parses back.
  var doc = %*{"schema": 1}
  if keyPresent:
    var entries = newJObject()
    for ln in lines:
      let i = ln.rfind('\t')
      let triple = ln[0 ..< i].split(' ')
      entries[closurePathFromLine(ln)] =
        %*{"mode": triple[0], "type": triple[1], "sha": triple[2]}
    doc[RotationPinKey] = entries
  $doc

proc derivedText(lines: HashSet[string]): string =
  var parts: seq[string]
  for ln in lines:
    parts.add(ln)
  parts.join("\n")

proc checkerVerdict(h, b, m: HashSet[string];
                    pinBKeys, pinHKeys: Option[HashSet[string]];
                    changed: seq[string]):
    tuple[adj: RotationAdjudication, outcome: CheckOutcome] =
  ## One fixture row judged by BOTH consumers: the landing adjudication and
  ## the preflight checker's text-level core.
  let adj = adjudicateRotation(h, b, m, pinBKeys, pinHKeys, changed)
  let outcome = evaluatePinAnchorTexts(
    derivedText(h),
    if pinHKeys.isSome: pinDocText(true, pinHKeys.get)
    else: pinDocText(false, initHashSet[string]()),
    if pinBKeys.isSome: pinDocText(true, pinBKeys.get)
    else: pinDocText(false, initHashSet[string]()))
  (adj, outcome)

suite "newAnchorVerdict — the H2 (④) condition, exact semantics + reason strings":
  test "pin@H == derived(H) → ok, empty annotation":
    let h = lineSet("100644 blob a1\tci/checker.mk")
    let v = newAnchorVerdict(h, some(h), some(h))
    check v.ok
    check v.code == ""
    check v.reason == ""

  test "pin@H line-set mismatch → ROT_NEW_PIN (pin@B present)":
    let d = lineSet("100644 blob a1\tci/checker.mk")
    let p = lineSet("100644 blob ZZ\tci/checker.mk")
    let v = newAnchorVerdict(d, some(p), some(d))
    check not v.ok
    check v.code == "ROT_NEW_PIN"
    check v.reason == "pin anchor invalid: line-set(pin@H) != set(derived H) — " &
      "the pin must anchor exactly H (fail-closed)"

  test "pin@H key absent + pin@B key absent → ROT_GENESIS_INVALID":
    let d = lineSet("100644 blob a1\tci/checker.mk")
    let v = newAnchorVerdict(d, none(HashSet[string]), none(HashSet[string]))
    check not v.ok
    check v.code == "ROT_GENESIS_INVALID"
    check v.reason == "genesis pin anchor invalid: pin@H missing or line-set(pin@H) != set(derived H) — " &
      "the one-time genesis exception cannot be established (fail-closed)"

  test "genesis is decided by pin@B alone: pin@H absent + pin@B present → ROT_NEW_PIN":
    let d = lineSet("100644 blob a1\tci/checker.mk")
    let v = newAnchorVerdict(d, none(HashSet[string]), some(d))
    check not v.ok
    check v.code == "ROT_NEW_PIN"

suite "checker↔predicate equivalence — checker exit==0 ⇔ check.newAnchorOk (VS-1)":
  test "NORMAL, ④ holds → both PASS":
    let h = lineSet("100644 blob a1\tci/checker.mk")
    let (adj, outcome) = checkerVerdict(h, h, h, some(h), some(h), @[])
    check adj.qualification == rqNormal
    check adj.check.newAnchorOk
    check outcome.exitCode == ExitPass
    check (outcome.exitCode == ExitPass) == adj.check.newAnchorOk

  test "ROTATION, ④ holds → both PASS":
    let h = lineSet("100644 blob a1\tci/checker.mk",
                    "100644 blob b2\ttools/ci/derive_checker_closure.nim")
    let b = lineSet("100644 blob a1\tci/checker.mk")
    # changed = a pin@B closure-member path → ① holds → the ROTATION class
    # survives the ladder (tools/ci/derive_checker_closure.nim is NOT an A2
    # companion — the earlier draft of this row denied on ①, rqNone).
    let (adj, outcome) = checkerVerdict(h, b, h, some(b), some(h), @["ci/checker.mk"])
    check adj.qualification == rqRotation
    check adj.check.newAnchorOk
    check outcome.exitCode == ExitPass
    check (outcome.exitCode == ExitPass) == adj.check.newAnchorOk

  test "NORMAL, ④ fails (content tamper) → both FAIL ROT_NEW_PIN":
    let h = lineSet("100644 blob a1\tci/checker.mk")
    let tampered = lineSet("100644 blob ZZ\tci/checker.mk")
    let (adj, outcome) = checkerVerdict(h, h, h, some(h), some(tampered), @[])
    check not adj.check.newAnchorOk
    check adj.reasonCode == "ROT_NEW_PIN"
    check outcome.exitCode == ExitH2Fail
    check outcome.line.contains("H2 FAIL code=ROT_NEW_PIN")
    check outcome.line.contains(
      "reason=pin anchor invalid: line-set(pin@H) != set(derived H)")

  test "ROTATION, ④ fails → both FAIL ROT_NEW_PIN":
    let h = lineSet("100644 blob a1\tci/checker.mk",
                    "100644 blob b2\ttools/ci/derive_checker_closure.nim")
    let b = lineSet("100644 blob a1\tci/checker.mk")
    let tampered = lineSet("100644 blob a1\tci/checker.mk",
                           "100644 blob ZZ\ttools/ci/derive_checker_closure.nim")
    let (adj, outcome) = checkerVerdict(h, b, h, some(b), some(tampered),
                                        @["ci/checker.mk"])
    check adj.qualification == rqRotation
    check not adj.check.newAnchorOk
    check outcome.exitCode == ExitH2Fail
    check outcome.line.contains("H2 FAIL code=ROT_NEW_PIN")
    check (outcome.exitCode == ExitPass) == adj.check.newAnchorOk

  test "genesis pin@B + anchored pin@H → ④ holds → both PASS":
    let h = lineSet("100644 blob a1\tci/checker.mk")
    let (adj, outcome) = checkerVerdict(h, h, h, none(HashSet[string]), some(h), @[])
    check adj.check.genesis
    check adj.check.newAnchorOk
    check outcome.exitCode == ExitPass
    check (outcome.exitCode == ExitPass) == adj.check.newAnchorOk

  test "genesis pin@B + pin@H absent → both FAIL ROT_GENESIS_INVALID":
    let h = lineSet("100644 blob a1\tci/checker.mk")
    let (adj, outcome) = checkerVerdict(h, h, h, none(HashSet[string]),
                                        none(HashSet[string]), @[])
    check adj.check.genesis
    check not adj.check.newAnchorOk
    check adj.reasonCode == "ROT_GENESIS_INVALID"
    check outcome.exitCode == ExitH2Fail
    check outcome.line.contains("H2 FAIL code=ROT_GENESIS_INVALID")
    check (outcome.exitCode == ExitPass) == adj.check.newAnchorOk

  test "③ deny row: the checker judges H2 ONLY — exit==0 ⇔ newAnchorOk, ROT_OLD_PIN stays the landing ladder's":
    let h = lineSet("100644 blob a1\tci/checker.mk")
    let driftedB = lineSet("100644 blob DR\tci/checker.mk")
    let (adj, outcome) = checkerVerdict(h, h, h, some(driftedB), some(h), @[])
    check not adj.check.oldAnchorOk
    check adj.qualification == rqNone
    check adj.reasonCode == "ROT_OLD_PIN"   # ③ overwrote the ④ annotation
    check adj.check.newAnchorOk             # ④ is an every-path FACT
    check outcome.exitCode == ExitPass      # H2 holds — the checker never denies ③
    check (outcome.exitCode == ExitPass) == adj.check.newAnchorOk

# ---------------------------------------------------------------------------
# RequiredWorkflowIds — the v1.19.0 path-identity binding (hybrid authority
# rotation): the mirror binds (job, workflowPath); the numeric workflow id is
# an observed-at record in the policy SSOT, never a binding here.
# ---------------------------------------------------------------------------
suite "RequiredWorkflowIds — the v1.19.0 path-identity mirror":
  test "every binding is a (job, workflowPath) pair with a workflow file path":
    check RequiredWorkflowIds.len == 4
    for b in RequiredWorkflowIds:
      check b.jobName.len > 0
      check b.workflowPath.startsWith(".github/workflows/")
      check b.workflowPath.endsWith(".yml")
  test "the jobs are exactly the repo-native required contexts":
    var jobs: seq[string] = @[]
    for b in RequiredWorkflowIds:
      jobs.add(b.jobName)
    jobs.sort()
    check jobs == @["axiom-operational-slice", "bsec-integrity",
                    "debt-registry-gate", "generation-acceptance"]
  test "no numeric workflow id remains as a binding (ids are observed-at records)":
    for b in RequiredWorkflowIds:
      check b.workflowPath != "381835906"
      check b.workflowPath != "389486255"
      check b.workflowPath != "392117427"
      check b.workflowPath != "392498537"
