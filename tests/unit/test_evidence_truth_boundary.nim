import std/[unittest, json, options, os, strutils, tempfiles]
import ../../src/core/results
import ../../src/core/utils/repo_root
import ../../src/gate/runners/evidence_truth_boundary_gate
import ../../src/verification/obligation/kernel_acceptance_authority
import ../../src/verification/obligation/verification_decision_authority
import ../../src/verification/obligation/persisted_artifact_validator
import ../../src/verification/obligation/lean_kernel_boundary
import ../../src/verification/obligation/identity
import ../../src/verification/proof_state_builder
import ../../src/core/types/certificate_types
import ../../src/core/types/verification_tier

## W2-B unit tests — Evidence Truth Boundary (Phase B, R4).
##
## Opacity note: `LeanKernelCheckReceipt` fields are private and its only
## constructor `makeReceipt` is private to `lean_kernel_boundary.nim`.
## Tests therefore obtain receipts ONLY through the canonical sink
## `canonicalLeanKernelCheck` (real Lean kernel execution). There is no
## test-side receipt forgery path — that is the invariant under test.
## External construction attempts are covered by the negative compile
## fixture `tests/negative/forge_receipt_external.nim`.

proc trivialTheoremSource(name: string): string =
  "theorem " & name & " : True := trivial\n"

proc sinkReceipt(name: string): Result[LeanKernelCheckReceipt, string] =
  canonicalLeanKernelCheck(trivialTheoremSource(name))

# ---------------------------------------------------------------------------
# Authority B: KernelAcceptanceAuthority — bindReceipt() is the sole creation path
# ---------------------------------------------------------------------------

suite "KernelAcceptanceAuthority — bindReceipt() as sole KAA creation path":

  test "canonical sink issues a receipt for a real theorem (single issuance point)":
    let res = sinkReceipt("axiomBoundaryTrivialA")
    check res.isOk()
    let receipt = res.get()
    check receipt.receiptTheoremIdentity == "axiomBoundaryTrivialA"
    check receipt.receiptExecutableDigest.len == 64
    check receipt.receiptInputIdentity.len == 64
    check receipt.receiptArtifactIdentity.len == 64

  test "canonical sink refuses a source without a theorem declaration":
    let res = canonicalLeanKernelCheck("def notATheorem := 1\n")
    check res.isErr()

  test "bindReceipt() produces a KAA from a sink-issued receipt":
    let receipt = sinkReceipt("axiomBoundaryTrivialB").get()
    let bound = bindReceipt(receipt)
    check bound.isOk()
    let kaa = bound.get()
    check kaa.kaaTheoremIdentity == "axiomBoundaryTrivialB"
    check kaa.kaaArtifactHash == receipt.receiptArtifactIdentity
    check kaa.kaaAxiomSet().len == 0
    check kaa.kaaSorryScan().len == 0

  test "bindReceipt() with axioms and sorryScan populates KAA fields":
    let receipt = sinkReceipt("axiomBoundaryTrivialC").get()
    let kaa = bindReceipt(receipt, axioms = @["propext", "Classical.choice"],
                          sorryScan = @["sorryAx"]).get()
    # makeKAA canonicalizes observations to a sorted, de-duplicated set.
    check kaa.kaaAxiomSet() == @["Classical.choice", "propext"]
    check kaa.kaaSorryScan() == @["sorryAx"]

  test "KAA identity is deterministic for the same receipt":
    let receipt = sinkReceipt("axiomBoundaryTrivialD").get()
    let kaa1 = bindReceipt(receipt).get()
    let kaa2 = bindReceipt(receipt).get()
    let execId = executionIdentity(
      receipt.receiptInputIdentity,
      executionContractDigest(canonicalExecutionContract("", "", "", @[], "", "", "", "")),
      canonicalExecutionBundleFingerprint("", "", "", "", "", "", @[], "", "")
    )
    check kaa1.kaaIdentity(execId) == kaa2.kaaIdentity(execId)

  test "KAA identity differs for different canonical inputs":
    let receipt1 = sinkReceipt("axiomBoundaryTrivialE1").get()
    let receipt2 = sinkReceipt("axiomBoundaryTrivialE2").get()
    check receipt1.receiptInputIdentity != receipt2.receiptInputIdentity
    let kaa1 = bindReceipt(receipt1).get()
    let kaa2 = bindReceipt(receipt2).get()
    let execId = executionIdentity(
      receipt1.receiptInputIdentity,
      executionContractDigest(canonicalExecutionContract("", "", "", @[], "", "", "", "")),
      canonicalExecutionBundleFingerprint("", "", "", "", "", "", @[], "", "")
    )
    check kaa1.kaaIdentity(execId) != kaa2.kaaIdentity(execId)

  test "KAA is opaque — access only through accessor functions":
    ## Opacity invariant: KAA and receipt fields are private; the only
    ## surface is the accessor functions. Direct field construction from
    ## outside the authority modules is a compile error (see
    ## tests/negative/forge_receipt_external.nim).
    let receipt = sinkReceipt("axiomBoundaryTrivialF").get()
    let kaa = bindReceipt(receipt).get()
    check kaa.kaaReceipt().receiptTheoremIdentity == "axiomBoundaryTrivialF"
    check kaa.kaaArtifactHash().len == 64

# ---------------------------------------------------------------------------
# Authority C: VerificationDecisionAuthority — evaluate() produces verdicts
# ---------------------------------------------------------------------------

suite "VerificationDecisionAuthority — evaluate(KAA, Policy)":

  test "evaluate() produces vdVerified when policy is satisfied":
    let receipt = sinkReceipt("axiomBoundaryTrivialG").get()
    let kaa = bindReceipt(receipt).get()
    let policy = VerificationPolicy(
      allowedAxioms: @["propext", "Classical.choice"],
      sorryPolicy: spForbid
    )
    check evaluate(kaa, policy) == vdVerified

  test "evaluate() produces vdPolicyRejected when axioms are forbidden":
    let receipt = sinkReceipt("axiomBoundaryTrivialH").get()
    let kaa = bindReceipt(receipt, axioms = @["sorryAx"]).get()
    let policy = VerificationPolicy(
      allowedAxioms: @["propext", "Classical.choice"],
      sorryPolicy: spForbid
    )
    check evaluate(kaa, policy) == vdPolicyRejected

  test "evaluate() produces vdPolicyRejected when sorry is forbidden":
    let receipt = sinkReceipt("axiomBoundaryTrivialI").get()
    let kaa = bindReceipt(receipt, sorryScan = @["sorryAx"]).get()
    let policy = VerificationPolicy(
      allowedAxioms: @["propext"],
      sorryPolicy: spForbid
    )
    check evaluate(kaa, policy) == vdPolicyRejected

  test "evaluate() with an empty allowlist accepts a clean KAA":
    ## Empty allowlist permits no axioms — it does NOT skip the check.
    ## A KAA with an empty observed axiom set has nothing to reject.
    let receipt = sinkReceipt("axiomBoundaryTrivialJ").get()
    let kaa = bindReceipt(receipt).get()
    let policy = VerificationPolicy(
      allowedAxioms: @[],  # empty allowlist = no axioms permitted (fail-closed)
      sorryPolicy: spAllow
    )
    check evaluate(kaa, policy) == vdVerified

# ---------------------------------------------------------------------------
# Authority D: PersistedArtifactValidator — HistoricalRecord/ReplayRequest
# ---------------------------------------------------------------------------

suite "PersistedArtifactValidator — HistoricalRecord/ReplayRequest":

  test "validate() produces a ReplayRequest for valid persisted artifacts":
    let validator = PersistedArtifactValidator(allowedSources: @["trust-commit"])
    let artifact = %*{
      "modulePath": "src/test.nim",
      "functionName": "testFn",
      "identityDigest": "sha256:artifact123",
      "status": "certGreen",
      "sourceHash": "sha256:source",
      "toolchainIdentity": "nim-2.2.10|lean-4.33.0",
      "theoremIdentity": "testTheorem"
    }
    let outcome = validator.validate(artifact, "trust-commit")
    check outcome.status == pvrReplayRequest
    check outcome.historicalRecord.isSome()
    check outcome.replayRequest.isSome()
    check outcome.historicalRecord.get().artifactIdentity == "sha256:artifact123"

  test "validate() rejects artifacts with missing modulePath":
    let validator = PersistedArtifactValidator(allowedSources: @["trust-commit"])
    let artifact = %*{
      "functionName": "testFn",
      "identityDigest": "sha256:artifact123"
    }
    let outcome = validator.validate(artifact, "trust-commit")
    check outcome.status == pvrRejected

  test "validate() rejects artifacts from untrusted sources":
    let validator = PersistedArtifactValidator(allowedSources: @["trust-commit"])
    let artifact = %*{
      "modulePath": "src/test.nim",
      "functionName": "testFn",
      "identityDigest": "sha256:artifact123"
    }
    let outcome = validator.validate(artifact, "untrusted-source")
    check outcome.status == pvrRejected

  test "HistoricalRecord does NOT restore a verified verdict":
    ## Key invariant: persisted records are historical only.
    ## No field in HistoricalRecord may be used to directly construct
    ## or reconstruct a verified verdict.
    let validator = PersistedArtifactValidator(allowedSources: @["trust-commit"])
    let artifact = %*{
      "modulePath": "src/test.nim",
      "functionName": "testFn",
      "identityDigest": "sha256:artifact123",
      "status": "certGreen",  # historical label, NOT a current verdict
      "sourceHash": "sha256:source",
      "toolchainIdentity": "nim-2.2.10|lean-4.33.0"
    }
    let outcome = validator.validate(artifact, "trust-commit")
    check outcome.status == pvrReplayRequest
    # The HistoricalRecord stores the status as a string, not as a verdict
    check outcome.historicalRecord.get().persistedStatus == "certGreen"
    # But this does NOT mean the artifact is currently verified —
    # a fresh canonical check is required.

# ---------------------------------------------------------------------------
# B2: certZ3Verified reclassification
# ---------------------------------------------------------------------------

suite "certZ3Verified reclassification — canonical output uses certZ3Candidate":

  test "certZ3Candidate is a distinct status from certZ3Verified":
    check certZ3Candidate != certZ3Verified
    check $certZ3Candidate == "certZ3Candidate"
    check $certZ3Verified == "certZ3Verified"

  test "tierToCertStatus maps vtZ3Only to certZ3Candidate":
    check tierToCertStatus(vtZ3Only) == certZ3Candidate

  test "tierToCertStatus maps vtKInduction to certZ3Candidate":
    check tierToCertStatus(vtKInduction) == certZ3Candidate

  test "tierToCertStatus maps vtDual to certGreen":
    check tierToCertStatus(vtDual) == certGreen

  test "tierToCertStatus maps vtLeanOnly to certLeanVerified":
    check tierToCertStatus(vtLeanOnly) == certLeanVerified

  test "tierToStatusString maps vtZ3Only to certZ3Candidate":
    check tierToStatusString(vtZ3Only) == "certZ3Candidate"

  test "tierToStatusString maps vtKInduction to certZ3Candidate":
    check tierToStatusString(vtKInduction) == "certZ3Candidate"

  test "parseCertificateStatus parses certZ3Candidate":
    let status = parseCertificateStatus("certZ3Candidate")
    check status == certZ3Candidate

  test "isVerifiedCertificateStatus excludes certZ3Candidate":
    ## Z3-only is candidate-only, NOT verified
    check isVerifiedCertificateStatus("certGreen") == true
    check isVerifiedCertificateStatus("certLeanVerified") == true
    check isVerifiedCertificateStatus("certZ3Candidate") == false
    check isVerifiedCertificateStatus("certZ3Verified") == false  # legacy, also excluded

# ---------------------------------------------------------------------------
# isDeepVerified promotion behavior — tested through the public hydration API
# ---------------------------------------------------------------------------
## `isDeepVerified` is private to proof_state_builder.nim. Its behavioral
## invariant (Z3-only evidence never promotes to verified) is exercised
## through `hydrateProofStateFromCertificateVault`: a Z3-only certificate
## labeled "certGreen" must land as pending/unverifiable, never as
## certVerifiedAxiom.

proc writeCert(dir: string; name: string; body: JsonNode) =
  writeFile(dir / (name & ".json"), pretty(body))

suite "hydrateProofStateFromCertificateVault — Z3-only never promotes to verified":

  test "Z3-only certificate labeled certGreen is NOT counted as verified":
    let dir = createTempDir("axbnd", "z3only")
    defer:
      removeDir(dir)
    writeCert(dir, "z3only_cert", %*{
      "modulePath": "src/does_not_exist_z3only.nim",
      "functionName": "z3OnlyFn",
      "fingerprint": "abc123",
      "sourceHash": "sha256:source",
      "status": "certGreen",
      "smtlib2": "(set-logic QF_BV)",
      "z3outPath": "",
      "solverMeta": %*{"leanCompilerVerified": false, "vacuityProven": false},
      "verificationTier": ""
    })
    let (_, certs) = hydrateProofStateFromCertificateVault(dir)
    check certs.len == 1
    # Z3-only evidence must NOT promote to certVerifiedAxiom.
    check certs[0].status != certVerifiedAxiom

  test "Lean-verified certificate with soundness assurance promotes to verified":
    let dir = createTempDir("axbnd", "leanok")
    defer:
      removeDir(dir)
    writeCert(dir, "lean_cert", %*{
      "modulePath": "src/does_not_exist_leanok.nim",
      "functionName": "leanOkFn",
      "fingerprint": "abc123",
      "sourceHash": "sha256:source",
      "status": "certGreen",
      # DECISION-0630: Lean evidence is the P0 conjunction
      # leanCompilerVerified ∧ kernel — the fixture carries the kernel receipt.
      "kernel": true,
      "solverMeta": %*{"leanCompilerVerified": true, "vacuityProven": true},
      "verificationTier": ""
    })
    let (_, certs) = hydrateProofStateFromCertificateVault(dir)
    check certs.len == 1
    # P0 Lean evidence + vacuityProven satisfies the soundness gatekeeper.
    check certs[0].status == certVerifiedAxiom

  test "lean flag without kernel receipt does NOT promote (KAA-less, P0)":
    let dir = createTempDir("axbnd", "leanflag")
    defer:
      removeDir(dir)
    writeCert(dir, "leanflag_cert", %*{
      "modulePath": "src/does_not_exist_leanflag.nim",
      "functionName": "leanFlagFn",
      "fingerprint": "abc123",
      "sourceHash": "sha256:source",
      "status": "certGreen",
      # Raw flag + vacuity but NO kernel receipt: the DECISION-0630 contract
      # (leanVerified = flag ∧ kernel) fails — fail-closed, never promoted.
      "solverMeta": %*{"leanCompilerVerified": true, "vacuityProven": true},
      "verificationTier": ""
    })
    let (_, certs) = hydrateProofStateFromCertificateVault(dir)
    check certs.len == 1
    check certs[0].status != certVerifiedAxiom

  test "leanCompilerVerified alone (no vacuity, no tier) does NOT promote":
    let dir = createTempDir("axbnd", "leanbare")
    defer:
      removeDir(dir)
    writeCert(dir, "leanbare_cert", %*{
      "modulePath": "src/does_not_exist_leanbare.nim",
      "functionName": "leanBareFn",
      "fingerprint": "abc123",
      "sourceHash": "sha256:source",
      "status": "certGreen",
      "solverMeta": %*{"leanCompilerVerified": true, "vacuityProven": false},
      "verificationTier": ""
    })
    let (_, certs) = hydrateProofStateFromCertificateVault(dir)
    check certs.len == 1
    check certs[0].status != certVerifiedAxiom

# ---------------------------------------------------------------------------
# Legacy certZ3Verified migration is terminal-at-candidate
# ---------------------------------------------------------------------------

suite "Legacy certZ3Verified migration — terminal at candidate":

  test "certZ3Verified legacy string maps to certZ3Candidate, not verified":
    ## When reading a legacy record with certZ3Verified status,
    ## it must be converted to a canonical Z3Candidate record immediately.
    let legacyStatus = parseCertificateStatus("certZ3Verified")
    check legacyStatus == certZ3Verified  # legacy enum still exists for compat
    # But the canonical output uses certZ3Candidate
    check tierToCertStatus(vtZ3Only) == certZ3Candidate
    # certZ3Candidate is NOT in the verified set
    check isVerifiedCertificateStatus("certZ3Candidate") == false

  test "certZ3Candidate does not feed into verified count":
    ## The verified count must not include Z3-only candidates.
    check isVerifiedCertificateStatus("certZ3Candidate") == false
    check isVerifiedCertificateStatus("certZ3Verified") == false

  test "no promotion edge exists from certZ3Candidate to verified":
    ## Negative test: certZ3Candidate must never be promoted to verified.
    check not isVerifiedCertificateStatus("certZ3Candidate")
    check tierToCertStatus(vtZ3Only) == certZ3Candidate
    # certZ3Candidate is candidate-only — it never reaches verified/deep-verified/certGreen/KAA

# ---------------------------------------------------------------------------
# [T4-b] Guarded run-outcome keys — the 6-key guard set, locked by test
# ---------------------------------------------------------------------------
## `guardedOutcomeKeys` in evidence_truth_boundary_gate.nim names the run-outcome
## JSON keys that may never be written from a literal of the verdict
## vocabulary. The set was widened from 4 keys to 6 when the three RAW
## completeness projections (`planComplete` / `executionComplete` /
## `verificationComplete`) were brought under the same guard as the
## VDA-decided `verdict` / `basis` / `gateVerdict`.
##
## `guardedOutcomeKeys` is module-private and `src/` is immutable to this test,
## so the guard set is pinned BEHAVIOURALLY instead of by importing the const:
## the fixture repo below contains one fabricator module per CANDIDATE key, and
## the set of keys the gate actually reports must equal the six expected. A
## dropped key makes the set shrink (test fails on count); an extra key that
## collides with a control makes it grow (test fails on the control). A future
## edit that silently narrows the guard can no longer pass.

const verdictVocabularySourcePath = "src/verification/accounting/run_accounting.nim"
  ## Enum declarations that define the vocabulary the gate compares literals
  ## against. Copied VERBATIM into the fixture so the spellings under test are
  ## the production ones, not a hand-written stand-in.

const verdictOwnerPath = "src/verification/obligation/verification_decision_authority.nim"
  ## Sole authority module for the run verdict; writing the keys there by
  ## PROJECTION is legitimate and must not be reported.

const fabricatorDir = "src/fixture"
  ## Location of the per-key fabricator modules inside the fixture repo.

type KeyCase = object
  key: string
  literalText: string   ## vocabulary spelling; used when boolLiteral is ""
  boolLiteral: string   ## "true"/"false" for the completeness projections

const keyCases = [
  # ── the six guarded keys ──
  KeyCase(key: "verdict", literalText: "PASS"),
  KeyCase(key: "basis", literalText: "PROVEN"),
  KeyCase(key: "gateVerdict", literalText: "PASS"),
  KeyCase(key: "planComplete", boolLiteral: "true"),
  KeyCase(key: "executionComplete", boolLiteral: "false"),
  KeyCase(key: "verificationComplete", boolLiteral: "true"),
  # ── negative controls: same vocabulary literal, key NOT in the guard set ──
  # These prove the gate filters on the KEY. If they were reported, the guard
  # would be matching the value rather than the guarded schema.
  KeyCase(key: "reusedConditionsMet", literalText: "REUSED"),
  KeyCase(key: "attempts", literalText: "PASS"),
]
# Test-side mirror of the guard set. Deliberately the FULL candidate list;
# which of these the gate reports is what the assertions below measure.

const guardedOutcomeKeyUnderTest = [
  "verdict", "basis", "gateVerdict",
  "planComplete", "executionComplete", "verificationComplete"
]

const unguardedOutcomeKeyControl = ["reusedConditionsMet", "attempts"]

func rhsSource(k: KeyCase): string =
  if k.boolLiteral.len > 0: k.boolLiteral
  else: "\"" & k.literalText & "\""

func fabricatorPath(key: string): string = fabricatorDir / ("fabricate_" & key & ".nim")

func flaggedKey(violation: string): string =
  ## The outcome key named by a [T4-b] violation, or "" for any other.
  const marker = "[T4] outcome key '"
  let start = violation.find(marker)
  if start < 0: return ""
  let keyStart = start + marker.len
  let stop = violation.find("'", keyStart)
  if stop < 0: return ""
  violation[keyStart ..< stop]

func flaggedKeys(violations: seq[string]): seq[string] =
  for v in violations:
    let k = flaggedKey(v)
    if k.len > 0 and k notin result:
      result.add k

func flaggedAt(violations: seq[string]; path, key: string): bool =
  ## True iff a [T4-b] violation for `key` was reported IN `path`.
  for v in violations:
    if v.startsWith(path & ":") and
        v.contains("[T4] outcome key '" & key & "'"):
      return true
  false

func anyViolationFrom(violations: seq[string]; path: string): bool =
  for v in violations:
    if v.startsWith(path & ":"): return true
  false

func anyContains(violations: seq[string]; needle: string): bool =
  for v in violations:
    if needle in v: return true
  false

func hasUnparseable(violations: seq[string]): bool =
  for v in violations:
    if "[I-1] unparseable" in v: return true
  false

func fabricatorSource(k: KeyCase): string =
  ## Syntax-only fixture — parsed by the gate, never compiled. The value is the
  ## LITERAL that fabricates the authority at the serialization site.
  "## Non-owner fixture: fabricates run-outcome key '" & k.key & "'.\n" &
  "proc fabricateOutcome(): string =\n" &
  "  var parts: seq[string] = @[]\n" &
  "  parts[\"" & k.key & "\"] = " & rhsSource(k) & "\n" &
  "  result = $parts\n"

const ownerProjectionSource = """
## Authority owner fixture — the same six keys written by PROJECTION, in both
## positions [T4-b] judges: a keyed write and an object-constructor field.
## It also carries a deliberate [I-2] violation (a value-producing `vvSafe`
## reference) as a SCAN RECEIPT: that violation is only reported if the AST
## walk actually visited this file. Without it, "no [T4-b] violation for the
## owner file" could equally mean "the file was never read" — a vacuous pass.
## An unguarded outcome key could not serve as the receipt, because [T4-b]
## fires only on keys inside the guard set.
type RunOutcomeRecord = object
  verdict: string
  basis: string
  gateVerdict: string
  planComplete: bool
  executionComplete: bool
  verificationComplete: bool

proc projectOutcome(v, b, g: string; p, e, x: bool): RunOutcomeRecord =
  RunOutcomeRecord(
    verdict: v,
    basis: b,
    gateVerdict: g,
    planComplete: p,
    executionComplete: e,
    verificationComplete: x
  )

proc serializeOutcome(o: RunOutcomeRecord): seq[string] =
  var outcome: seq[string] = @[]
  outcome["verdict"] = o.verdict
  outcome["basis"] = o.basis
  outcome["gateVerdict"] = o.gateVerdict
  outcome["planComplete"] = o.planComplete
  outcome["executionComplete"] = o.executionComplete
  outcome["verificationComplete"] = o.verificationComplete
  result = outcome

proc ownerScanCanary(): string =
  ## [I-2] scan receipt: `vvSafe` is owned by universal_pipeline.nim, so a
  ## value-producing reference here MUST be reported — which is what proves
  ## this file was walked. Never remove it: without it the "owner is not
  ## flagged" assertion could pass without the file ever being read.
  var marker = ""
  marker = $vvSafe
  result = marker
""".strip()

proc buildOutcomeKeyFixture(): string =
  ## Synthetic repo root scanned by checkAuthorityGraphAst:
  ##   - the production verdict-vocabulary source, copied verbatim;
  ##   - one fabricator module per candidate outcome key;
  ##   - the authority owner module writing the six keys by projection, plus a
  ##     deliberate [I-2] violation as a scan receipt.
  let root = createTempDir("axbnd", "t4b")
  let repoRoot = findRepoRoot()
  createDir(root / verdictVocabularySourcePath.splitFile().dir)
  createDir(root / verdictOwnerPath.splitFile().dir)
  createDir(root / fabricatorDir)
  writeFile(root / verdictVocabularySourcePath,
            readFile(repoRoot / verdictVocabularySourcePath))
  writeFile(root / verdictOwnerPath, ownerProjectionSource)
  for k in keyCases:
    writeFile(root / fabricatorPath(k.key), fabricatorSource(k))
  root

suite "EvidenceTruthBoundary [T4-b] — guarded run-outcome keys":

  test "fixture premises hold — vocabulary readable and every fixture parses":
    ## Guard against a vacuous pass: an unreadable vocabulary or an unparseable
    ## fixture would silently stop the assertions below from testing anything.
    let root = buildOutcomeKeyFixture()
    defer:
      removeDir(root)
    let violations = checkAuthorityGraphAst(root)
    check not hasUnparseable(violations)
    # [T4] must not have bailed out with an empty vocabulary (fail-closed path).
    check not anyContains(violations, "verdict vocabulary unreadable")

  test "each of the six guarded keys is caught when fabricated from a literal":
    ## One assertion PER key, and attributed to the module that fabricated it —
    ## a key that silently dropped out of guardedOutcomeKeys fails its own test.
    let root = buildOutcomeKeyFixture()
    defer:
      removeDir(root)
    let violations = checkAuthorityGraphAst(root)
    check not hasUnparseable(violations)
    for k in keyCases:
      if k.key in guardedOutcomeKeyUnderTest:
        check flaggedAt(violations, fabricatorPath(k.key), k.key)
      else:
        check not flaggedAt(violations, fabricatorPath(k.key), k.key)

  test "the guard set is EXACTLY the six expected keys":
    ## Count pins the set size, so a removal is loud; the two control keys pin
    ## the lower bound, so an unwarranted widening is loud too.
    let root = buildOutcomeKeyFixture()
    defer:
      removeDir(root)
    let flagged = flaggedKeys(checkAuthorityGraphAst(root))
    check flagged.len == guardedOutcomeKeyUnderTest.len
    for key in guardedOutcomeKeyUnderTest:
      check key in flagged
    for key in unguardedOutcomeKeyControl:
      check key notin flagged

  test "the three completeness projections are guarded like the verdict keys":
    ## These three are the exact keys the 4 → 6 extension added; state them
    ## separately so a regression names itself.
    let root = buildOutcomeKeyFixture()
    defer:
      removeDir(root)
    let flagged = flaggedKeys(checkAuthorityGraphAst(root))
    for key in ["planComplete", "executionComplete", "verificationComplete"]:
      check key in flagged

  test "the authority owner writing the same keys by projection is NOT flagged":
    let root = buildOutcomeKeyFixture()
    defer:
      removeDir(root)
    let violations = checkAuthorityGraphAst(root)
    # Receipt: the owner file WAS walked (its deliberate [I-2] canary is
    # reported). Without this, the loop below could pass vacuously.
    check anyViolationFrom(violations, verdictOwnerPath)
    check anyContains(violations, "[I-2] 'vvSafe'")
    for key in guardedOutcomeKeyUnderTest:
      check not flaggedAt(violations, verdictOwnerPath, key)

  test "the vocabulary spellings these fixtures rely on are the production ones":
    ## The fixture supplies the vocabulary, so without this the tests could pass
    ## against spellings production no longer uses.
    let source = readFile(findRepoRoot() / verdictVocabularySourcePath)
    for k in keyCases:
      if k.boolLiteral.len == 0:
        check ("= \"" & k.literalText & "\"") in source
