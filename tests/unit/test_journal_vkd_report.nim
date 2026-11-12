{.push raises: [CatchableError].}

## Journal-driven VKD admission — regression tests.
##
## `ax report` computes VKD from the authoritative TrustCommit journal
## (data/trusted/journal), NOT from the reference vault or the L1 cache.
## These tests exercise cert_reconcile.computeJournalVkdAdmission and the
## report-facing proof_hydration.getCanonicalVkdMetrics against real temp-dir
## fixture repos: journal records written via commitVerification, a
## verification_scope.lock denominator, and module source files whose bytes
## control the source fingerprint.  No mocks, no network, no repo mutation.
##
## Covered contracts:
##   - journal-only v1 full-cert certGreen claim is counted (no vault, no cache)
##   - a symbol with no journal record is not counted
##   - stale source / stale semantic profile / stale toolchain are excluded
##   - duplicate identical records dedup to ONE count (identityDigest)
##   - two distinct eligible full-cert claims → UNKNOWN/ambiguous, not counted
##   - a matching tcQuarantine record excludes the evidence
##   - v2 compact `entries[]` checkpoints never admit

import std/[os, json, strutils, unittest, times, options]
import ../../src/core/results
import ../../src/core/crypto/hash_kernel
import ../../src/core/trusted/trust_commit
import ../../src/core/trusted/completeness_binding
import ../../src/core/trusted/semantic_fact_types
import ../../src/core/proof/source_fingerprint
import ../../src/core/proof/proof_integrity
import ../../src/core/trusted/fingerprint_generator
import ../../src/core/trusted/semantic_profile
import ../../src/verification/cert_reconcile
import ../../src/verification/certificate_identity
import ../../src/infrastructure/evidence_artifact_io
import ../../src/cli/shared/proof_hydration

const ModulePath = "src" / "m.nim"
const FixtureSource = "proc f*() = discard\n"
const FnName = "f"
const Symbol = "src/m.nim::f"

var fixtureCounter = 0
var origAxiomRoot = ""

proc pointAxiomRoot(dir: string) =
  ## AXIOM_ROOT makes resolveRepoRoot() (used inside verifyCertificateClosure
  ## for journal binding and inside isVkdAdmissible for source staleness)
  ## resolve to the fixture repo.
  if origAxiomRoot.len == 0:
    origAxiomRoot = getEnv("AXIOM_ROOT", "")
  putEnv("AXIOM_ROOT", dir)

proc restoreAxiomRoot() =
  if origAxiomRoot.len > 0:
    putEnv("AXIOM_ROOT", origAxiomRoot)
  else:
    delEnv("AXIOM_ROOT")
  origAxiomRoot = ""

var origStateDir = ""

proc pointStateDir(dir: string) =
  ## AXIOM_STATE_DIR anchors the CompletenessBinding artifact cache
  ## (.axiom/cache/evidence/<key>.binding.json) — the SAME resolution the
  ## product admission path uses.
  if origStateDir.len == 0:
    origStateDir = getEnv("AXIOM_STATE_DIR", "")
  putEnv("AXIOM_STATE_DIR", dir)

proc restoreStateDir() =
  if origStateDir.len > 0:
    putEnv("AXIOM_STATE_DIR", origStateDir)
  else:
    delEnv("AXIOM_STATE_DIR")
  origStateDir = ""

var origStrictEnv = ""

proc pointStrictEnv(active: bool) =
  if origStrictEnv.len == 0:
    origStrictEnv = getEnv("AXIOM_EVIDENCE_STRICT", "")
  putEnv("AXIOM_EVIDENCE_STRICT", if active: "1" else: "")

proc restoreStrictEnv() =
  if origStrictEnv.len > 0:
    putEnv("AXIOM_EVIDENCE_STRICT", origStrictEnv)
  else:
    delEnv("AXIOM_EVIDENCE_STRICT")
  origStrictEnv = ""

proc newFixture(sourceContent: string = FixtureSource): string =
  ## A fresh fixture repo: scope lock (|VKS| = 1), module source, no journal,
  ## no certificate vault, no L1 cache.
  inc fixtureCounter
  let dir = getTempDir() / ("axiom_journal_vkd_test_" & $fixtureCounter & "_" & $epochTime().int)
  createDir(dir / "data")
  createDir(dir / "src")
  writeFile(dir / "src" / "m.nim", sourceContent)
  let lock = %*{
    "kernel_total": 1,
    "vksTotal": 1,
    "kernel_symbols": @[Symbol],
    "kernel_exempt_symbols": @[]
  }
  writeFile(dir / "data" / "verification_scope.lock", $lock)
  pointAxiomRoot(dir)
  dir

proc fixtureScope(): KernelScopeInfo =
  KernelScopeInfo(
    kernelSymbols: @[Symbol],
    kernelTotal: 1,
    vksTotal: 1,
    kernelExemptSymbols: @[])

proc makeFullCertClaim(irHash: string; sourceContent: string = FixtureSource;
                       toolchain: JsonNode = currentJournalToolchainPin();
                       profile: string = SemanticProfileV1Hash): JsonNode =
  ## Build a v1 flat full-cert claim that passes verifyCertificateClosure and
  ## isVkdAdmissible for the fixture module bytes.
  let sourceHash = computeStableSourceFingerprint(sourceContent)
  let solverStatus = "unsat"
  let status = "certGreen"
  let winningStrategy = "lean-replay"
  let inputHash = "sha256:fixture-input"
  let solverInputDigest = "sha256:fixture-sinput"
  let solverResultDigest = "sha256:fixture-sresult"
  result = %*{
    "schemaVersion": "axiom.certificate.v3",
    "modulePath": ModulePath,
    "functionName": FnName,
    "sourceHash": sourceHash,
    "irHash": irHash,
    "leanProposition": "",
    "solverStatus": solverStatus,
    "status": status,
    "winningStrategy": winningStrategy,
    "inputHash": inputHash,
    "solverInputDigest": solverInputDigest,
    "solverResultDigest": solverResultDigest,
    "kernel": true,
    "solverMeta": %*{
      "leanCompilerVerified": true,
      "z3Executed": true,
      "vacuityChecked": true
    },
    "smtlib2": "(assert true)",
    "toolchainIdentity": toolchain,
    "semanticProfileId": profile
  }
  result["fingerprint"] = %* computeVerificationFingerprint(irHash, "")
  result["identityDigest"] = %* compV3Identity(V3IdentityState(
    schemaVersion: "axiom.certificate.v3",
    modulePath: ModulePath,
    functionName: FnName,
    sourceHash: sourceHash,
    irHash: irHash,
    leanProposition: "",
    solverStatus: solverStatus,
    status: status,
    winningStrategy: winningStrategy,
    inputHash: inputHash,
    solverInputDigest: solverInputDigest,
    solverResultDigest: solverResultDigest
  ))

proc writeJournalRecord(baseDir: string; claim: JsonNode;
                        invocation: string = "batch-uap-loop"): string =
  ## Commit a tcVerifiedProof record for `claim` into the fixture journal and
  ## return the commitId. `invocation` differentiates commits of identical
  ## claims (distinct evidenceId/commitId, same certificate identity).
  let tc = trustCommitFromJson(claim, invocation,
    "journal-vkd regression fixture", ModulePath, FnName, "unsat", "", "", "")
  commitVerification(baseDir, tc).value

proc writeQuarantineRecord(baseDir: string; modulePath, functionName,
                           sourceHash: string): string =
  ## Commit a tcQuarantine record binding (identity, sourceHash).
  let q = %*{
    "modulePath": modulePath,
    "functionName": functionName,
    "sourceHash": sourceHash,
    "status": "certPending"
  }
  let tc = quarantineTrustCommit(q, "regression-fixture-quarantine", "certGreen")
  commitVerification(baseDir, tc).value

proc admissionForResult(fixtureRoot: string): Result[
    cert_reconcile.JournalVkdAdmission, string] =
  computeJournalVkdAdmission(fixtureRoot, fixtureScope(), fixtureRoot)

suite "Journal-driven VKD admission (ax report authority)":

  test "journal-only v1 full-cert certGreen claim is counted (no vault, no L1 cache)":
    let root = newFixture()
    defer: restoreAxiomRoot()
    discard writeJournalRecord(root, makeFullCertClaim(irHash = "a" & repeat("1", 63)))
    let admissionRes = admissionForResult(root)
    check admissionRes.ok
    let admission = admissionRes.value
    check admission.counted == 1
    check admission.verdicts.len == 1
    check admission.verdicts[0].outcome == jvCounted
    check admission.verdicts[0].symbol == Symbol
    # Report path: the canonical metrics see the journal evidence with the
    # reference vault and L1 cache entirely absent from the fixture.
    let metrics = getCanonicalVkdMetrics(root)
    check metrics.failed == false
    check metrics.verifiedCount == 1
    check metrics.totalCount == 1  # denominator |VKS| from the fixture lock

  test "missing journal record is not counted (0/|VKS|, not failed)":
    let root = newFixture()
    defer: restoreAxiomRoot()
    let admissionRes = admissionForResult(root)
    check admissionRes.ok
    let admission = admissionRes.value
    check admission.counted == 0
    check admission.verdicts.len == 0
    let metrics = getCanonicalVkdMetrics(root)
    check metrics.failed == false
    check metrics.verifiedCount == 0
    check metrics.totalCount == 1

  test "stale source (sourceHash != current fingerprint) is excluded":
    # NOTE: the stable fingerprint normalizes blank/#-comment lines, so the
    # drift must change CODE to be observable.
    let root = newFixture(sourceContent = "proc f*() = discard 1\n")
    defer: restoreAxiomRoot()
    # Claim bound to the ORIGINAL bytes, fixture holds drifted bytes.
    discard writeJournalRecord(root,
      makeFullCertClaim(irHash = "b" & repeat("2", 63), sourceContent = FixtureSource))
    let admissionRes = admissionForResult(root)
    check admissionRes.ok
    let admission = admissionRes.value
    check admission.counted == 0
    check admission.verdicts[0].outcome == jvNoCurrentEvidence

  test "stale semanticProfileId is excluded":
    let root = newFixture()
    defer: restoreAxiomRoot()
    discard writeJournalRecord(root,
      makeFullCertClaim(irHash = "c" & repeat("3", 63), profile = "stale-profile"))
    let admissionRes = admissionForResult(root)
    check admissionRes.ok
    let admission = admissionRes.value
    check admission.counted == 0
    check admission.verdicts[0].outcome == jvNoCurrentEvidence

  test "stale toolchainIdentity is excluded":
    let root = newFixture()
    defer: restoreAxiomRoot()
    var stalePin = currentJournalToolchainPin()
    stalePin["lean"] = newJString("9.9.9")
    discard writeJournalRecord(root,
      makeFullCertClaim(irHash = "d" & repeat("4", 63), toolchain = stalePin))
    let admissionRes = admissionForResult(root)
    check admissionRes.ok
    let admission = admissionRes.value
    check admission.counted == 0
    check admission.verdicts[0].outcome == jvNoCurrentEvidence

  test "duplicate identical records dedup to ONE count":
    let root = newFixture()
    defer: restoreAxiomRoot()
    let claim = makeFullCertClaim(irHash = "e" & repeat("5", 63))
    # Same claim content committed twice with different invocation metadata:
    # distinct evidenceId/commitId, identical identityDigest → ONE identity.
    let cid1 = writeJournalRecord(root, claim, invocation = "invocation-one")
    let cid2 = writeJournalRecord(root, claim, invocation = "invocation-two")
    check cid1 != cid2
    let admissionRes = admissionForResult(root)
    check admissionRes.ok
    let admission = admissionRes.value
    check admission.counted == 1
    check admission.verdicts.len == 1
    check admission.verdicts[0].outcome == jvCounted
    check admission.verdicts[0].identityDigest ==
      claim.getOrDefault("identityDigest").getStr("")

  test "same function-level evidence under a different tree identity dedups to ONE count":
    let root = newFixture()
    defer: restoreAxiomRoot()
    let claimA = makeFullCertClaim(irHash = "1" & repeat("8", 63))
    var claimB = makeFullCertClaim(irHash = "1" & repeat("8", 63))
    # Re-attestation on a different subject-tree snapshot: evidenceId (the
    # tree-bound evidence identity) changes, every function-level field stays
    # identical. This must be ONE claim, not UNKNOWN.
    claimB["evidenceId"] = %* "tree-b-evidence-identity"
    claimB["identityDigest"] = %* v3IdentityFromJson(claimB)
    discard writeJournalRecord(root, claimA)
    discard writeJournalRecord(root, claimB)
    let admissionRes = admissionForResult(root)
    check admissionRes.ok
    let admission = admissionRes.value
    check admission.counted == 1
    check admission.verdicts.len == 1
    check admission.verdicts[0].outcome == jvCounted

  test "two distinct eligible full-cert claims → UNKNOWN/ambiguous, not counted":
    let root = newFixture()
    defer: restoreAxiomRoot()
    discard writeJournalRecord(root, makeFullCertClaim(irHash = "f" & repeat("6", 63)))
    discard writeJournalRecord(root, makeFullCertClaim(irHash = "0" & repeat("7", 63)))
    let admissionRes = admissionForResult(root)
    check admissionRes.ok
    let admission = admissionRes.value
    check admission.counted == 0
    check admission.verdicts.len == 1
    check admission.verdicts[0].outcome == jvAmbiguous
    check admission.verdicts[0].variantCount == 2
    check admission.verdicts[0].identityDigests.len == 2
    let metrics = getCanonicalVkdMetrics(root)
    check metrics.failed == false
    check metrics.verifiedCount == 0
    check metrics.totalCount == 1

  test "matching tcQuarantine record excludes the evidence":
    let root = newFixture()
    defer: restoreAxiomRoot()
    let claim = makeFullCertClaim(irHash = "9" & repeat("8", 63))
    discard writeJournalRecord(root, claim)
    discard writeQuarantineRecord(root, ModulePath, FnName,
      claim.getOrDefault("sourceHash").getStr(""))
    let admissionRes = admissionForResult(root)
    check admissionRes.ok
    let admission = admissionRes.value
    check admission.counted == 0
    check admission.verdicts[0].outcome == jvNoCurrentEvidence

  test "v2 compact entries[] checkpoint never admits":
    let root = newFixture()
    defer: restoreAxiomRoot()
    # A checkpoint claiming certGreen for the symbol in the compact shape —
    # no sourceHash/toolchain/profile; catalog only, never admission.
    let checkpoint = %*{
      "version": 2,
      "entries": @[%*{
        "modulePath": ModulePath,
        "functionName": FnName,
        "status": "certGreen",
        "irHash": "a" & repeat("1", 63),
        "lastVerifiedAt": "2026-10-19T00:00:00Z"
      }]
    }
    discard writeJournalRecord(root, checkpoint)
    let admissionRes = admissionForResult(root)
    check admissionRes.ok
    let admission = admissionRes.value
    check admission.counted == 0
    check admission.verdicts.len == 0  # never entered admission as a full-cert claim
    let metrics = getCanonicalVkdMetrics(root)
    check metrics.failed == false
    check metrics.verifiedCount == 0

  test "currentJournalToolchainPin is well-formed and stable within a build":
    let pin = currentJournalToolchainPin()
    check pin.kind == JObject
    check pin{"nim"}.getStr("").len > 0
    check pin{"lean"}.getStr("").len > 0
    check pin{"z3"}.getStr("").len > 0
    check toolchainIdentityMatchesPin(pin)
    var missing = %*{"nim": pin["nim"]}
    check toolchainIdentityMatchesPin(missing) == false

  test "non-certGreen full-cert claims are excluded":
    let root = newFixture()
    defer: restoreAxiomRoot()
    var claim = makeFullCertClaim(irHash = "a" & repeat("9", 63))
    claim["status"] = newJString("certZ3Candidate")
    claim["identityDigest"] = %* compV3Identity(V3IdentityState(
      schemaVersion: "axiom.certificate.v3",
      modulePath: ModulePath,
      functionName: FnName,
      sourceHash: claim.getOrDefault("sourceHash").getStr(""),
      irHash: claim.getOrDefault("irHash").getStr(""),
      leanProposition: "",
      solverStatus: "unsat",
      status: "certZ3Candidate",
      winningStrategy: "lean-replay",
      inputHash: "sha256:fixture-input",
      solverInputDigest: "sha256:fixture-sinput",
      solverResultDigest: "sha256:fixture-sresult"
    ))
    discard writeJournalRecord(root, claim)
    let admissionRes = admissionForResult(root)
    check admissionRes.ok
    let admission = admissionRes.value
    check admission.counted == 0
    check admission.verdicts[0].outcome == jvNoCurrentEvidence

  # ─── Phase 1B: strict completeness contract + measured engineBuild ──────

  proc saveFixtureBinding(key, irHash: string; ctx: cert_reconcile.StrictCompletenessContext;
                          payloadDigest: var string;
                          toolchainFingerprint = "";
                          irDigestCanonical = "";
                          irDigest = ""): bool =
    ## Save a strict CompletenessBinding bound to the CURRENT measured fixture
    ## context. `toolchainFingerprint`/`irDigestCanonical`/`irDigest` overrides
    ## let tests pin the individual mismatch directions.
    let payload = CompletenessEvidence(
      translationLossFree: true,
      bindingUniverseComplete: true,
      opaqueExpansionStatus: "none",
      sourceBindingCount: 3,
      irBindingCount: 3)
    payloadDigest = sha256Hex($evidenceToJson(payload))
    let binding = makeCompletenessBinding(
      evidenceKey = key,
      irDigest = if irDigest.len > 0: irDigest else: key,  # flavor ③ anchor
      irDigestCanonical = if irDigestCanonical.len > 0: irDigestCanonical else: irHash,
      sourceIdentity = ctx.sourceIdentity,
      subjectModuleSha256 = ctx.subjectModuleSha256,
      semanticProfileId = SemanticProfileV1Hash,
      toolchainFingerprint = if toolchainFingerprint.len > 0: toolchainFingerprint
                             else: ctx.toolchainFingerprint,
      payload = payload)
    saveCompletenessBinding(binding)

  proc makeStrictFullCertClaim(irHash: string; key, bindingDigest,
                               payloadDigest: string): JsonNode =
    ## A strict-contract (strict-v1) full-cert claim: the legacy claim plus the
    ## completeness anchor set and the 16-field strict identity.
    result = makeFullCertClaim(irHash = irHash)
    result["completenessContract"] = newJString(CompletenessContractStrictV1)
    result["completenessEvidenceKey"] = newJString(key)
    result["completenessBindingDigest"] = newJString(bindingDigest)
    result["completenessPayloadDigest"] = newJString(payloadDigest)
    result["identityDigest"] = %* v3IdentityFromJson(result)

  proc newStrictFixture(): tuple[repoRoot, journalRoot: string] =
    ## Strict fixture: repo (AXIOM_ROOT) + state dir (binding cache + journal).
    ## The journal lives UNDER $AXIOM_STATE_DIR — the same placement the
    ## product prove/report path uses (activeJournalRoot resolves the journal
    ## to the state dir), so the closure's journal binding sees the records.
    let dir = newFixture()
    pointStateDir(dir / "state")
    let journalRoot = dir / "state"
    createDir(journalRoot / "data")
    (dir, journalRoot)

  proc fixtureStrictContext(repoRoot: string): cert_reconcile.StrictCompletenessContext =
    measureStrictCompletenessContext(repoRoot, ModulePath, FixtureSource)

  proc strictAdmission(journalRoot, repoRoot: string): Result[
      cert_reconcile.JournalVkdAdmission, string] =
    computeJournalVkdAdmission(journalRoot, fixtureScope(), repoRoot)

  test "strict-contract claim with a valid binding is counted":
    let (repoRoot, journalRoot) = newStrictFixture()
    defer:
      restoreStateDir()
      restoreAxiomRoot()
    let ctx = fixtureStrictContext(repoRoot)
    check ctx.subjectModuleSha256 == sha256Hex(FixtureSource)
    var payloadDigest = ""
    let key = sha256Hex("strict-fixture-key")
    check saveFixtureBinding(key, "1" & repeat('1', 63), ctx, payloadDigest)
    let loaded = loadCompletenessBinding(key, ctx.sourceIdentity,
      ctx.subjectModuleSha256, SemanticProfileV1Hash, ctx.toolchainFingerprint)
    check loaded.isSome
    discard writeJournalRecord(journalRoot, makeStrictFullCertClaim(
      "1" & repeat('1', 63), key, loaded.get.evidenceDigest, payloadDigest))
    let admissionRes = strictAdmission(journalRoot, repoRoot)
    check admissionRes.ok
    let admission = admissionRes.value
    check admission.counted == 1
    check admission.verdicts[0].outcome == jvCounted

  test "strict-contract claim with a missing binding artifact is not counted":
    let (repoRoot, journalRoot) = newStrictFixture()
    defer:
      restoreStateDir()
      restoreAxiomRoot()
    let ctx = fixtureStrictContext(repoRoot)
    let key = sha256Hex("strict-missing-key")
    var payloadDigest = ""
    discard saveFixtureBinding(key, "2" & repeat('2', 63), ctx, payloadDigest)
    discard writeJournalRecord(journalRoot, makeStrictFullCertClaim(
      "2" & repeat('2', 63), sha256Hex("different-anchor"), repeat('a', 64),
      payloadDigest))
    let admissionRes = strictAdmission(journalRoot, repoRoot)
    check admissionRes.ok
    check admissionRes.value.counted == 0
    check admissionRes.value.verdicts[0].outcome == jvNoCurrentEvidence

  test "strict-contract claim with a tampered completenessBindingDigest is not counted":
    let (repoRoot, journalRoot) = newStrictFixture()
    defer:
      restoreStateDir()
      restoreAxiomRoot()
    let ctx = fixtureStrictContext(repoRoot)
    let key = sha256Hex("strict-tamper-key")
    var payloadDigest = ""
    check saveFixtureBinding(key, "3" & repeat('3', 63), ctx, payloadDigest)
    # Claim records a digest that is NOT the saved binding's evidenceDigest.
    discard writeJournalRecord(journalRoot, makeStrictFullCertClaim(
      "3" & repeat('3', 63), key, repeat('b', 64), payloadDigest))
    let admissionRes = strictAdmission(journalRoot, repoRoot)
    check admissionRes.ok
    check admissionRes.value.counted == 0
    check admissionRes.value.verdicts[0].outcome == jvNoCurrentEvidence

  test "strict-contract claim with a mismatched completenessPayloadDigest is not counted":
    let (repoRoot, journalRoot) = newStrictFixture()
    defer:
      restoreStateDir()
      restoreAxiomRoot()
    let ctx = fixtureStrictContext(repoRoot)
    let key = sha256Hex("strict-payload-key")
    var payloadDigest = ""
    check saveFixtureBinding(key, "4" & repeat('4', 63), ctx, payloadDigest)
    let loaded = loadCompletenessBinding(key, ctx.sourceIdentity,
      ctx.subjectModuleSha256, SemanticProfileV1Hash, ctx.toolchainFingerprint)
    check loaded.isSome
    discard writeJournalRecord(journalRoot, makeStrictFullCertClaim(
      "4" & repeat('4', 63), key, loaded.get.evidenceDigest,
      sha256Hex("foreign-payload")))
    let admissionRes = strictAdmission(journalRoot, repoRoot)
    check admissionRes.ok
    check admissionRes.value.counted == 0
    check admissionRes.value.verdicts[0].outcome == jvNoCurrentEvidence

  test "strict-contract claim bound to a stale toolchain binding is not counted":
    let (repoRoot, journalRoot) = newStrictFixture()
    defer:
      restoreStateDir()
      restoreAxiomRoot()
    let ctx = fixtureStrictContext(repoRoot)
    let key = sha256Hex("strict-toolchain-key")
    var payloadDigest = ""
    # Binding captured under a DIFFERENT toolchain fingerprint: the current
    # measured fingerprint no longer matches → none → never counted.
    check saveFixtureBinding(key, "5" & repeat('5', 63), ctx, payloadDigest,
      toolchainFingerprint = repeat('5', 64))
    let loaded = loadCompletenessBinding(key, ctx.sourceIdentity,
      ctx.subjectModuleSha256, SemanticProfileV1Hash, repeat('5', 64))
    check loaded.isSome  # the artifact itself is intact under ITS context
    discard writeJournalRecord(journalRoot, makeStrictFullCertClaim(
      "5" & repeat('5', 63), key, loaded.get.evidenceDigest, payloadDigest))
    let admissionRes = strictAdmission(journalRoot, repoRoot)
    check admissionRes.ok
    check admissionRes.value.counted == 0
    check admissionRes.value.verdicts[0].outcome == jvNoCurrentEvidence

  test "pre-synthesis completeness anchor: irDigestCanonical != certified irHash is still counted":
    ## The binding describes the PRE-SYNTHESIS IR; the certificate's irHash is
    ## the post-synthesis certified IR. The authenticated link is the flavor-③
    ## CAS anchor (completenessEvidenceKey), not a canonical-digest equality.
    let (repoRoot, journalRoot) = newStrictFixture()
    defer:
      restoreStateDir()
      restoreAxiomRoot()
    let ctx = fixtureStrictContext(repoRoot)
    let key = sha256Hex("strict-ir-key")
    var payloadDigest = ""
    let claimIrHash = "6" & repeat('6', 63)
    check saveFixtureBinding(key, claimIrHash, ctx, payloadDigest,
      irDigestCanonical = repeat('7', 64))  # ≠ claim irHash (pre-synthesis)
    let loaded = loadCompletenessBinding(key, ctx.sourceIdentity,
      ctx.subjectModuleSha256, SemanticProfileV1Hash, ctx.toolchainFingerprint)
    check loaded.isSome
    discard writeJournalRecord(journalRoot, makeStrictFullCertClaim(claimIrHash,
      key, loaded.get.evidenceDigest, payloadDigest))
    let admissionRes = strictAdmission(journalRoot, repoRoot)
    check admissionRes.ok
    check admissionRes.value.counted == 1
    check admissionRes.value.verdicts[0].outcome == jvCounted

  test "binding CAS anchor != claim completenessEvidenceKey is not counted":
    let (repoRoot, journalRoot) = newStrictFixture()
    defer:
      restoreStateDir()
      restoreAxiomRoot()
    let ctx = fixtureStrictContext(repoRoot)
    let key = sha256Hex("strict-cas-key")
    var payloadDigest = ""
    let claimIrHash = "6" & repeat('6', 63)
    check saveFixtureBinding(key, claimIrHash, ctx, payloadDigest,
      irDigest = repeat('8', 64))  # CAS anchor ≠ claim's completenessEvidenceKey
    let loaded = loadCompletenessBinding(key, ctx.sourceIdentity,
      ctx.subjectModuleSha256, SemanticProfileV1Hash, ctx.toolchainFingerprint)
    check loaded.isSome
    discard writeJournalRecord(journalRoot, makeStrictFullCertClaim(claimIrHash,
      key, loaded.get.evidenceDigest, payloadDigest))
    let admissionRes = strictAdmission(journalRoot, repoRoot)
    check admissionRes.ok
    check admissionRes.value.counted == 0
    check admissionRes.value.verdicts[0].outcome == jvNoCurrentEvidence

  test "AXIOM_EVIDENCE_STRICT=1 excludes legacy claims; without the flag the legacy path counts":
    let (repoRoot, journalRoot) = newStrictFixture()
    defer:
      restoreStateDir()
      restoreAxiomRoot()
      restoreStrictEnv()
    discard writeJournalRecord(journalRoot,
      makeFullCertClaim(irHash = "7" & repeat('7', 63)))
    pointStrictEnv(true)
    let strictRes = strictAdmission(journalRoot, repoRoot)
    check strictRes.ok
    check strictRes.value.counted == 0
    check strictRes.value.verdicts[0].outcome == jvNoCurrentEvidence
    pointStrictEnv(false)
    check evidenceStrictModeActive() == false
    let legacyRes = strictAdmission(journalRoot, repoRoot)
    check legacyRes.ok
    check legacyRes.value.counted == 1
    check legacyRes.value.verdicts[0].outcome == jvCounted

  test "strict claim supersedes a legacy claim for one symbol without the flag":
    let (repoRoot, journalRoot) = newStrictFixture()
    defer:
      restoreStateDir()
      restoreAxiomRoot()
      restoreStrictEnv()
    pointStrictEnv(false)  # this test is specifically about the un-flagged path
    let ctx = fixtureStrictContext(repoRoot)
    let key = sha256Hex("strict-mix-key")
    var payloadDigest = ""
    check saveFixtureBinding(key, "8" & repeat('8', 63), ctx, payloadDigest)
    let loaded = loadCompletenessBinding(key, ctx.sourceIdentity,
      ctx.subjectModuleSha256, SemanticProfileV1Hash, ctx.toolchainFingerprint)
    check loaded.isSome
    discard writeJournalRecord(journalRoot,
      makeFullCertClaim(irHash = "9" & repeat('9', 63)))  # legacy generation
    discard writeJournalRecord(journalRoot,
      makeStrictFullCertClaim("8" & repeat('8', 63), key,
        loaded.get.evidenceDigest, payloadDigest))      # strict generation
    check evidenceStrictModeActive() == false
    let admissionRes = strictAdmission(journalRoot, repoRoot)
    check admissionRes.ok
    # Generation cutover: the symbol HAS a strict-generation claim, so the
    # legacy claim is not a fallback even without the flag. The valid strict
    # evidence is counted.
    check admissionRes.value.counted == 1
    check admissionRes.value.verdicts[0].outcome == jvCounted

  test "legacy claim cannot resurrect a symbol whose strict claim is inadmissible":
    let (repoRoot, journalRoot) = newStrictFixture()
    defer:
      restoreStateDir()
      restoreAxiomRoot()
      restoreStrictEnv()
    pointStrictEnv(false)
    # A strict-generation claim exists but its binding artifact is absent:
    # strictAdmits fails. The legacy claim for the same symbol must NOT be
    # resurrected as a fallback (the generation-cutover rule).
    discard writeJournalRecord(journalRoot,
      makeFullCertClaim(irHash = "9" & repeat('9', 63)))
    let missingKey = sha256Hex("absent-strict-key")
    discard writeJournalRecord(journalRoot, makeStrictFullCertClaim(
      "8" & repeat('8', 63), missingKey, repeat('0', 64), repeat('0', 64)))
    check evidenceStrictModeActive() == false
    let admissionRes = strictAdmission(journalRoot, repoRoot)
    check admissionRes.ok
    check admissionRes.value.counted == 0
    check admissionRes.value.verdicts[0].outcome == jvNoCurrentEvidence

  test "claim toolchainIdentity missing or mismatching engineBuild is excluded":
    let root = newFixture()
    defer: restoreAxiomRoot()
    var missingEngine = currentJournalToolchainPin()
    missingEngine.delete("engineBuild")
    check toolchainIdentityMatchesPin(missingEngine) == false
    discard writeJournalRecord(root,
      makeFullCertClaim(irHash = "a" & repeat('4', 63), toolchain = missingEngine))
    var staleEngine = currentJournalToolchainPin()
    staleEngine["engineBuild"] = newJString(repeat('0', 64))
    check toolchainIdentityMatchesPin(staleEngine) == false
    discard writeJournalRecord(root,
      makeFullCertClaim(irHash = "b" & repeat('4', 63), toolchain = staleEngine))
    let admissionRes = admissionForResult(root)
    check admissionRes.ok
    check admissionRes.value.counted == 0
    check admissionRes.value.verdicts[0].outcome == jvNoCurrentEvidence

  test "isFullCertClaim generation contract (required fields, strict anchors)":
    let legacy = parseJson($(makeFullCertClaim(irHash = "c" & repeat('4', 63))))
    check isFullCertClaim(legacy)
    # v3-identity-bound required fields: dropping any drops the claim.
    for field in ["solverStatus", "solverInputDigest", "solverResultDigest"]:
      let broken = parseJson($legacy)
      broken[field] = newJString("")
      check isFullCertClaim(broken) == false
    let noStrategy = parseJson($legacy)
    noStrategy["winningStrategy"] = newJString("")
    check isFullCertClaim(noStrategy) == false  # certGreen requires the strategy
    # Strict generation: the marker demands the full anchor set.
    var strict = parseJson($legacy)
    strict["completenessContract"] = newJString(CompletenessContractStrictV1)
    check isFullCertClaim(strict) == false  # anchors missing
    strict["completenessEvidenceKey"] = newJString(repeat('a', 64))
    check isFullCertClaim(strict) == false
    strict["completenessBindingDigest"] = newJString(repeat('b', 64))
    check isFullCertClaim(strict) == false
    strict["completenessPayloadDigest"] = newJString(repeat('c', 64))
    check isFullCertClaim(strict) == true
    # The legacy claim itself is untouched by the strict variants (no ref
    # aliasing): the legacy generation contract still holds.
    check isFullCertClaim(legacy)
    check isStrictContractClaim(legacy) == false
    check isStrictContractClaim(strict) == true
