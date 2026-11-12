import std/strutils
import core/crypto/hash_kernel
import core/proof/proof_budget
import core/trusted/solver_invocation
import verification/evidence_cas

## Evidence CAS — metamorphic identity test (PURE: no z3, no lean, no
## network, no git, no filesystem). Exercises the EvidenceKey derivation
## surface of src/verification/evidence_cas.nim:
##
##   NEGATIVE mutations — every semantic input change MUST move the key:
##     evidenceDraftDigest, z3ChecksumPolicyDigest, policyDigest,
##     solverOptionsDigest (rlimit 30M→25M), verifierIdentity (treeOID
##     change), headTreeDigest, mergeTreeDigest, scopeDigest.
##   POSITIVE invariances — the key MUST NOT move when nothing semantic did:
##     (a) determinism (same inputs → same key, twice),
##     (b) run-scoped context (runId/attempt/createdAt/buildDate/cloneDepth)
##         has ZERO effect — the function signature itself excludes it,
##     (c) NormalizedEvidence canonical serialization is byte-stable,
##     (e) same-tree rebuild: artifact digests (whose bytes embed
##         BuildEnvBuildDate/GitHash/CommitCount per tools/hermetic_build.nim)
##         are record-level metadata — identity-invariant,
##     (d) across the whole mutation matrix: no collisions, no empty keys.

proc digest64(seed: string): string =
  ## Synthetic well-formed digest member (64 lowercase hex) — content that
  ## would otherwise come from a fail-closed collector.
  sha256Hex(seed)

proc oid40(seed: string): string =
  ## Synthetic well-formed git tree OID (40 lowercase hex).
  sha256Hex(seed)[0 ..< 40]

proc sampleArtifacts(): seq[ArtifactDigest] =
  ## The canonical executed-artifact set (same member set as
  ## evidence_cas.ExecutedArtifactPaths), all with synthetic digests.
  @[ArtifactDigest(name: "ircheck", digest: digest64("artifact-ircheck"))]

proc baseVerifierInputs(): VerifierIdentityInputs =
  VerifierIdentityInputs(
    baseTreeOid: oid40("verifier-base-tree"),
    recipeDigest: digest64("recipe-base"),
    nimPin: "2.2.10",
    leanPin: digest64("lean-toolchain-content-base"),
    z3Pin: "4.13.3",
    z3ChecksumPolicyDigest: digest64("z3-checksum-policy-base"),
    solverOptionsDigest: deterministicSolverOptionsDigest(),
    artifactDigests: sampleArtifacts())

proc baseKeyInputs(): EvidenceKeyInputs =
  EvidenceKeyInputs(
    verifierIdentity: composeVerifierIdentity(baseVerifierInputs()),
    evidenceDraftDigest: digest64("evidence-draft-base"),
    headTreeDigest: oid40("head-tree-base"),
    mergeTreeDigest: oid40("merge-tree-base"),
    policyDigest: digest64("policy-set-base"),
    scopeDigest: digest64("scope-lock-base"))

proc sampleNormalized(): NormalizedEvidence =
  NormalizedEvidence(
    funcSource: "func add(a, b: int): int = a + b",
    funcName: "add",
    leanSource: "theorem add_spec (a b : Int) : add a b = a + b := by simp",
    smtlib2: "(set-option :random-seed 42)\n(declare-fun x () Int)\n(assert (> x 0))\n(check-sat)\n",
    irHash: digest64("ir-base"),
    extractionVerdict: eaAgree,
    leanVerdict: krPassed,
    z3Verdict: krPassed)

type
  RunContext = object
    ## Run-scoped provenance — deliberately NOT an EvidenceKeyInputs member.
    runId: string
    runAttempt: int
    createdAt: string
    buildDate: string
    cloneDepth: string

proc deriveWithContext(ctx: RunContext; inputs: EvidenceKeyInputs): EvidenceKey =
  ## The demonstration vehicle for invariance (b): the run context is a
  ## parameter the body cannot route into the key, because deriveEvidenceKey
  ## consumes only the declared EvidenceKeyInputs members.
  discard ctx
  deriveEvidenceKey(inputs)

proc main() =
  echo "=== Evidence CAS Identity (metamorphic, pure) ==="

  # ── Fixtures ──────────────────────────────────────────────────────────────
  let base = baseKeyInputs()
  let baseProblem = validateEvidenceKeyInputs(base)
  doAssert baseProblem == "",
    "fixture precondition: the baseline key inputs must validate clean (got: " & baseProblem & ")"
  let verifierProblem = validateVerifierIdentityInputs(baseVerifierInputs())
  doAssert verifierProblem == "",
    "fixture precondition: the baseline verifier inputs must validate clean (got: " & verifierProblem & ")"
  echo "  OK: fixtures validate clean (EvidenceKeyInputs + VerifierIdentityInputs)"

  # ── POSITIVE (a): determinism ─────────────────────────────────────────────
  let k1 = deriveEvidenceKey(base)
  let k2 = deriveEvidenceKey(base)
  doAssert k1 == k2,
    "POSITIVE (a): deriveEvidenceKey called twice on identical inputs must yield the identical key"
  doAssert ($k1).len == 64,
    "POSITIVE (a): an EvidenceKey is 64 hex chars, never empty (got length " & $($(k1)).len & ")"
  for c in $k1:
    doAssert c in {'0'..'9', 'a'..'f'},
      "POSITIVE (a): EvidenceKey must be lowercase hex (found '" & $c & "')"
  echo "  OK: (a) determinism — identical inputs → identical 64-hex key"

  # ── POSITIVE (b): run-scoped context has zero effect ──────────────────────
  let ctxA = RunContext(runId: "run-111111", runAttempt: 1,
    createdAt: "2026-01-01T00:00:00Z", buildDate: "2026-01-01", cloneDepth: "50")
  let ctxB = RunContext(runId: "run-999999", runAttempt: 7,
    createdAt: "2026-06-30T23:59:59Z", buildDate: "2026-06-30", cloneDepth: "1")
  doAssert ctxA != ctxB,
    "POSITIVE (b) precondition: the two run contexts must actually differ (else this invariance would be vacuous)"
  let keyFromA = deriveWithContext(ctxA, base)
  let keyFromB = deriveWithContext(ctxB, base)
  doAssert keyFromA == keyFromB,
    "POSITIVE (b): two differing run contexts (runId/attempt/createdAt/buildDate/cloneDepth) must yield the same key from identical EvidenceKeyInputs"
  doAssert keyFromA == k1,
    "POSITIVE (b): the context-independent key must equal the direct derivation"
  echo "  OK: (b) run context (runId/attempt/createdAt/buildDate/cloneDepth) — zero effect"

  # ── POSITIVE (c): NormalizedEvidence byte-stability ───────────────────────
  let evidence = sampleNormalized()
  doAssert validateNormalizedEvidence(evidence) == "",
    "fixture precondition: the normalized sample must validate clean"
  let wire1 = normalizedEvidenceWire(evidence)
  let wire2 = normalizedEvidenceWire(evidence)
  let wire3 = normalizedEvidenceWire(evidence)
  doAssert wire1 == wire2 and wire2 == wire3,
    "POSITIVE (c): canonical serialization must be byte-stable across repeated serialization"
  doAssert normalizedEvidenceDigest(evidence) == sha256Hex(wire1),
    "POSITIVE (c): normalizedEvidenceDigest is sha256 over the canonical wire"
  doAssert normalizedEvidenceDigest(evidence) == normalizedEvidenceDigest(evidence),
    "POSITIVE (c): the normalized digest itself is stable across derivations"
  var lastPos = -1
  for key in ["extractionVerdict", "funcName", "funcSource", "irHash",
              "leanSource", "smtlib2", "z3Verdict"]:
    let at = wire1.find("\"" & key & "\":")
    doAssert at > lastPos,
      "POSITIVE (c): field '" & key & "' must appear in the fixed RFC-8785 canonical order"
    lastPos = at
  for token in ["runId", "runAttempt", "createdAt", "mergeSha", "prNumber",
                "timestamp", "buildDate", "cloneDepth"]:
    doAssert token notin wire1,
      "POSITIVE (c): provenance token '" & token & "' must never enter the normalized wire"
  echo "  OK: (c) canonical serialization byte-stable, field order fixed, no provenance tokens"

  # ── Normalized-record semantic sensitivity (every member moves the digest) ─
  let recordDigest = normalizedEvidenceDigest(evidence)
  block:
    var m = evidence; m.funcSource = "func add(a, b: int): int = a + b + 0"
    doAssert normalizedEvidenceDigest(m) != recordDigest,
      "NEGATIVE: funcSource change must change the normalized digest"
  block:
    var m = evidence; m.funcName = "addChecked"
    doAssert normalizedEvidenceDigest(m) != recordDigest,
      "NEGATIVE: funcName change must change the normalized digest"
  block:
    var m = evidence; m.leanSource = "theorem other_spec : True := by trivial"
    doAssert normalizedEvidenceDigest(m) != recordDigest,
      "NEGATIVE: leanSource change must change the normalized digest"
  block:
    var m = evidence; m.smtlib2 = "(set-option :random-seed 42)\n(check-sat)\n"
    doAssert normalizedEvidenceDigest(m) != recordDigest,
      "NEGATIVE: smtlib2 change must change the normalized digest"
  block:
    var m = evidence; m.irHash = digest64("ir-mutated")
    doAssert normalizedEvidenceDigest(m) != recordDigest,
      "NEGATIVE: irHash change must change the normalized digest"
  block:
    var m = evidence; m.extractionVerdict = eaMismatch
    doAssert normalizedEvidenceDigest(m) != recordDigest,
      "NEGATIVE: extraction verdict change must change the normalized digest"
    doAssert not isReusableOutcome(m),
      "a non-agreeing extraction verdict must never count as a reusable outcome"
  block:
    var m = evidence; m.leanVerdict = krTimeout
    doAssert normalizedEvidenceDigest(m) != recordDigest,
      "NEGATIVE: lean verdict change must change the normalized digest"
    doAssert not isReusableOutcome(m),
      "a non-passing lean verdict must never count as a reusable outcome"
  block:
    var m = evidence; m.z3Verdict = krZ3Mismatch
    doAssert normalizedEvidenceDigest(m) != recordDigest,
      "NEGATIVE: z3 verdict change must change the normalized digest"
    doAssert not isReusableOutcome(m),
      "a non-passing z3 verdict must never count as a reusable outcome"
  doAssert isReusableOutcome(evidence),
    "the all-pass sample (eaAgree + krPassed + krPassed) must count as a reusable outcome"
  echo "  OK: normalized record — all 8 member mutations move the digest; reusability gate correct"

  # ── NEGATIVE mutations: every semantic input change MUST move the key ─────
  var matrix: seq[string] = @[$k1]

  block:
    var m = base; m.evidenceDraftDigest = digest64("evidence-draft-mutated")
    let k = deriveEvidenceKey(m); matrix.add($k)
    doAssert k != k1,
      "NEGATIVE: evidenceDraftDigest change must change the EvidenceKey"

  block:
    var m = base; m.policyDigest = digest64("policy-set-mutated")
    let k = deriveEvidenceKey(m); matrix.add($k)
    doAssert k != k1,
      "NEGATIVE: policyDigest change must change the EvidenceKey"

  block:
    var m = base; m.scopeDigest = digest64("scope-lock-mutated")
    let k = deriveEvidenceKey(m); matrix.add($k)
    doAssert k != k1,
      "NEGATIVE: scopeDigest change must change the EvidenceKey"

  block:
    var m = base; m.headTreeDigest = oid40("head-tree-mutated")
    let k = deriveEvidenceKey(m); matrix.add($k)
    doAssert k != k1,
      "NEGATIVE: headTreeDigest change must change the EvidenceKey"

  block:
    var m = base; m.mergeTreeDigest = oid40("merge-tree-mutated")
    let k = deriveEvidenceKey(m); matrix.add($k)
    doAssert k != k1,
      "NEGATIVE: mergeTreeDigest change must change the EvidenceKey"

  block:
    var m = base; m.verifierIdentity = digest64("verifier-mutated")
    let k = deriveEvidenceKey(m); matrix.add($k)
    doAssert k != k1,
      "NEGATIVE: verifierIdentity change must change the EvidenceKey"

  block:
    # z3ChecksumPolicyDigest — a verifier-identity part, so the mutation is
    # observed first at the composition, then at the key.
    var v = baseVerifierInputs()
    v.z3ChecksumPolicyDigest = digest64("z3-checksum-policy-mutated")
    let vidMutated = composeVerifierIdentity(v)
    doAssert vidMutated != base.verifierIdentity,
      "NEGATIVE: z3ChecksumPolicyDigest change must change the composed verifierIdentity"
    var m = base; m.verifierIdentity = vidMutated
    let k = deriveEvidenceKey(m); matrix.add($k)
    doAssert k != k1,
      "NEGATIVE: z3ChecksumPolicyDigest change must change the EvidenceKey"

  block:
    # solverOptionsDigest — rlimit 30M → 25M on the CANONICAL option set.
    let opts30M = solverOptionsDigest(
      deterministicSolverOptions(z3DeterministicBudget, z3SafetyNetMs))
    let opts25M = solverOptionsDigest(deterministicSolverOptions(25_000_000, z3SafetyNetMs))
    doAssert opts30M == deterministicSolverOptionsDigest(),
      "precondition: the shipped deterministic option digest must be the 30M-rlimit set (z3DeterministicBudget)"
    doAssert opts30M != opts25M,
      "NEGATIVE: rlimit 30M→25M must change the solver option digest"
    var v30 = baseVerifierInputs(); v30.solverOptionsDigest = opts30M
    var v25 = baseVerifierInputs(); v25.solverOptionsDigest = opts25M
    doAssert composeVerifierIdentity(v30) == base.verifierIdentity,
      "precondition: the 30M option set composes to the baseline verifier identity"
    let vid25 = composeVerifierIdentity(v25)
    doAssert vid25 != base.verifierIdentity,
      "NEGATIVE: solverOptionsDigest change must change the composed verifierIdentity"
    var m = base; m.verifierIdentity = vid25
    let k = deriveEvidenceKey(m); matrix.add($k)
    doAssert k != k1,
      "NEGATIVE: solverOptionsDigest change (rlimit 30M→25M) must change the EvidenceKey"

  block:
    # verifierIdentity via treeOID(B) change.
    var v = baseVerifierInputs()
    v.baseTreeOid = oid40("verifier-base-tree-mutated")
    let vidMutated = composeVerifierIdentity(v)
    doAssert vidMutated != base.verifierIdentity,
      "NEGATIVE: treeOID(B) change must change the composed verifierIdentity"
    var m = base; m.verifierIdentity = vidMutated
    let k = deriveEvidenceKey(m); matrix.add($k)
    doAssert k != k1,
      "NEGATIVE: verifierIdentity change (treeOID change) must change the EvidenceKey"

  block:
    # Remaining verifier-identity parts — each channel must be live.
    var vRecipe = baseVerifierInputs(); vRecipe.recipeDigest = digest64("recipe-mutated")
    doAssert composeVerifierIdentity(vRecipe) != base.verifierIdentity,
      "NEGATIVE: recipeDigest change must change the composed verifierIdentity"
    var vLean = baseVerifierInputs()
    vLean.leanPin = digest64("lean-toolchain-content-mutated")
    doAssert composeVerifierIdentity(vLean) != base.verifierIdentity,
      "NEGATIVE: leanPin (proofs/lean-toolchain content) change must change the composed verifierIdentity"
    var vNim = baseVerifierInputs(); vNim.nimPin = "2.3.4"
    doAssert composeVerifierIdentity(vNim) != base.verifierIdentity,
      "NEGATIVE: nimPin change must change the composed verifierIdentity"
    var vZ3 = baseVerifierInputs(); vZ3.z3Pin = "4.14.0"
    doAssert composeVerifierIdentity(vZ3) != base.verifierIdentity,
      "NEGATIVE: z3Pin change must change the composed verifierIdentity"
    for mutated in [composeVerifierIdentity(vRecipe), composeVerifierIdentity(vLean),
                    composeVerifierIdentity(vNim), composeVerifierIdentity(vZ3)]:
      var m = base; m.verifierIdentity = mutated
      let k = deriveEvidenceKey(m); matrix.add($k)
      doAssert k != k1,
        "NEGATIVE: a verifier-identity part change must reach the EvidenceKey"

  block:
    # Second distinct values for two tree members — replaces the two former
    # artifact-only matrix entries, so the matrix stays 16 keys of purely
    # semantic variance (artifact digests are record metadata, not identity).
    var mHead2 = base; mHead2.headTreeDigest = oid40("head-tree-mutated-2")
    let kHead2 = deriveEvidenceKey(mHead2); matrix.add($kHead2)
    doAssert kHead2 != k1,
      "NEGATIVE: a second distinct headTreeDigest must yield a distinct key"
    var mMerge2 = base; mMerge2.mergeTreeDigest = oid40("merge-tree-mutated-2")
    let kMerge2 = deriveEvidenceKey(mMerge2); matrix.add($kMerge2)
    doAssert kMerge2 != k1,
      "NEGATIVE: a second distinct mergeTreeDigest must yield a distinct key"
  echo "  OK: negatives — draft/z3-policy/policy/rlimit/verifier-treeOID/head/merge/scope all move the key"

  # ── POSITIVE (e): artifact digests are record metadata — identity-invariant
  block:
    # Same-tree rebuild simulation: CI rebuilds the binaries on every
    # admission run and tools/hermetic_build.nim embeds BuildEnvBuildDate/
    # GitHash/CommitCount, so every artifact byte can differ while treeOID(B),
    # recipeDigest and the pins — the semantic identity — do not.
    var rebuilt = baseVerifierInputs()
    for i in 0 ..< rebuilt.artifactDigests.len:
      rebuilt.artifactDigests[i].digest = digest64("rebuilt-artifact-" & $i)
    doAssert validateVerifierIdentityInputs(rebuilt) == "",
      "precondition: the rebuilt-artifact inputs must still validate (record integrity holds)"
    let vidRebuilt = composeVerifierIdentity(rebuilt)
    doAssert vidRebuilt == base.verifierIdentity,
      "POSITIVE (e): artifact byte change (same-tree rebuild) must NOT move the verifier identity"
    doAssert deriveEvidenceKey(
      EvidenceKeyInputs(verifierIdentity: vidRebuilt,
        evidenceDraftDigest: base.evidenceDraftDigest,
        headTreeDigest: base.headTreeDigest,
        mergeTreeDigest: base.mergeTreeDigest,
        policyDigest: base.policyDigest,
        scopeDigest: base.scopeDigest)) == k1,
      "POSITIVE (e): a same-tree rebuild with different artifact bytes must yield the identical EvidenceKey"
    var renamed = rebuilt
    renamed.artifactDigests[0].name = "not-a-canonical-member"
    doAssert validateVerifierIdentityInputs(renamed) != "",
      "fail-closed: a non-canonical artifact name is rejected as RECORD metadata"
    var dropped = baseVerifierInputs(); dropped.artifactDigests = @[]
    doAssert composeVerifierIdentity(dropped) == base.verifierIdentity,
      "POSITIVE (e): the identity composition is artifact-blind even for an empty set"
    doAssert validateVerifierIdentityInputs(dropped) != "",
      "fail-closed: an empty artifact set is still rejected as RECORD metadata (identity-invariance does not waive record integrity)"
  echo "  OK: (e) artifact digests — record-level metadata: rebuild never moves the key; executed-set completeness stays enforced"

  # ── Fail-closed validation (missing ≠ valid-empty) ────────────────────────
  block:
    var noVerifier = base; noVerifier.verifierIdentity = ""
    var noDraft = base; noDraft.evidenceDraftDigest = ""
    var noHead = base; noHead.headTreeDigest = ""
    var noMerge = base; noMerge.mergeTreeDigest = ""
    var noPolicy = base; noPolicy.policyDigest = ""
    var noScope = base; noScope.scopeDigest = ""
    for (label, blank) in [("verifierIdentity", noVerifier),
                           ("evidenceDraftDigest", noDraft),
                           ("headTreeDigest", noHead),
                           ("mergeTreeDigest", noMerge),
                           ("policyDigest", noPolicy),
                           ("scopeDigest", noScope)]:
      doAssert validateEvidenceKeyInputs(blank) != "",
        "fail-closed: empty " & label & " must be rejected, never accepted as a valid-empty key input"
    var wrongShape = base; wrongShape.headTreeDigest = digest64("sixty-four-hex-not-a-tree-oid")
    doAssert validateEvidenceKeyInputs(wrongShape) != "",
      "fail-closed: a 64-hex tree member must be rejected (tree members are 40-hex git OIDs)"
    var uppercase = base
    uppercase.policyDigest = ($k1).toUpperAscii()
    doAssert validateEvidenceKeyInputs(uppercase) != "",
      "fail-closed: uppercase hex must be rejected (digest members are lowercase hex)"
    var truncated = base; truncated.scopeDigest = ($k1)[0 ..< 63]
    doAssert validateEvidenceKeyInputs(truncated) != "",
      "fail-closed: a 63-char digest member must be rejected (exact 64-hex required)"
  block:
    var v = baseVerifierInputs(); v.artifactDigests = @[]
    doAssert validateVerifierIdentityInputs(v) != "",
      "fail-closed: an incomplete executed-artifact set must be rejected"
    var v2 = baseVerifierInputs(); v2.baseTreeOid = digest64("not-an-oid")
    doAssert validateVerifierIdentityInputs(v2) != "",
      "fail-closed: a 64-hex baseTreeOid must be rejected (40-hex git tree OID required)"
    var v3 = baseVerifierInputs(); v3.z3Pin = ""
    doAssert validateVerifierIdentityInputs(v3) != "",
      "fail-closed: an empty z3Pin must be rejected (an identity that cannot name its Z3 pin is never derived)"
  echo "  OK: fail-closed validation — empty/malformed members rejected on both input types"

  # ── POSITIVE (d): matrix closure — no collisions, no empty keys ───────────
  doAssert matrix.len >= 14,
    "POSITIVE (d) precondition: the mutation matrix must be non-trivially populated (got " & $matrix.len & ")"
  for i, ki in matrix:
    doAssert ki.len == 64,
      "POSITIVE (d): no key in the matrix may be empty or short — matrix[" & $i & "] has length " & $ki.len
    for c in ki:
      doAssert c in {'0'..'9', 'a'..'f'},
        "POSITIVE (d): matrix[" & $i & "] must be lowercase hex (found '" & $c & "')"
    for j in (i + 1) ..< matrix.len:
      doAssert ki != matrix[j],
        "POSITIVE (d): no two distinct input sets may collide — matrix[" & $i & "] == matrix[" & $j & "]"
  echo "  OK: (d) matrix closure — " & $matrix.len & " derived keys, all distinct, all 64-hex"

  echo "=== Evidence CAS Identity OK ==="

main()
