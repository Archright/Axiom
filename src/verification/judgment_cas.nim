import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

## Judgment CAS — content-addressed REUSE of the s1a golden judgment.
##
## Terminal outcome: the computation of an identical verification is reused,
## the reuse itself is verifiable, and if anything differs by even a little,
## the original verification must run again.
##
## The s1a golden test (tests/unit/test_s1a_lean_golden.nim) is a genuine
## Lean-kernel judgment (17 kernel ACCEPTs through canonicalLeanKernelCheck +
## 14 canonical-chain probes). When its full execution closure is unchanged,
## a prior run's judgment is a durable FACT — the landing Evidence CAS pattern
## (verification/evidence_cas.nim) applied to the JUDGMENT surface:
##
##   EvidenceKey = H(JudgmentClosure) — the closure carries every input that
##   shapes the verdict and nothing run-scoped. The 9-component set is the
##   NORMATIVE contract (docs/spec/test_judgment_cas_contract.md §4); this
##   serialization keeps all nine, in fixed order:
##     ①+② test source + its transitive import closure as ONE member
##        (v5: derived from the TESTED TREE's git objects — the multi-hop,
##        AST-walked closure of verification/tested_tree_closure.nim; the
##        v4 member was a workdir-relative ONE-HOP measure whose
##        package-style imports never resolved)  ③ the three golden fixture
##        files (v5: the fixture blobs of the same tree)  ④ the measured
##        toolchain bundle (computeBundleDigest)  ⑤ the SEMANTIC SET digest —
##        S = TreeUniverse(R) − N over the tested tree R, derived by the
##        SINGLE derivation authority (verification/semantic_set_derivation.nim):
##        sha256 over the sorted `git ls-tree -r -z <R>` NUL-record stream of
##        the semantic members. The tree OID itself is the OUT-OF-KEY probe
##        anchor (b-probe-tree 4 propositions: caller-object-store
##        resolvable / key-non-participating / decision-file provenance
##        match / unverifiable → never REUSED → EXECUTED fallback)  ⑥ the
##        raw env snapshot the receipts digest (PATH, TMPDIR, AXIOM_LEAN_CMD,
##        AXIOM_IRCHECK_CMD, AXIOM_STATE_DIR, cwd)  ⑦ the build recipe (Makefile
##        · config.nims · tests/config.nims · config/effects.nims · nimble.lock)
##        ⑧ the compiler/semantic pins (NimVersion — the contract's standalone
##        member · SemanticProfileV1Hash · Z3 pin)  ⑨ the execution-config
##        digest (executionContractDigest over the canonical run contract).
##   Narrowing-only members BEYOND the nine (they can only turn a REUSED into
##   an EXECUTED, never the reverse): the four CompletenessEvidence keys
##   (re-derived from the SHARED golden fixture constructors —
##   verification/obligation/golden_fixture_ir.nim — never self-reported) and
##   VERIFICATION_SCHEMA_VERSION. No tree OID exists anywhere in the wire
##   (v1.0.4 p2 — the type is the contract): the verifier's execution identity
##   is bound by ④+⑧, its source/policy/spec inputs by ⑤ S, and the tested
##   tree's OID is the out-of-key probe anchor (§4.1). ciGeneration is a
##   member of NOTHING (§15.4).
##
##   Record = the EvidenceCasRecord envelope (evidence_ledger.nim) whose
##   payload is the canonical judgment projection: verdict field + the
##   minimal judgment evidence set — kernel ACCEPT facts ×17 (per-theorem
##   identities normalizeMaxWorkers_post / mulDivRoundtrip_post /
##   identityPostcondition / subPostcondition) + the 6-fold identity
##   (inputHash/irHash/obligationHash/leanSourceHash/kaaIdentity/
##   artifactIdentity) + the CLE identity members (cleKaaDigest/
##   cleCanonicalKaaJson/cleToolchainFingerprint) + the execution epoch.
##   The CLE's `evidenceId` is EXCLUDED: it is H(boundId|…) where the §2.1a
##   bound obligation identity transitively binds `subjectGitRef` — the
##   checkout's HEAD COMMIT hash — so two runs of the SAME closure (same
##   tested tree, different commit: branch head vs merge-queue merge commit)
##   derive different evidenceIds and hence different payload bytes for the
##   same key, tripping the ledger's same-key/different-payload guard
##   (evidence_ledger.appendEvidence, R2 mechanism defect). The contract
##   fixes the rule (test_judgment_cas_contract.md §4 v1.0.2 ③: run HEAD is
##   provenance, never identity); the payload now enforces it structurally —
##   every remaining member is a pure function of the closure, and the
##   validator rejects any field outside the canonical set so a run-scope
##   member can never re-enter the bytes. Provenance (observedAt, kernel
##   stdout, run ids) is EXCLUDED — a record is a fact, not a run.
##
##   Integrity chain (no signatures): payloadSha256 re-derived on EVERY read
##   + FF-only exactly-once ledger append (the mint publish job is the only
##   contents:write) + witness binding (the record's judgment projection must
##   byte-equal the witness's fresh projection — verdict field included).
##
##   REUSED basis (execution_accounting_contract §15.3 five-conditions shape):
##   closure re-derivation match (the key re-derived from the CURRENT
##   workspace equals the record key) + executionEpoch match (§15.3(e)) +
##   per-read re-hash (fetchEvidenceRecord) + witness binding pass. Anything
##   else — including a timeout FAIL — is never REUSED: the original s1a
##   execution runs. Records are only stored for ALL-ACCEPT runs.
##
## Fail-closed everywhere: a missing/unreadable/unverifiable input is an
## error, never an empty digest or a guessed reuse. Env unset/zero = the
## unarmed legacy state: no reads, no files, no log lines, byte-identical
## behavior.

import std/[algorithm, json, os, strutils]
import core/axiom_pragmas
import core/crypto/hash_kernel
import core/deterministic_cas_key
import core/results
import core/trusted/semantic_profile
import verification/attestation_orchestrator
import verification/canonical_json
import verification/accounting/execution_context
import verification/evidence_cas
import verification/evidence_ledger
import verification/ledger_side_ref
import verification/obligation/golden_fixture_ir
import verification/obligation/identity
import verification/obligation/lean_kernel_boundary
import verification/semantic_set_derivation
import verification/tested_tree_closure
import verification/verification_subject

when fileExists("src/generated/build_env.nim"):
  import generated/build_env
else:
  const BuildEnvZ3Version = ""

axiomIoBoundary()

# ---------------------------------------------------------------------------
# Canonical contract constants
# ---------------------------------------------------------------------------

const
  JudgmentKeyScheme* = "axiom.judgment.cas.key.v5"
    ## Domain separator for the judgment key wire — keys of different eras can
    ## never collide across scheme revisions. v5 is the M-TREE cutover: ①
    ## (the test-source closure) and ③ (the fixture set) are now derived from
    ## the TESTED tree's git objects instead of the working directory
    ## (verification/tested_tree_closure.nim) — the v4 ① was a WORKDIR-relative
    ## ONE-HOP walk (core/gate/transitive_hash.nim) whose package-style
    ## imports never resolved, so the measured closure was 19 files with
    ## depth ≥ 2 = 0: the identity did not cover the sources the judged test
    ## actually compiles. v5 walks the closure multi-hop from the tested tree
    ## (workdir-independent — the plan and the attest derive the same closure
    ## from the same tree) and classifies every import under the R-NT rule
    ## (tree member / pinned external / build-generated / unresolved). v4 is
    ## the p2 compliance cutover:
    ## the v3 wire still carried `verifierIdentity` — the KEPT verifier-identity
    ## pattern hashed over B's base tree OID (evidence_cas.nim
    ## collectVerifierIdentityInputs) — so every main landing advanced B^{tree}
    ## and re-keyed every closure even when S was provably unchanged: the same
    ## over-invalidation v1.0.3 removed from component ⑤, resurrected through a
    ## narrowing-only member. v1.0.4 applies §4.1 p2 literally — a tree OID
    ## appears NOWHERE in the closure wire (the type is the contract) — by
    ## removing the member entirely; the verifier's execution identity stays
    ## bound by ④ toolchainBundle + ⑧ compilerPins (§5(e)) and the verifier's
    ## source/policy/spec inputs by ⑤ S. v3 binds ⑤ to the semantic set digest
    ## S = TreeUniverse(R) − N (one derivation authority:
    ## verification/semantic_set_derivation.nim) — a STRICT narrowing: every
    ## v3-advancing change also advanced v2, so a v3 REUSED implies the v2
    ## closure identical too. The cutover orphans every v4-era record in one
    ## coherent generation (the v2→v3 and v3→v4 precedent: they remain
    ## immutable ledger history and can never re-verify as — or collide with —
    ## a v5 append); the new generation's first run is EXECUTED and re-mints.
    ## The payload schema is UNCHANGED (the projection members did not move —
    ## only the closure→key derivation), so the ledger's payloadSha256 sealing
    ## inherits verbatim.
  JudgmentPayloadSchema* = "axiom.judgment.cas.v2"
    ## The judgment projection schema — carried inside the payload; a record
    ## whose payload carries any other value is corrupt (fail-closed). v2
    ## removes the run-scope `cle.evidenceId` member: the payload is now a
    ## PURE function of the closure — same closure ⇒ byte-identical payload,
    ## so a second EXECUTED run of the same closure produces exactly the
    ## stored bytes and the ledger's same-key/different-payload guard can
    ## never fire on a legitimate re-derivation.
  JudgmentVerdictAcceptAll* = "KERNEL_ACCEPT_ALL"
    ## The only reusable verdict — every recorded kernel ACCEPT fact is an
    ## ACCEPT of the canonical 17-fact set. A timeout FAIL (or any other
    ## outcome) is never a REUSED candidate.
  JudgmentEnabledEnv* = "AXIOM_JUDGMENT_CAS_ENABLED"
  JudgmentRecordPathEnv* = "AXIOM_JUDGMENT_CAS_RECORD_PATH"
  JudgmentDecisionPathEnv* = "AXIOM_JUDGMENT_CAS_DECISION_PATH"
    ## The plan stage's decision file ({basis, evidenceKey, reason} — written by
    ## `ax cert judgment-plan --decision <path>`, consumed by the armed attest).
  JudgmentTestedTreeOidEnv* = "AXIOM_JUDGMENT_CAS_TESTED_TREE_OID"
    ## The TESTED tree's git tree OID — the b-probe-tree ANCHOR (contract
    ## component ⑤'s probe, v3): the executor checkout's tree,
    ## `git rev-parse HEAD^{tree}` at the plan/attest step. It is derived
    ## from the caller's object store, NEVER enters the key (the key carries
    ## the semantic set digest derived from it), and is recorded in the
    ## plan's decision file as provenance (cross-checked at attest).
    ## This module performs no git itself — the derivation authority
    ## (verification/semantic_set_derivation.nim) shells the ls-tree.
  JudgmentForceExecutionEnv* = "AXIOM_JUDGMENT_CAS_FORCE_EXECUTED"
    ## The workflow's explicit force-execution trigger: set to "1" by the
    ## admission workflow when its LANDING predicate fires — the merge_group
    ## venue must SHOW a fresh execution, so the plan's reuse path is blocked
    ## (jExecuted regardless of ledger state). Unset/other = current behavior.
  JudgmentMergeGroupEvent* = "merge_group"
    ## The GitHub event name of the landing venue. Belt trigger: inside the
    ## admission callee `GITHUB_EVENT_NAME` inherits the CALLER's event
    ## (observed live: `venue=landing` on the merge_group callee run
    ## 38983713057, `venue=preflight` on the pull_request callee runs
    ## 38990620435/38983249224), so the belt is LIVE code there — it arms the
    ## gate exactly when the caller venue is the merge_group landing, even
    ## if the explicit env wiring has not landed yet. Outside a GitHub
    ## runner the variable is unset and the belt is inert (local/dev runs
    ## keep the current behavior).
  S1aTestSourcePath* = "tests/unit/test_s1a_lean_golden.nim"
    ## The judged test source — closure component ①'s root.
  GoldenFixturePaths*: array[3, string] = [
    "tests/golden/sub_postcondition.nim",
    "tests/golden/identity_postcondition.nim",
    "tests/golden/mul_div_body.nim"]
    ## The three golden fixture files — closure component ③, fixed sorted
    ## order (sub, identity, mulDiv).
  JudgmentRecipePaths*: array[5, string] = [
    "Makefile",
    "config.nims",
    "tests/config.nims",
    "config/effects.nims",
    "nimble.lock"]
    ## The build-recipe/compile-flag set — closure component ⑦ (the contract
    ## names the Makefile recipe + tests/config.nims integrity guard), fixed
    ## order.
  CanonicalKernelAcceptCount* = 17
    ## The measured kernel-ACCEPT fact count of the s1a golden test (3 direct
    ## canonicalLeanKernelCheck calls + 14 inside executeCanonicalVerification).
    ## Part of the judgment contract: a run with any other count is not the
    ## canonical judgment and produces no record.
  CanonicalProbeCount* = 14
    ## The measured canonical-chain probe count (executeCanonicalVerification
    ## invocations: 1 sub + 1 mulDiv + 1 identity + 2 sub-determinism +
    ## 4 toolchain-fingerprint + 1 old-constant + 1 canonical-evidence +
    ## 1 evidenceId + 2 KAA-projection + 2 splice = 14).
  CanonicalTheoremIdentities*: array[4, string] = [
    "identityPostcondition_post",
    "mulDivRoundtrip_post",
    "normalizeMaxWorkers_post",
    "subPostcondition_post"]
    ## The theorem identities of the 17 ACCEPT facts — fixed sorted order.
    ## These are the DECLARED Lean theorem names of the rendered artifacts
    ## (canonical_verification.nim: `theorem <name>_post`), i.e. exactly the
    ## receiptTheoremIdentity each issued receipt carries.
  CanonicalAcceptsByTheorem*: array[4, int] = [3, 2, 1, 11]
    ## ACCEPT facts per theorem identity, aligned with
    ## CanonicalTheoremIdentities (sorted): identityPostcondition_post ×3
    ## (2 chain + 1 direct), mulDivRoundtrip_post ×2 (1 chain + 1 direct),
    ## normalizeMaxWorkers_post ×1 (direct), subPostcondition_post ×11
    ## (all chain). The sum is CanonicalKernelAcceptCount.

# ---------------------------------------------------------------------------
# Judgment subjects — the 4 GO-critical admission tests (contract §1)
# ---------------------------------------------------------------------------
#
# The s1a golden test was the Phase-3 slice; the other three GO-critical
# admission tests reuse the SAME 9-component closure machine, the SAME
# 5-condition reuse basis, and the SAME record envelope. Only the per-test
# judgment evidence set (the payload body — contract §5 (d)) and the
# per-test closure roots differ:
#   proof_integrity — pure predicate judgment, kernel 0 runs: the verdict is
#     the canonical checkpoint verdict set of isVkdAdmissible/isDeepVerified.
#   d2_golden — kernel 14 runs: the receipt identity 4 + the 5-fold C1
#     identity chain of the judged d2Golden canonical execution.
#   d2_persist — the persistence loop judgment: kernel 1 run + the
#     cert_writer→reader round-trip checkpoint set.
# The s1a key wire is NOT touched: its closure members, payload schema and
# verdict stay byte-identical, so every s1a record ever minted (and the live
# b5b10096965b cycle) remains reachable. Cross-subject key separation is
# structural: component ① is the SUBJECT'S OWN test source transitive hash.

const
  ProofIntegrityTestSourcePath* = "tests/unit/proof_integrity_test.nim"
  D2GoldenTestSourcePath* = "tests/unit/test_d2_golden.nim"
  D2PersistTestSourcePath* = "tests/unit/test_d2_persist.nim"

  ProofIntegrityFixturePaths*: array[1, string] = [
    "src/core/vault/vault_manager_spec.nim"]
    ## The one file the proof-integrity suite reads at runtime (readSource —
    ## the source-fingerprint stage-2 inputs). Closure component ③.
  D2GoldenFixturePaths*: array[0, string] = []
    ## The d2_golden judged artifact is the inline D2GoldenSource constant —
    ## no file fixtures (component ③ = chained digest over the empty set).
  D2PersistFixturePaths*: array[0, string] = []
    ## d2_persist writes/reads a temp cert dir it creates — no repo fixtures.

  ProofIntegrityPayloadSchema* = "axiom.judgment.cas.proof_integrity.v1"
  D2GoldenPayloadSchema* = "axiom.judgment.cas.d2_golden.v1"
  D2PersistPayloadSchema* = "axiom.judgment.cas.d2_persist.v1"

  JudgmentVerdictPredicatePassAll* = "PREDICATE_PASS_ALL"
    ## The only reusable verdict of the proof-integrity subject: every
    ## canonical checkpoint observed its canonical predicate verdict.
  JudgmentVerdictPersistLoopVerified* = "PERSIST_LOOP_VERIFIED"
    ## The only reusable verdict of the d2_persist subject: the kernel-backed
    ## certificate survived the real writer→reader round-trip.

  ProofIntegrityCheckpointCount* = 12
    ## The canonical predicate checkpoints of the proof-integrity judgment.
  D2GoldenKernelRunCount* = 14
    ## The measured kernel-execution count of the d2_golden suite (Stage 1 ×4,
    ## Stage 2 ×2, Stage 3 ×2, Stage 4 chain ×5, golden summary ×1).
  D2PersistKernelRunCount* = 1
    ## The measured kernel-execution count of the d2_persist suite (Stage 1).
  D2GoldenTheoremIdentity* = "d2Golden"
    ## The theorem identity of both d2 subjects' judged canonical execution.

  CanonicalProofIntegrityCheckpoints*: array[12, string] = [
    "admissionAdmit",
    "admissionExemptIsScopeInconsistency",
    "admissionNoObligationRejects",
    "emptyScopeDegradedMode",
    "freshCertAccepts",
    "kernelScopeSymbolInDenominator",
    "kernelScopeSymbolOutOfDenominator",
    "kernelSymbolInDenominator",
    "kernelSymbolNotInDenominator",
    "nonKernelMemberNotChecked",
    "renewedCertAccepts",
    "staleCertSourceHashMismatch"]
    ## The canonical checkpoint names — fixed sorted order.
  CanonicalProofIntegrityVerdicts*: array[12, string] = [
    "varAdmit",
    "varScopeInconsistency",
    "varReject",
    "dvcSuccess",
    "dvcSuccess",
    "true",
    "false",
    "dvcSuccess",
    "dvcNotInKernelScope",
    "dvcSuccess",
    "dvcSuccess",
    "dvcNotCurrent"]
    ## The canonical verdict per checkpoint, aligned with
    ## CanonicalProofIntegrityCheckpoints: admissionAdmit→varAdmit,
    ## admissionExemptIsScopeInconsistency→varScopeInconsistency,
    ## admissionNoObligationRejects→varReject, emptyScopeDegradedMode→
    ## dvcSuccess, freshCertAccepts→dvcSuccess,
    ## kernelScopeSymbolInDenominator→true,
    ## kernelScopeSymbolOutOfDenominator→false,
    ## kernelSymbolInDenominator→dvcSuccess,
    ## kernelSymbolNotInDenominator→dvcNotInKernelScope,
    ## nonKernelMemberNotChecked→dvcSuccess, renewedCertAccepts→dvcSuccess,
    ## staleCertSourceHashMismatch→dvcNotCurrent.

  CanonicalD2PersistLoopCheckpoints*: array[7, string] = [
    "evidenceLeanVerified",
    "kernelFlagFromKaa",
    "leanCompilerVerified",
    "statusCertLeanVerified",
    "statusConsistentWithEvidence",
    "tierLeanVerified",
    "writerPersisted"]
    ## The canonical writer→reader loop checkpoints — fixed sorted order.

type
  JudgmentSubject* = enum
    jsS1aGolden
    jsProofIntegrity
    jsD2Golden
    jsD2Persist

func subjectName*(s: JudgmentSubject): string {.raises: [].} =
  case s
  of jsS1aGolden: "s1a"
  of jsProofIntegrity: "proof_integrity"
  of jsD2Golden: "d2_golden"
  of jsD2Persist: "d2_persist"

func parseJudgmentSubject*(name: string): Result[JudgmentSubject, string] {.
    raises: [].} =
  for s in JudgmentSubject:
    if subjectName(s) == name:
      return ok(s)
  err("judgment_cas: unknown judgment subject '" & name &
    "' (known: s1a, proof_integrity, d2_golden, d2_persist)")

func allJudgmentSubjects*: array[4, JudgmentSubject] {.raises: [].} =
  [jsS1aGolden, jsProofIntegrity, jsD2Golden, jsD2Persist]

func allJudgmentSubjectsJson*: string {.raises: [].} =
  ## The canonical read-only projection of the judgment subject SSOT —
  ## `{"subjects":[...]}` in SSOT (enum) order, RFC 8785 canonical bytes.
  ## `ax cert judgment-subjects --json` echoes it verbatim; pure, no side
  ## effects, no network.
  var names = newJArray()
  for s in allJudgmentSubjects():
    names.add(%subjectName(s))
  canonicalJsonString(%*{"subjects": names})

func subjectTestSourcePath*(s: JudgmentSubject): string {.raises: [].} =
  case s
  of jsS1aGolden: S1aTestSourcePath
  of jsProofIntegrity: ProofIntegrityTestSourcePath
  of jsD2Golden: D2GoldenTestSourcePath
  of jsD2Persist: D2PersistTestSourcePath

func subjectPayloadSchema*(s: JudgmentSubject): string {.raises: [].} =
  case s
  of jsS1aGolden: JudgmentPayloadSchema
  of jsProofIntegrity: ProofIntegrityPayloadSchema
  of jsD2Golden: D2GoldenPayloadSchema
  of jsD2Persist: D2PersistPayloadSchema

func subjectDecisionPathEnv*(s: JudgmentSubject): string {.raises: [].} =
  ## The plan stage's decision-file env — s1a keeps its unsuffixed name (the
  ## landed wire); the extension subjects are suffixed per subject.
  case s
  of jsS1aGolden: JudgmentDecisionPathEnv
  of jsProofIntegrity: "AXIOM_JUDGMENT_CAS_DECISION_PATH_PROOF_INTEGRITY"
  of jsD2Golden: "AXIOM_JUDGMENT_CAS_DECISION_PATH_D2_GOLDEN"
  of jsD2Persist: "AXIOM_JUDGMENT_CAS_DECISION_PATH_D2_PERSIST"

func subjectRecordPathEnv*(s: JudgmentSubject): string {.raises: [].} =
  case s
  of jsS1aGolden: JudgmentRecordPathEnv
  of jsProofIntegrity: "AXIOM_JUDGMENT_CAS_RECORD_PATH_PROOF_INTEGRITY"
  of jsD2Golden: "AXIOM_JUDGMENT_CAS_RECORD_PATH_D2_GOLDEN"
  of jsD2Persist: "AXIOM_JUDGMENT_CAS_RECORD_PATH_D2_PERSIST"

func subjectEvidencePathEnv*(s: JudgmentSubject): string {.raises: [].} =
  ## The armed flush target env the SUBJECT'S test binary reads.
  case s
  of jsS1aGolden: "AXIOM_JUDGMENT_CAS_EVIDENCE_PATH"
  of jsProofIntegrity: "AXIOM_JUDGMENT_CAS_EVIDENCE_PATH_PROOF_INTEGRITY"
  of jsD2Golden: "AXIOM_JUDGMENT_CAS_EVIDENCE_PATH_D2_GOLDEN"
  of jsD2Persist: "AXIOM_JUDGMENT_CAS_EVIDENCE_PATH_D2_PERSIST"

# ---------------------------------------------------------------------------
# Judgment closure — the 9 components + the verifier identity (pure)
# ---------------------------------------------------------------------------

type
  JudgmentClosure* = object
    ## The declared member set of the judgment key. This object is the whole
    ## derivation surface: a caller cannot feed an input that is not one of
    ## the nine contract components (docs/spec/test_judgment_cas_contract.md
    ## §4) or a narrowing-only member without widening this type, and the
    ## type is the contract.
    testSourceClosure*: string       ## ①+② transitive hash of the s1a test source
    goldenFixtures*: string          ## ③ chained digest over the 3 fixture files
    toolchainBundle*: string         ## ④ measured bundle digest (computeBundleDigest)
    semanticSetDigest*: string       ## ⑤ v3 — S = TreeUniverse(R) − N set digest (semantic_set_derivation)
    envSnapshot*: string             ## ⑥ raw env snapshot digest (receipt-style)
    recipe*: string                  ## ⑦ chained digest over JudgmentRecipePaths
    compilerPins*: string            ## ⑧ NimVersion · SemanticProfileV1Hash · Z3 pin
    executionConfig*: string         ## ⑨ execution-config digest (canonical run contract)
    completenessKeys*: array[4, string] ## narrowing-only: re-derived CompletenessEvidence keys
    schemaVersion*: string           ## narrowing-only: VERIFICATION_SCHEMA_VERSION
    pinIdentity*: string             ## narrowing-only: the pinned external dependency
                                    ## identities the closure rests on (R-NT (b) —
                                    ## the nimble.lock entries). It RECORDS which
                                    ## pin the reuse rests on; it adds NO new
                                    ## invalidation: any pin change already advances
                                    ## ⑤ (nimble.lock is a normative exact path —
                                    ## W ∩ N = ∅ enforced) and ⑦ (the recipe
                                    ## member), so the key advances on a pin change
                                    ## with or without this member. Narrowing-only:
                                    ## it can only turn a REUSED into an EXECUTED.

func closureWire*(c: JudgmentClosure): string {.raises: [].} =
  ## Canonical closure serialization — fixed member set, RFC 8785 key order,
  ## explicit separators, UTF-8 bytes.
  canonicalJsonString(%*{
    "schema": JudgmentKeyScheme,
    "testSourceClosure": c.testSourceClosure,
    "goldenFixtures": c.goldenFixtures,
    "toolchainBundle": c.toolchainBundle,
    "semanticSetDigest": c.semanticSetDigest,
    "envSnapshot": c.envSnapshot,
    "recipe": c.recipe,
    "compilerPins": c.compilerPins,
    "executionConfig": c.executionConfig,
    "completenessKeys": c.completenessKeys,
    "schemaVersion": c.schemaVersion,
    "pinIdentity": c.pinIdentity})

func deriveJudgmentKey*(c: JudgmentClosure): string {.raises: [].} =
  ## JudgmentKey = H(canonical closure wire). Pure.
  sha256Hex(closureWire(c))

func validateJudgmentClosure*(c: JudgmentClosure): string {.raises: [].} =
  ## "" = well-formed; otherwise the rejection reason. Every digest member is
  ## 64-hex, the tested tree OID is a 40-hex git OID; empty is never valid — a
  ## missing input surfaces here instead of degenerating the identity.
  for (label, value) in [("testSourceClosure", c.testSourceClosure),
                         ("goldenFixtures", c.goldenFixtures),
                         ("toolchainBundle", c.toolchainBundle),
                         ("semanticSetDigest", c.semanticSetDigest),
                         ("envSnapshot", c.envSnapshot),
                         ("recipe", c.recipe),
                         ("compilerPins", c.compilerPins),
                         ("executionConfig", c.executionConfig)]:
    if not isHexOfLen(value, 64):
      return "judgment_cas: closure " & label & " must be 64 lowercase hex chars (fail-closed)"
  for i, k in c.completenessKeys:
    if not isHexOfLen(k, 64):
      return "judgment_cas: closure completenessKeys[" & $i & "] must be 64 lowercase hex chars (fail-closed)"
  if c.schemaVersion != $VERIFICATION_SCHEMA_VERSION:
    return "judgment_cas: closure schemaVersion must be the current VERIFICATION_SCHEMA_VERSION (fail-closed)"
  # The pin identity is a canonical record — the lock entries joined by "|",
  # each "name@version#vcsRevision#sha1". A whitespace or control character
  # in it means the record was not built by the derivation (fail-closed).
  for ch in c.pinIdentity:
    if ch in {' ', '\t', '\n', '\r'}:
      return "judgment_cas: closure pinIdentity carries a whitespace character (fail-closed)"
  ""

func envSnapshotDigest*(path: string; tmpdir, leanCmd, ircheckCmd, stateDir: string;
                        cwd: string): string {.raises: [].} =
  ## Closure component ⑥ — the RAW env snapshot the kernel receipts digest
  ## ("receipt가 원문 소화"): the original text of each variable, one per
  ## line, no canonicalization. An unset variable contributes its empty
  ## string — the snapshot is over the OBSERVED environment, and any change
  ## (even whitespace) moves the key.
  sha256Hex(
    "PATH=" & path & "\n" &
    "TMPDIR=" & tmpdir & "\n" &
    "AXIOM_LEAN_CMD=" & leanCmd & "\n" &
    "AXIOM_IRCHECK_CMD=" & ircheckCmd & "\n" &
    "AXIOM_STATE_DIR=" & stateDir & "\n" &
    "cwd=" & cwd & "\n")

# ---------------------------------------------------------------------------
# I/O boundary — fail-closed closure collection
# ---------------------------------------------------------------------------

proc fileDigestHexOrErr(path: string): Result[string, string] {.
  raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## sha256 over the raw bytes of ONE file — missing/unreadable/empty → err
  ## (fail-closed). Empty digests are never substituted for missing data.
  if not fileExists(path):
    return err("judgment_cas: file not found (fail-closed): " & path)
  let bytes =
    try: readFile(path)
    except CatchableError as e:
      return err("judgment_cas: file unreadable (fail-closed): " & path & ": " & e.msg)
  if bytes.len == 0:
    return err("judgment_cas: file is empty (fail-closed): " & path)
  ok(sha256Hex(bytes))

proc collectChainedDigest*(paths: openArray[string]): Result[string, string] {.
  raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Chained content digest over a FIXED path set in the given order
  ## (`<rel>:<bytes>\n` per member), fail-closed per member — the
  ## evidence_cas.collectChainedFileDigest pattern.
  var content = ""
  for rel in paths:
    if not fileExists(rel):
      return err("judgment_cas: chained digest input missing (fail-closed): " & rel)
    let bytes =
      try: readFile(rel)
      except CatchableError as e:
        return err("judgment_cas: chained digest input unreadable (fail-closed): " & rel & ": " & e.msg)
    content.add(rel & ":" & bytes & "\n")
  ok(sha256Hex(content))

proc judgmentRecordingPathsExist*(): bool {.raises: [].} =
  fileExists(S1aTestSourcePath)

proc subjectFixturePaths*(s: JudgmentSubject): seq[string] {.raises: [].} =
  ## The subject's fixture set — closure component ③'s input.
  case s
  of jsS1aGolden:
    for p in GoldenFixturePaths: result.add(p)
  of jsProofIntegrity:
    for p in ProofIntegrityFixturePaths: result.add(p)
  of jsD2Golden:
    for p in D2GoldenFixturePaths: result.add(p)
  of jsD2Persist:
    for p in D2PersistFixturePaths: result.add(p)

proc deriveSubjectTreeClosure*(s: JudgmentSubject; treeOid: string): Result[TestedTreeClosure, string] {.
  raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## ① + ③ from the TESTED TREE — the subject's test-source closure and its
  ## fixture set, derived from the tree's git objects (verification/
  ## tested_tree_closure.nim). Workdir-independent: the plan stage and the
  ## attest stage derive the SAME closure from the SAME tree.
  let derived =
    try: deriveTestedTreeClosure(".", treeOid, @[subjectTestSourcePath(s)],
        subjectFixturePaths(s))
    except CatchableError as e:
      return err("judgment_cas: tested-tree closure derivation raised (fail-closed): " & e.msg)
  if derived.isErr:
    return err(derived.error)
  if derived.get.nonReusable.len > 0:
    return err("judgment_cas: the tested-tree closure is not reusable — " &
      derived.get.nonReusable.join(" · ") &
      " (fail-closed: an unresolved/unpinned dependency never grants a REUSED)")
  ok(derived.get)

proc collectTestSourceClosure*(treeOid: string): Result[string, string] {.
  raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Closure component ① — the s1a test source + its transitive import
  ## closure, derived from the TESTED TREE (v5: the v4 walk was a
  ## workdir-relative ONE-HOP measure — package-style imports never resolved,
  ## so the closure was 19 files with depth ≥ 2 = 0). Fail-closed.
  let derived = deriveSubjectTreeClosure(jsS1aGolden, treeOid)
  if derived.isErr:
    return err(derived.error)
  let h = derived.get.sourceDigest
  if h.len != 64:
    return err("judgment_cas: the tested-tree closure digest of " &
      S1aTestSourcePath & " is not a 64-hex digest (fail-closed): '" & h & "'")
  ok(h)

proc collectGoldenFixturesDigest*(treeOid: string): Result[string, string] {.
  raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Closure component ③ — the 3 golden fixture files' digest, derived from
  ## the TESTED TREE's blob OIDs (v5; the v4 member was a workdir content
  ## digest).
  let derived = deriveSubjectTreeClosure(jsS1aGolden, treeOid)
  if derived.isErr:
    return err(derived.error)
  let h = derived.get.fixturesDigest
  if h.len != 64:
    return err("judgment_cas: the tested-tree fixture digest is not a 64-hex " &
      "digest (fail-closed): '" & h & "'")
  ok(h)

proc subjectCompletenessKeys*(s: JudgmentSubject): array[4, string] {.
    raises: [].} =
  ## The closure's narrowing-only 4-key slot, per subject. s1a keeps the
  ## re-derived golden CompletenessEvidence keys (the landed wire). The
  ## extension subjects pin their EVIDENCE-SCHEMA ERA (schema · canonical
  ## member set · verdict vocabulary · fixture root set): a schema revision
  ## moves the key, so a record of the old era can never re-verify as the
  ## new one. Narrowing-only: they can turn a REUSED into an EXECUTED, and
  ## a stale-era record is never resurrected, never the reverse.
  case s
  of jsS1aGolden:
    goldenCompletenessKeys()
  else:
    var members = ""
    case s
    of jsProofIntegrity:
      for i, name in CanonicalProofIntegrityCheckpoints:
        members.add(name & "=" & CanonicalProofIntegrityVerdicts[i] & ";")
    of jsD2Golden:
      members = "receipt{executableDigest,inputIdentity,artifactIdentity," &
        "toolchainFingerprint};chain{artifact,execution,kaa,decision,result};"
    of jsD2Persist:
      for name in CanonicalD2PersistLoopCheckpoints:
        members.add(name & "=true;")
    of jsS1aGolden:
      discard
    var fixtures = ""
    case s
    of jsProofIntegrity:
      for p in ProofIntegrityFixturePaths: fixtures.add(p & ";")
    of jsD2Golden:
      for p in D2GoldenFixturePaths: fixtures.add(p & ";")
    of jsD2Persist:
      for p in D2PersistFixturePaths: fixtures.add(p & ";")
    of jsS1aGolden:
      discard
    let prefix = "axiom.judgment.cas.subject." & subjectName(s)
    [sha256Hex(prefix & "|schema|" & subjectPayloadSchema(s)),
     sha256Hex(prefix & "|members|" & members),
     sha256Hex(prefix & "|verdict|" &
       (case s
        of jsProofIntegrity: JudgmentVerdictPredicatePassAll
        of jsD2Golden: JudgmentVerdictAcceptAll
        of jsD2Persist: JudgmentVerdictPersistLoopVerified
        of jsS1aGolden: JudgmentVerdictAcceptAll)),
     sha256Hex(prefix & "|fixtures|" & fixtures)]

proc subjectSourceClosure*(s: JudgmentSubject; treeOid: string): Result[string, string] {.
  raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Closure component ① for a subject — the subject's own test source +
  ## its transitive import closure, derived from the TESTED TREE (fail-closed).
  let derived = deriveSubjectTreeClosure(s, treeOid)
  if derived.isErr:
    return err(derived.error)
  let h = derived.get.sourceDigest
  if h.len != 64:
    return err("judgment_cas: the tested-tree closure digest of " &
      subjectTestSourcePath(s) & " is not a 64-hex digest (fail-closed): '" & h & "'")
  ok(h)

proc subjectFixturesDigest*(s: JudgmentSubject; treeOid: string): Result[string, string] {.
  raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Closure component ③ for a subject — the fixture set's digest from the
  ## TESTED TREE's blob OIDs (an empty set is a valid, deterministic member).
  let derived = deriveSubjectTreeClosure(s, treeOid)
  if derived.isErr:
    return err(derived.error)
  let h = derived.get.fixturesDigest
  if h.len != 64:
    return err("judgment_cas: the tested-tree fixture digest for " &
      subjectName(s) & " is not a 64-hex digest (fail-closed): '" & h & "'")
  ok(h)

proc collectRecipeDigest*(): Result[string, string] {.
  raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Closure component ⑥ — chained digest over the build-recipe set.
  collectChainedDigest(JudgmentRecipePaths)

func compilerPinsDigest*(): Result[string, string] {.raises: [].} =
  ## Closure component ⑦ — NimVersion · SemanticProfileV1Hash · the Z3 pin,
  ## all compile-time constants of the executing binary. The Z3 pin is
  ## fail-closed (an identity that cannot name its Z3 pin is never derived),
  ## mirroring evidence_cas.collectZ3Pin.
  if BuildEnvZ3Version.len == 0:
    return err("judgment_cas: Z3 pin unavailable in build metadata (fail-closed)")
  ok(sha256Hex(
    "nim=" & $NimVersion &
    "|semanticProfile=" & SemanticProfileV1Hash &
    "|z3=" & BuildEnvZ3Version))

proc collectToolchainBundleDigest*(): Result[string, string] {.
  raises: [CatchableError], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Closure component ③ — the measured toolchain bundle digest, resolved
  ## through the SAME resolution the kernel check uses (QUIRK(DEBT#427): an
  ## elan shim may point elsewhere — both sides of a comparison must resolve
  ## the same binary).
  let leanCmd = getEnv("AXIOM_LEAN_CMD", "")
  let resolvedCmd = if leanCmd.len > 0: leanCmd else: "lake env lean"
  let leanPath = resolveLeanBinaryPath()
  if leanPath.len == 0:
    return err("judgment_cas: cannot resolve lean executable (fail-closed)")
  let lakePath = findExe("lake")
  if lakePath.len == 0:
    return err("judgment_cas: cannot resolve lake executable (fail-closed)")
  ok(computeBundleDigest(leanPath, lakePath, bundleDigestTimeoutMs, resolvedCmd))

proc judgmentWitnessPaths*(s: JudgmentSubject): seq[string] {.raises: [].} =
  ## The subject's known-input witness set W (contract §4.1 포함-증인):
  ## the recipe members, the subject's own test source + fixtures, and the
  ## declared computed staticRead targets (the k12 compile-input face —
  ## semantic_set_derivation.ComputedStaticReadTargets). The derivation
  ## authority refuses the whole closure when any member is absent from the
  ## tested tree or excluded by the no-effect table (W ⊆ S ∧ W ∩ N = ∅).
  result = @[]
  for p in JudgmentRecipePaths:
    result.add(p)
  result.add(subjectTestSourcePath(s))
  case s
  of jsS1aGolden:
    for p in GoldenFixturePaths: result.add(p)
  of jsProofIntegrity:
    for p in ProofIntegrityFixturePaths: result.add(p)
  of jsD2Golden, jsD2Persist:
    discard
  for t in ComputedStaticReadTargets:
    result.add(t)

type
  JudgmentClosureBundle* = object
    ## The closure + the dependency audit trail. The plan stage records the
    ## notes in its decision file — every (b)/(c)/(d) dependency hit is
    ## recorded, never silently skipped.
    closure*: JudgmentClosure
    notes*: seq[string]

proc collectJudgmentClosureBundle*(s: JudgmentSubject;
    probeTreeOid: string): Result[JudgmentClosureBundle, string] {.
  raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## The 9-component closure for ONE subject, plus the dependency audit
  ## trail. ① (the subject's test-source closure) and ③ (its fixture set)
  ## are derived from the TESTED TREE's git objects (v5 — workdir-
  ## independent: the plan and the attest derive the same closure from the
  ## same tree); ⑤ is the SEMANTIC SET digest of the probe tree, derived by
  ## the single derivation authority; ④⑥⑦⑧⑨ stay executor/process-measured
  ## (unchanged). The probe OID never enters the key (b-probe-tree p2) and no
  ## base-tree OID does either (v1.0.4 p2 — no tree OID anywhere in the
  ## wire). An unresolvable probe, a witness violation, an unparsable source
  ## or a non-reusable dependency is an err (fail-closed → EXECUTED, p4).
  let sem =
    try: deriveSemanticSet(".", probeTreeOid, judgmentWitnessPaths(s))
    except CatchableError as e:
      return err("judgment_cas: semantic set derivation raised (fail-closed): " & e.msg)
  if sem.isErr: return err(sem.error)
  let treeClosure = deriveSubjectTreeClosure(s, probeTreeOid)
  if treeClosure.isErr: return err(treeClosure.error)
  var c = JudgmentClosure(
    testSourceClosure: treeClosure.get.sourceDigest,
    goldenFixtures: treeClosure.get.fixturesDigest,
    toolchainBundle: "",
    semanticSetDigest: sem.get.semanticDigest,
    envSnapshot: "",
    recipe: "",
    compilerPins: "",
    executionConfig: "",
    completenessKeys: subjectCompletenessKeys(s),
    schemaVersion: $VERIFICATION_SCHEMA_VERSION,
    pinIdentity: treeClosure.get.pinIdentity)
  let bundle = collectToolchainBundleDigest()
  if bundle.isErr: return err(bundle.error)
  c.toolchainBundle = bundle.get
  let recipe = collectRecipeDigest()
  if recipe.isErr: return err(recipe.error)
  c.recipe = recipe.get
  let pins = compilerPinsDigest()
  if pins.isErr: return err(pins.error)
  c.compilerPins = pins.get
  c.executionConfig = executionContractDigest(
    canonicalExecutionContractForRun(getCurrentDir()))
  c.envSnapshot = envSnapshotDigest(
    getEnv("PATH", ""), getEnv("TMPDIR", ""), getEnv("AXIOM_LEAN_CMD", ""),
    getEnv("AXIOM_IRCHECK_CMD", ""), getEnv("AXIOM_STATE_DIR", ""),
    getCurrentDir())
  let problem = validateJudgmentClosure(c)
  if problem.len > 0:
    return err(problem)
  ok(JudgmentClosureBundle(closure: c, notes: treeClosure.get.notes))

proc collectJudgmentClosure*(probeTreeOid: string): Result[JudgmentClosure, string] {.
  raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## The s1a closure (the landed subject) — the bundle's closure.
  let bundle = collectJudgmentClosureBundle(jsS1aGolden, probeTreeOid)
  if bundle.isErr: return err(bundle.error)
  ok(bundle.get.closure)

proc collectJudgmentClosureFor*(s: JudgmentSubject;
    probeTreeOid: string): Result[JudgmentClosure, string] {.
  raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## The same 9-component machine, per subject: the subject's own test-source
  ## transitive closure (①+②), its own fixture set (③), and its own
  ## narrowing-only completeness keys. Component ⑤ is the SHARED semantic
  ## set digest of the probe tree (the subject's witness set still spans its
  ## own known inputs). Every other component (④ toolchain bundle, ⑥ env
  ## snapshot, ⑦ recipe, ⑧ compiler pins, ⑨ execution config) is SHARED
  ## machinery — the same measured values the s1a closure carries. The probe
  ## OID never enters the key (b-probe-tree p2) and no base-tree OID does
  ## either (v1.0.4 p2 — no tree OID anywhere in the wire).
  let bundle = collectJudgmentClosureBundle(s, probeTreeOid)
  if bundle.isErr: return err(bundle.error)
  ok(bundle.get.closure)

# ---------------------------------------------------------------------------
# Judgment evidence — the measured minimal set (the test's emission)
# ---------------------------------------------------------------------------

type
  JudgmentAcceptFacts* = object
    ## The kernel-ACCEPT facts observed in one test process (the
    ## lean_kernel_boundary observation log, aggregated).
    acceptsByTheorem*: array[4, int]  ## aligned with CanonicalTheoremIdentities
    unknownTheorems*: seq[string]     ## ACCEPT facts outside the canonical set

func aggregateAcceptFacts*(accepts: openArray[tuple[theoremIdentity: string, inputIdentity: string]]): JudgmentAcceptFacts {.
    raises: [].} =
  ## Aggregate the observed ACCEPT log into the per-theorem counts. An ACCEPT
  ## outside the canonical theorem set is recorded as an anomaly — it can
  ## never pass validation, and it is never silently dropped.
  var facts = JudgmentAcceptFacts(unknownTheorems: @[])
  for (thm, _) in accepts:
    var idx = -1
    for i, canonical in CanonicalTheoremIdentities:
      if thm == canonical:
        idx = i
        break
    if idx >= 0:
      inc facts.acceptsByTheorem[idx]
    else:
      facts.unknownTheorems.add(thm)
  facts

type
  JudgmentFoldIdentity* = object
    ## The 6-fold identity of the judged canonical execution (sub fixture).
    inputHash*: string
    irHash*: string
    obligationHash*: string
    leanSourceHash*: string
    kaaIdentity*: string
    artifactIdentity*: string

  JudgmentCleIdentity* = object
    ## The CLE identity members of the judged canonical execution — the
    ## CLOSURE-PURE projection only. The CLE's `evidenceId` is deliberately
    ## absent: it is H(boundId|…) and the §2.1a bound identity transitively
    ## binds the checkout's HEAD commit (subjectGitRef), a run-scope digest —
    ## carrying it made the payload bytes commit-dependent for the same
    ## closure (the R2 same-key/different-payload defect). The type is the
    ## separation surface: a caller cannot feed a run-scope member into the
    ## payload.
    cleKaaDigest*: string
    cleCanonicalKaaJson*: string
    cleToolchainFingerprint*: string

  JudgmentMeasuredEvidence* = object
    kernelAcceptCount*: int
    probeCount*: int
    facts*: JudgmentAcceptFacts
    fold*: JudgmentFoldIdentity
    cle*: JudgmentCleIdentity

func judgmentEvidenceWire*(e: JudgmentMeasuredEvidence; completenessKeys: array[4, string];
                           executionEpoch: string): string {.raises: [].} =
  ## The canonical judgment projection — the payload bytes and the witness
  ## projection source. The verdict field is REQUIRED (P7b-shape binding):
  ## the projection states the verdict it claims. Pure function of its
  ## inputs: every member is closure-scoped (fold + the CLE closure-pure
  ## members + counts + verdict + epoch), so the same closure re-measured by
  ## a later run yields byte-identical payload. Provenance excluded.
  canonicalJsonString(%*{
    "schemaVersion": JudgmentPayloadSchema,
    "verdict": JudgmentVerdictAcceptAll,
    "kernelAcceptCount": e.kernelAcceptCount,
    "probeCount": e.probeCount,
    "acceptsByTheorem": {
      CanonicalTheoremIdentities[0]: e.facts.acceptsByTheorem[0],
      CanonicalTheoremIdentities[1]: e.facts.acceptsByTheorem[1],
      CanonicalTheoremIdentities[2]: e.facts.acceptsByTheorem[2],
      CanonicalTheoremIdentities[3]: e.facts.acceptsByTheorem[3]},
    "fold": {
      "inputHash": e.fold.inputHash,
      "irHash": e.fold.irHash,
      "obligationHash": e.fold.obligationHash,
      "leanSourceHash": e.fold.leanSourceHash,
      "kaaIdentity": e.fold.kaaIdentity,
      "artifactIdentity": e.fold.artifactIdentity},
    "cle": {
      "cleKaaDigest": e.cle.cleKaaDigest,
      "cleCanonicalKaaJson": e.cle.cleCanonicalKaaJson,
      "cleToolchainFingerprint": e.cle.cleToolchainFingerprint},
    "completenessKeys": completenessKeys,
    "executionEpoch": executionEpoch})

func exactFieldSet(node: JsonNode; allowed: openArray[string]; what: string): string {.
    raises: [].} =
  ## "" when the object carries EXACTLY the allowed field set — a missing or
  ## EXTRA field is a contract violation. Extra fields matter for integrity,
  ## not hygiene: the payload bytes are the canonical serialization of the
  ## node, so an extra (potentially run-scope) field would flow into the
  ## stored bytes and break the same-closure ⇒ same-payload-bytes invariant
  ## (fail-closed).
  if node.len != allowed.len:
    return "judgment_cas: payload " & what & " must carry exactly " & $allowed.len &
      " canonical fields, got " & $node.len & " (fail-closed)"
  for key, _ in node.pairs:
    var known = false
    for a in allowed:
      if key == a:
        known = true
        break
    if not known:
      return "judgment_cas: payload " & what & " carries a non-canonical field '" &
        key & "' (fail-closed)"
  ""

func validateS1aJudgmentPayloadNode*(node: JsonNode): Result[JudgmentMeasuredEvidence, string] {.
    raises: [].} =
  ## Strict validation of a judgment projection (from the test's evidence file
  ## or a stored record). Fail-closed on every contract:
  ##   * schemaVersion == JudgmentPayloadSchema
  ##   * verdict == JudgmentVerdictAcceptAll (only ALL-ACCEPT is reusable)
  ##   * kernelAcceptCount == 17 ∧ probeCount == 14 (the canonical set)
  ##   * acceptsByTheorem == the canonical distribution (sum == 17)
  ##   * the 6-fold identity: six 64-hex fields
  ##   * the CLE identity: cleKaaDigest/cleToolchainFingerprint as 64-hex +
  ##     the canonical KAA JSON TEXT (non-empty string — its digest rides
  ##     separately as cleKaaDigest). The CLE's evidenceId is NOT a member:
  ##     it transitively binds the checkout commit (§2.1a subjectGitRef), a
  ##     run-scope digest the payload identity must never carry.
  ##   * completenessKeys == the re-derived golden keys (component ⑧ cross-check)
  ##   * executionEpoch: 64-hex
  ##   * EXACT field sets (top level, fold, cle): an extra field would change
  ##     the canonical bytes, so anything outside the canonical shape is
  ##     rejected — the payload can never grow a run-scope member back.
  if node.isNil or node.kind != JObject:
    return err("judgment_cas: judgment payload must be a JSON object (fail-closed)")
  let topError = exactFieldSet(node,
    ["schemaVersion", "verdict", "kernelAcceptCount", "probeCount",
     "acceptsByTheorem", "fold", "cle", "completenessKeys", "executionEpoch"],
    "top level")
  if topError.len > 0:
    return err(topError)
  template needStr(key: string): string =
    block:
      let v = node{key}
      if v.isNil or v.kind != JString or v.getStr().len == 0:
        return err("judgment_cas: payload field '" & key & "' missing/empty (fail-closed)")
      v.getStr()
  if needStr("schemaVersion") != JudgmentPayloadSchema:
    return err("judgment_cas: payload schemaVersion is not '" & JudgmentPayloadSchema & "' (fail-closed)")
  let verdict = needStr("verdict")
  if verdict != JudgmentVerdictAcceptAll:
    return err("judgment_cas: payload verdict '" & verdict & "' is not a reusable outcome — only " &
      JudgmentVerdictAcceptAll & " is stored or reused (timeout FAIL included, fail-closed)")
  let acceptCount = node{"kernelAcceptCount"}
  if acceptCount.isNil or acceptCount.kind != JInt or acceptCount.getInt() != CanonicalKernelAcceptCount:
    return err("judgment_cas: payload kernelAcceptCount must be " & $CanonicalKernelAcceptCount &
      " (the canonical judgment set, fail-closed)")
  let probeCount = node{"probeCount"}
  if probeCount.isNil or probeCount.kind != JInt or probeCount.getInt() != CanonicalProbeCount:
    return err("judgment_cas: payload probeCount must be " & $CanonicalProbeCount &
      " (the canonical judgment set, fail-closed)")
  let byTheorem = node{"acceptsByTheorem"}
  if byTheorem.isNil or byTheorem.kind != JObject:
    return err("judgment_cas: payload acceptsByTheorem missing/malformed (fail-closed)")
  var facts = JudgmentAcceptFacts(unknownTheorems: @[])
  var total = 0
  for i, thm in CanonicalTheoremIdentities:
    let v = byTheorem{thm}
    if v.isNil or v.kind != JInt:
      return err("judgment_cas: payload acceptsByTheorem." & thm & " missing/not an int (fail-closed)")
    facts.acceptsByTheorem[i] = v.getInt()
    total += v.getInt()
  if total != CanonicalKernelAcceptCount:
    return err("judgment_cas: payload acceptsByTheorem sum " & $total & " != " &
      $CanonicalKernelAcceptCount & " (fail-closed)")
  for thm, v in byTheorem.pairs:
    var canonical = false
    for c in CanonicalTheoremIdentities:
      if thm == c: canonical = true; break
    if not canonical:
      return err("judgment_cas: payload acceptsByTheorem carries non-canonical theorem '" &
        thm & "' (fail-closed)")
  let fold = node{"fold"}
  if fold.isNil or fold.kind != JObject:
    return err("judgment_cas: payload fold missing (fail-closed)")
  let foldError = exactFieldSet(fold,
    ["inputHash", "irHash", "obligationHash", "leanSourceHash", "kaaIdentity",
     "artifactIdentity"], "fold")
  if foldError.len > 0:
    return err(foldError)
  template needHex(container: JsonNode; key: string): string =
    block:
      let v = container{key}
      if v.isNil or v.kind != JString or not isHexOfLen(v.getStr(), 64):
        return err("judgment_cas: payload field '" & key & "' must be 64 lowercase hex chars (fail-closed)")
      v.getStr()
  template needStrIn(container: JsonNode; key: string): string =
    block:
      let v = container{key}
      if v.isNil or v.kind != JString or v.getStr().len == 0:
        return err("judgment_cas: payload field '" & key & "' must be a non-empty string (fail-closed)")
      v.getStr()
  let cleError = exactFieldSet(node{"cle"},
    ["cleKaaDigest", "cleCanonicalKaaJson", "cleToolchainFingerprint"], "cle")
  if cleError.len > 0:
    return err(cleError)
  let measured = JudgmentMeasuredEvidence(
    kernelAcceptCount: CanonicalKernelAcceptCount,
    probeCount: CanonicalProbeCount,
    facts: facts,
    fold: JudgmentFoldIdentity(
      inputHash: needHex(fold, "inputHash"),
      irHash: needHex(fold, "irHash"),
      obligationHash: needHex(fold, "obligationHash"),
      leanSourceHash: needHex(fold, "leanSourceHash"),
      kaaIdentity: needHex(fold, "kaaIdentity"),
      artifactIdentity: needHex(fold, "artifactIdentity")),
    cle: JudgmentCleIdentity(
      cleKaaDigest: needHex(node{"cle"}, "cleKaaDigest"),
      cleCanonicalKaaJson: needStrIn(node{"cle"}, "cleCanonicalKaaJson"),
      cleToolchainFingerprint: needHex(node{"cle"}, "cleToolchainFingerprint")))
  let keysNode = node{"completenessKeys"}
  if keysNode.isNil or keysNode.kind != JArray or keysNode.len != 4:
    return err("judgment_cas: payload completenessKeys must be the 4-key array (fail-closed)")
  var keys: array[4, string]
  for i in 0 ..< 4:
    let v = keysNode[i]
    if v.isNil or v.kind != JString or not isHexOfLen(v.getStr(), 64):
      return err("judgment_cas: payload completenessKeys[" & $i & "] must be 64 lowercase hex chars (fail-closed)")
    keys[i] = v.getStr()
  if keys != goldenCompletenessKeys():
    return err("judgment_cas: payload completenessKeys diverge from the re-derived golden keys (component ⑧ cross-check, fail-closed)")
  discard needHex(node, "executionEpoch")
  ok(measured)

func validateProofIntegrityPayloadNode*(node: JsonNode): Result[int, string] {.
    raises: [].} =
  ## Strict validation of a proof-integrity judgment projection — the PURE
  ## PREDICATE set (kernel 0 runs). Fail-closed on every contract:
  ##   * schemaVersion == ProofIntegrityPayloadSchema
  ##   * verdict == JudgmentVerdictPredicatePassAll
  ##   * kernelRunCount == 0 (the subject runs no kernel)
  ##   * checkpointCount == ProofIntegrityCheckpointCount
  ##   * checkpointVerdicts == the canonical name→verdict map, exact set,
  ##     exact values (a deviating predicate observation is a FAILED test —
  ##     it can never be a reusable judgment)
  ##   * executionEpoch: 64-hex
  ##   * EXACT top-level field set (an extra field would change the canonical
  ##     bytes — fail-closed)
  if node.isNil or node.kind != JObject:
    return err("judgment_cas: judgment payload must be a JSON object (fail-closed)")
  let topError = exactFieldSet(node,
    ["schemaVersion", "verdict", "kernelRunCount", "checkpointCount",
     "checkpointVerdicts", "executionEpoch"], "top level")
  if topError.len > 0:
    return err(topError)
  template needStr(key: string): string =
    block:
      let v = node{key}
      if v.isNil or v.kind != JString or v.getStr().len == 0:
        return err("judgment_cas: payload field '" & key & "' missing/empty (fail-closed)")
      v.getStr()
  if needStr("schemaVersion") != ProofIntegrityPayloadSchema:
    return err("judgment_cas: payload schemaVersion is not '" &
      ProofIntegrityPayloadSchema & "' (fail-closed)")
  let verdict = needStr("verdict")
  if verdict != JudgmentVerdictPredicatePassAll:
    return err("judgment_cas: payload verdict '" & verdict & "' is not a reusable outcome — only " &
      JudgmentVerdictPredicatePassAll & " is stored or reused (fail-closed)")
  let runs = node{"kernelRunCount"}
  if runs.isNil or runs.kind != JInt or runs.getInt() != 0:
    return err("judgment_cas: payload kernelRunCount must be 0 (the pure predicate judgment, fail-closed)")
  let count = node{"checkpointCount"}
  if count.isNil or count.kind != JInt or count.getInt() != ProofIntegrityCheckpointCount:
    return err("judgment_cas: payload checkpointCount must be " & $ProofIntegrityCheckpointCount &
      " (the canonical predicate set, fail-closed)")
  let verdicts = node{"checkpointVerdicts"}
  if verdicts.isNil or verdicts.kind != JObject:
    return err("judgment_cas: payload checkpointVerdicts missing/malformed (fail-closed)")
  for i, name in CanonicalProofIntegrityCheckpoints:
    let v = verdicts{name}
    if v.isNil or v.kind != JString:
      return err("judgment_cas: payload checkpointVerdicts." & name & " missing (fail-closed)")
    if v.getStr() != CanonicalProofIntegrityVerdicts[i]:
      return err("judgment_cas: payload checkpointVerdicts." & name & "='" & v.getStr() &
        "' deviates from the canonical predicate verdict '" &
        CanonicalProofIntegrityVerdicts[i] & "' (fail-closed)")
  if verdicts.len != CanonicalProofIntegrityCheckpoints.len:
    return err("judgment_cas: payload checkpointVerdicts carries a non-canonical checkpoint (fail-closed)")
  discard needStr("executionEpoch")
  ok(ProofIntegrityCheckpointCount)

func validateD2GoldenPayloadNode*(node: JsonNode): Result[int, string] {.
    raises: [].} =
  ## Strict validation of a d2_golden judgment projection — kernel 14 runs,
  ## the receipt identity 4 + the 5-fold C1 identity chain. Fail-closed:
  ## schema/verdict/counts exact, theoremIdentity exact, every identity
  ## field 64-hex, executionEpoch 64-hex, EXACT field sets (top level,
  ## receipt, identityChain — an extra field would change the canonical
  ## bytes, fail-closed).
  if node.isNil or node.kind != JObject:
    return err("judgment_cas: judgment payload must be a JSON object (fail-closed)")
  let topError = exactFieldSet(node,
    ["schemaVersion", "verdict", "kernelRunCount", "theoremIdentity",
     "receipt", "identityChain", "executionEpoch"], "top level")
  if topError.len > 0:
    return err(topError)
  template needStr(key: string): string =
    block:
      let v = node{key}
      if v.isNil or v.kind != JString or v.getStr().len == 0:
        return err("judgment_cas: payload field '" & key & "' missing/empty (fail-closed)")
      v.getStr()
  if needStr("schemaVersion") != D2GoldenPayloadSchema:
    return err("judgment_cas: payload schemaVersion is not '" &
      D2GoldenPayloadSchema & "' (fail-closed)")
  let verdict = needStr("verdict")
  if verdict != JudgmentVerdictAcceptAll:
    return err("judgment_cas: payload verdict '" & verdict & "' is not a reusable outcome — only " &
      JudgmentVerdictAcceptAll & " is stored or reused (timeout FAIL included, fail-closed)")
  let runs = node{"kernelRunCount"}
  if runs.isNil or runs.kind != JInt or runs.getInt() != D2GoldenKernelRunCount:
    return err("judgment_cas: payload kernelRunCount must be " & $D2GoldenKernelRunCount &
      " (the canonical d2_golden judgment set, fail-closed)")
  if needStr("theoremIdentity") != D2GoldenTheoremIdentity:
    return err("judgment_cas: payload theoremIdentity must be '" &
      D2GoldenTheoremIdentity & "' (fail-closed)")
  template needHexIn(container: JsonNode; key: string): string =
    block:
      let v = container{key}
      if v.isNil or v.kind != JString or not isHexOfLen(v.getStr(), 64):
        return err("judgment_cas: payload field '" & key & "' must be 64 lowercase hex chars (fail-closed)")
      v.getStr()
  let receipt = node{"receipt"}
  if receipt.isNil or receipt.kind != JObject:
    return err("judgment_cas: payload receipt missing (fail-closed)")
  let receiptError = exactFieldSet(receipt,
    ["executableDigest", "inputIdentity", "artifactIdentity",
     "toolchainFingerprint"], "receipt")
  if receiptError.len > 0:
    return err(receiptError)
  for f in ["executableDigest", "inputIdentity", "artifactIdentity", "toolchainFingerprint"]:
    discard needHexIn(receipt, f)
  let chain = node{"identityChain"}
  if chain.isNil or chain.kind != JObject:
    return err("judgment_cas: payload identityChain missing (fail-closed)")
  let chainError = exactFieldSet(chain,
    ["artifact", "execution", "kaa", "decision", "result"], "identityChain")
  if chainError.len > 0:
    return err(chainError)
  for f in ["artifact", "execution", "kaa", "decision", "result"]:
    discard needHexIn(chain, f)
  discard needStr("executionEpoch")
  ok(D2GoldenKernelRunCount)

func validateD2PersistPayloadNode*(node: JsonNode): Result[int, string] {.
    raises: [].} =
  ## Strict validation of a d2_persist judgment projection — the persistence
  ## LOOP judgment (kernel 1 run + the writer→reader round-trip). Fail-closed:
  ## schema/verdict/counts exact, irHash 64-hex, every canonical loop
  ## checkpoint present and true, executionEpoch 64-hex, EXACT top-level
  ## field set (an extra field would change the canonical bytes, fail-closed).
  if node.isNil or node.kind != JObject:
    return err("judgment_cas: judgment payload must be a JSON object (fail-closed)")
  let topError = exactFieldSet(node,
    ["schemaVersion", "verdict", "kernelRunCount", "theoremIdentity",
     "irHash", "loopCheckpoints", "executionEpoch"], "top level")
  if topError.len > 0:
    return err(topError)
  template needStr(key: string): string =
    block:
      let v = node{key}
      if v.isNil or v.kind != JString or v.getStr().len == 0:
        return err("judgment_cas: payload field '" & key & "' missing/empty (fail-closed)")
      v.getStr()
  if needStr("schemaVersion") != D2PersistPayloadSchema:
    return err("judgment_cas: payload schemaVersion is not '" &
      D2PersistPayloadSchema & "' (fail-closed)")
  let verdict = needStr("verdict")
  if verdict != JudgmentVerdictPersistLoopVerified:
    return err("judgment_cas: payload verdict '" & verdict & "' is not a reusable outcome — only " &
      JudgmentVerdictPersistLoopVerified & " is stored or reused (fail-closed)")
  let runs = node{"kernelRunCount"}
  if runs.isNil or runs.kind != JInt or runs.getInt() != D2PersistKernelRunCount:
    return err("judgment_cas: payload kernelRunCount must be " & $D2PersistKernelRunCount &
      " (the canonical d2_persist judgment set, fail-closed)")
  if needStr("theoremIdentity") != D2GoldenTheoremIdentity:
    return err("judgment_cas: payload theoremIdentity must be '" &
      D2GoldenTheoremIdentity & "' (fail-closed)")
  let irHash = node{"irHash"}
  if irHash.isNil or irHash.kind != JString or not isHexOfLen(irHash.getStr(), 64):
    return err("judgment_cas: payload irHash must be 64 lowercase hex chars (fail-closed)")
  let loops = node{"loopCheckpoints"}
  if loops.isNil or loops.kind != JObject:
    return err("judgment_cas: payload loopCheckpoints missing/malformed (fail-closed)")
  for name in CanonicalD2PersistLoopCheckpoints:
    let v = loops{name}
    if v.isNil or v.kind != JBool or not v.getBool():
      return err("judgment_cas: payload loopCheckpoints." & name &
        " missing/false — an unverified loop checkpoint is never a reusable judgment (fail-closed)")
  if loops.len != CanonicalD2PersistLoopCheckpoints.len:
    return err("judgment_cas: payload loopCheckpoints carries a non-canonical checkpoint (fail-closed)")
  discard needStr("executionEpoch")
  ok(D2PersistKernelRunCount)

func validateJudgmentPayloadNode*(node: JsonNode): Result[JudgmentMeasuredEvidence, string] {.
    raises: [].} =
  ## The judgment projection validator DISPATCH — by the payload's own
  ## schemaVersion (each subject owns its evidence minimal set; the s1a
  ## schema keeps its landed shape). An unknown schema is corrupt (fail-closed).
  ## The s1a return type is retained (the only subject with a structured
  ## projection); the extension subjects validate to their canonical counts.
  if node.isNil or node.kind != JObject:
    return err("judgment_cas: judgment payload must be a JSON object (fail-closed)")
  let sv = node{"schemaVersion"}
  if sv.isNil or sv.kind != JString or sv.getStr().len == 0:
    return err("judgment_cas: payload field 'schemaVersion' missing/empty (fail-closed)")
  case sv.getStr()
  of JudgmentPayloadSchema:
    validateS1aJudgmentPayloadNode(node)
  of ProofIntegrityPayloadSchema:
    let r = validateProofIntegrityPayloadNode(node)
    if r.isErr: return err(r.error)
    var empty = JudgmentMeasuredEvidence()
    empty.kernelAcceptCount = 0
    empty.probeCount = r.get
    ok(empty)
  of D2GoldenPayloadSchema:
    let r = validateD2GoldenPayloadNode(node)
    if r.isErr: return err(r.error)
    var empty = JudgmentMeasuredEvidence()
    empty.kernelAcceptCount = r.get
    empty.probeCount = 0
    ok(empty)
  of D2PersistPayloadSchema:
    let r = validateD2PersistPayloadNode(node)
    if r.isErr: return err(r.error)
    var empty = JudgmentMeasuredEvidence()
    empty.kernelAcceptCount = r.get
    empty.probeCount = 0
    ok(empty)
  else:
    return err("judgment_cas: payload schemaVersion '" & sv.getStr() &
      "' is not a known judgment payload schema (fail-closed)")

# ---------------------------------------------------------------------------
# Test-boundary emission — the flush the s1a golden test performs
# ---------------------------------------------------------------------------

proc writeJudgmentEvidenceFile*(e: JudgmentMeasuredEvidence): Result[string, string] {.
  raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Flush the measured judgment evidence to the env-armed path (the s1a
  ## golden test calls this once, after its suites). Fail-closed: unarmed →
  ## err (the caller skips), non-canonical counts → err (the golden contract
  ## canary), unwritable path → err. The file bytes are the canonical
  ## projection wire (schema + verdict + minimal set + execution epoch), so
  ## record build re-uses them verbatim.
  let path = getEnv("AXIOM_JUDGMENT_CAS_EVIDENCE_PATH", "")
  if path.len == 0:
    return err("judgment_cas: evidence path not armed (caller must check judgmentRecordingArmed())")
  if e.kernelAcceptCount != CanonicalKernelAcceptCount or e.probeCount != CanonicalProbeCount:
    return err("judgment_cas: measured counts (" & $e.kernelAcceptCount & "/" & $e.probeCount &
      ") are not the canonical judgment set (" & $CanonicalKernelAcceptCount & "/" &
      $CanonicalProbeCount & ") — the golden judgment contract requires revision in the same change (fail-closed)")
  if e.facts.unknownTheorems.len > 0:
    return err("judgment_cas: observed kernel ACCEPTs outside the canonical theorem set (fail-closed)")
  let epoch = captureReuseVerificationContext().currentEpoch
  let wire = judgmentEvidenceWire(e, goldenCompletenessKeys(), epoch)
  try:
    writeFile(path, wire)
  except CatchableError as exc:
    return err("judgment_cas: evidence write failed (fail-closed): " & path & ": " & exc.msg)
  ok(wire)

proc parseJudgmentEvidenceFile*(path: string): Result[string, string] {.
  raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Read + validate the test's evidence file, returning the canonical
  ## payload bytes. Absent/unparsable/contract-violating → err (fail-closed:
  ## an EXECUTED basis without a measurable judgment never produces a
  ## record).
  if not fileExists(path):
    return err("judgment_cas: judgment evidence file not found (fail-closed): " & path)
  let text =
    try: readFile(path)
    except CatchableError as exc:
      return err("judgment_cas: judgment evidence file unreadable (fail-closed): " & exc.msg)
  if text.len == 0:
    return err("judgment_cas: judgment evidence file is empty (fail-closed)")
  var node: JsonNode
  try:
    node = parseJson(text)
  except CatchableError as exc:
    return err("judgment_cas: judgment evidence file is not valid JSON: " & exc.msg)
  let measured = validateJudgmentPayloadNode(node)
  if measured.isErr:
    return err(measured.error)
  ok(canonicalJsonString(node))

# ---------------------------------------------------------------------------
# Extension subjects — the per-test judgment evidence (flush + wire)
# ---------------------------------------------------------------------------

type
  ProofIntegrityJudgmentEvidence* = object
    ## The observed predicate verdicts, aligned with
    ## CanonicalProofIntegrityCheckpoints (the flush validates the set).
    checkpointVerdicts*: array[ProofIntegrityCheckpointCount, string]

  D2GoldenJudgmentEvidence* = object
    ## The judged canonical execution's receipt identity 4 + 5-fold C1 chain
    ## (all run-invariant; receiptObservedAt provenance is excluded).
    receiptExecutableDigest*: string
    receiptInputIdentity*: string
    receiptArtifactIdentity*: string
    receiptToolchainFingerprint*: string
    chainArtifact*: string
    chainExecution*: string
    chainKaa*: string
    chainDecision*: string
    chainResult*: string

  D2PersistJudgmentEvidence* = object
    ## The persistence-loop judgment: the persisted cert's irHash + the
    ## writer→reader checkpoint results, aligned with
    ## CanonicalD2PersistLoopCheckpoints.
    irHash*: string
    loopCheckpoints*: array[CanonicalD2PersistLoopCheckpoints.len, bool]

func proofIntegrityEvidenceWire*(e: ProofIntegrityJudgmentEvidence;
    executionEpoch: string): string {.raises: [].} =
  ## The canonical proof-integrity projection (schema + verdict + the
  ## canonical checkpoint verdict set + execution epoch). Provenance excluded.
  var checkpointNode = newJObject()
  for i, name in CanonicalProofIntegrityCheckpoints:
    checkpointNode[name] = %e.checkpointVerdicts[i]
  canonicalJsonString(%*{
    "schemaVersion": ProofIntegrityPayloadSchema,
    "verdict": JudgmentVerdictPredicatePassAll,
    "kernelRunCount": 0,
    "checkpointCount": ProofIntegrityCheckpointCount,
    "checkpointVerdicts": checkpointNode,
    "executionEpoch": executionEpoch})

func d2GoldenEvidenceWire*(e: D2GoldenJudgmentEvidence;
    kernelRunCount: int; executionEpoch: string): string {.raises: [].} =
  ## The canonical d2_golden projection.
  canonicalJsonString(%*{
    "schemaVersion": D2GoldenPayloadSchema,
    "verdict": JudgmentVerdictAcceptAll,
    "kernelRunCount": kernelRunCount,
    "theoremIdentity": D2GoldenTheoremIdentity,
    "receipt": {
      "executableDigest": e.receiptExecutableDigest,
      "inputIdentity": e.receiptInputIdentity,
      "artifactIdentity": e.receiptArtifactIdentity,
      "toolchainFingerprint": e.receiptToolchainFingerprint},
    "identityChain": {
      "artifact": e.chainArtifact,
      "execution": e.chainExecution,
      "kaa": e.chainKaa,
      "decision": e.chainDecision,
      "result": e.chainResult},
    "executionEpoch": executionEpoch})

func d2PersistEvidenceWire*(e: D2PersistJudgmentEvidence;
    kernelRunCount: int; executionEpoch: string): string {.raises: [].} =
  ## The canonical d2_persist projection.
  var loopNode = newJObject()
  for i, name in CanonicalD2PersistLoopCheckpoints:
    loopNode[name] = %e.loopCheckpoints[i]
  canonicalJsonString(%*{
    "schemaVersion": D2PersistPayloadSchema,
    "verdict": JudgmentVerdictPersistLoopVerified,
    "kernelRunCount": kernelRunCount,
    "theoremIdentity": D2GoldenTheoremIdentity,
    "irHash": e.irHash,
    "loopCheckpoints": loopNode,
    "executionEpoch": executionEpoch})

proc writeSubjectEvidenceFile*(schemaVersion: string; wire: string): Result[string, string] {.
  raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Shared flush I/O: resolve the subject's armed evidence path, write the
  ## canonical wire. Fail-closed: unarmed → err (the caller skips), unwritable
  ## → err. The attest stage re-parses these bytes verbatim into the record.
  var path = ""
  for s in allJudgmentSubjects():
    if subjectPayloadSchema(s) == schemaVersion:
      path = getEnv(subjectEvidencePathEnv(s), "")
      break
  if path.len == 0:
    return err("judgment_cas: evidence path not armed for schema '" & schemaVersion &
      "' (caller must check the subject's armed state)")
  try:
    writeFile(path, wire)
  except CatchableError as exc:
    return err("judgment_cas: evidence write failed (fail-closed): " & path & ": " & exc.msg)
  ok(wire)

proc writeProofIntegrityJudgmentEvidenceFile*(e: ProofIntegrityJudgmentEvidence): Result[string, string] {.
  raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Flush the measured proof-integrity judgment evidence. Fail-closed: a
  ## checkpoint observation deviating from the canonical predicate verdict is
  ## a FAILED test — the golden-contract canary refuses to stage it.
  for i, name in CanonicalProofIntegrityCheckpoints:
    if e.checkpointVerdicts[i] != CanonicalProofIntegrityVerdicts[i]:
      return err("judgment_cas: measured checkpoint '" & name & "'='" &
        e.checkpointVerdicts[i] & "' deviates from the canonical predicate verdict '" &
        CanonicalProofIntegrityVerdicts[i] & "' — a deviating predicate observation is " &
        "never a reusable judgment (fail-closed)")
  let epoch = captureReuseVerificationContext().currentEpoch
  let wire = proofIntegrityEvidenceWire(e, epoch)
  writeSubjectEvidenceFile(ProofIntegrityPayloadSchema, wire)

proc writeD2GoldenJudgmentEvidenceFile*(e: D2GoldenJudgmentEvidence;
    observedKernelRunCount: int): Result[string, string] {.
  raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Flush the measured d2_golden judgment evidence. Fail-closed canary: a
  ## run whose kernel-execution count is not the canonical 14 produces no
  ## record (the golden judgment contract requires revision in the same change).
  if observedKernelRunCount != D2GoldenKernelRunCount:
    return err("judgment_cas: measured kernelRunCount (" & $observedKernelRunCount &
      ") is not the canonical d2_golden set (" & $D2GoldenKernelRunCount & ") — the golden " &
      "judgment contract requires revision in the same change (fail-closed)")
  for f in [e.receiptExecutableDigest, e.receiptInputIdentity,
            e.receiptArtifactIdentity, e.receiptToolchainFingerprint,
            e.chainArtifact, e.chainExecution, e.chainKaa,
            e.chainDecision, e.chainResult]:
    if not isHexOfLen(f, 64):
      return err("judgment_cas: measured d2_golden identity field is not 64 hex (fail-closed)")
  let epoch = captureReuseVerificationContext().currentEpoch
  let wire = d2GoldenEvidenceWire(e, observedKernelRunCount, epoch)
  writeSubjectEvidenceFile(D2GoldenPayloadSchema, wire)

proc writeD2PersistJudgmentEvidenceFile*(e: D2PersistJudgmentEvidence;
    observedKernelRunCount: int): Result[string, string] {.
  raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Flush the measured d2_persist judgment evidence. Fail-closed canary: a
  ## loop checkpoint that did not pass (or a non-canonical kernel count)
  ## stages no record.
  if observedKernelRunCount != D2PersistKernelRunCount:
    return err("judgment_cas: measured kernelRunCount (" & $observedKernelRunCount &
      ") is not the canonical d2_persist set (" & $D2PersistKernelRunCount & ") — the loop " &
      "judgment contract requires revision in the same change (fail-closed)")
  if not isHexOfLen(e.irHash, 64):
    return err("judgment_cas: measured d2_persist irHash is not 64 hex (fail-closed)")
  for i, name in CanonicalD2PersistLoopCheckpoints:
    if not e.loopCheckpoints[i]:
      return err("judgment_cas: measured loop checkpoint '" & name &
        "' did not pass — an unverified loop checkpoint is never a reusable judgment (fail-closed)")
  let epoch = captureReuseVerificationContext().currentEpoch
  let wire = d2PersistEvidenceWire(e, observedKernelRunCount, epoch)
  writeSubjectEvidenceFile(D2PersistPayloadSchema, wire)

# ---------------------------------------------------------------------------
# Plan — the reuse decision (read-only ledger consult)
# ---------------------------------------------------------------------------

type
  JudgmentPlanMode* = enum
    jOff       ## env unset/"0" — unarmed legacy state, zero behavior change
    jReused    ## ledger record fully re-verified — the sanctioned skip
    jExecuted  ## no verifiable record — the original s1a execution must run

  JudgmentPlan* = object
    mode*: JudgmentPlanMode
    reason*: string            ## the honest why (populated on every mode)
    evidenceKey*: string       ## 64-hex key (empty on jOff)
    recordPath*: string        ## where the attest stage emits the record file
    repo*: string              ## ledger repo (resolved)
    refName*: string           ## ledger side ref
    subject*: string = ""      ## the plan's subject name ("" = the s1a legacy wire)
    probeTreeOid*: string = "" ## the b-probe-tree anchor this plan derived from
                               ## (out-of-key; decision-file provenance — p3.
                               ## Empty on jOff and on pre-validation fallbacks)
    landingVenue*: string = "" ## JudgmentMergeGroupEvent when this run IS the
                               ## landing venue (marker only — never a consult
                               ## block; decision-file provenance, out-of-key.
                               ## Empty on every non-landing venue)
    rootEvidenceKey*: string = ""    ## jReused: the root ledger record's key
                                     ## (provenance marker — the root is always
                                     ## a same-generation pipeline-minted
                                     ## EXECUTED run; redecision §1.3)
    rootPayloadSha256*: string = ""  ## jReused: the root record envelope's
                                     ## payloadSha256
    rootExecutionEpoch*: string = "" ## jReused: the root EXECUTED run's
                                     ## executionEpoch (== this run's epoch —
                                     ## §5-b is verified before jReused)
    closureNotes*: seq[string] = @[] ## the closure's dependency audit trail —
                                     ## every (b)/(c)/(d) import hit (pinned
                                     ## external / build-generated /
                                     ## unresolved), recorded in the decision
                                     ## file. Never silently skipped.

func judgmentDisabled*(value: string): bool {.raises: [].} =
  ## The env-off contract: unset ("") or explicit "0" — anything else must be
  ## exactly "1" (an unexpected value fails closed later, never silently
  ## disables the reuse gate).
  value.len == 0 or value == "0"

func judgmentLandingVenueMarker*(forceEnvValue, githubEventName: string): bool {.
    raises: [].} =
  ## The landing-venue marker (redecision 2026-10-18 —
  ## docs/evidence/mg_reuse_policy_redecision_2026-10-18.md): the two triggers
  ## of the old force-execution block now only MARK this run as the merge_group
  ## landing venue — the plan consults the ledger on EVERY venue and the venue
  ## distinction travels on the decision file (`landingVenue`) for the
  ## armed-attest/yml consumers. "1" on JudgmentForceExecutionEnv (the
  ## workflow's explicit landing trigger, semantics = venue marker) OR
  ## GITHUB_EVENT_NAME equal to the merge_group landing venue (live in the
  ## admission callee, inert where the variable is unset). Both unset → not a
  ## landing venue: the PR preflight keeps the reuse pose exactly as before.
  forceEnvValue == "1" or githubEventName == JudgmentMergeGroupEvent

func planLogLine*(plan: JudgmentPlan): string {.raises: [].} =
  ## The greppable decision line (the single wire-text source; the CLI echoes
  ## it verbatim and the workflow consumes it). Extension plans name their
  ## subject so the per-test skip decision stays greppable per subject.
  let subjectTag =
    if plan.subject.len == 0 or plan.subject == "s1a": ""
    else: "[" & plan.subject & "] "
  case plan.mode
  of jOff: "AXIOM_JUDGMENT_CAS: OFF — unarmed (legacy execution path)"
  of jReused: "AXIOM_JUDGMENT_CAS" & (if subjectTag.len > 0: " " & subjectTag else: "") &
      ": REUSED — record " &
      plan.evidenceKey[0 ..< min(plan.evidenceKey.len, 12)] & " re-verified (" & plan.reason & ")"
  of jExecuted: "AXIOM_JUDGMENT_CAS" & (if subjectTag.len > 0: " " & subjectTag else: "") &
      ": EXECUTED — " & plan.reason

proc planJudgmentCasForSubjectWithTransport*(s: JudgmentSubject;
    transport: LedgerTransport): JudgmentPlan {.
  raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Resolve the judgment plan for ONE subject: env contract → fail-closed
  ## closure collection (the subject's own closure roots) → key derivation →
  ## read-only ledger consult → reuse re-verification. The transport is
  ## injectable (tests). Failure directions are asymmetric ON PURPOSE:
  ##   * workspace/env/identity collection failure → jExecuted with the
  ##     anomaly reason — the test re-runs (a cost, never a correctness loss).
  ##     A reuse claim is never made from an unmeasurable workspace.
  ##   * ledger membership read failure or a record that fails ANY reuse
  ##     condition (payload validation, completeness cross-check, epoch
  ##     match) → jExecuted — the stored fact is not provably this
  ##     computation's fact, so the original verification runs.
  let subjectTag = subjectName(s)
  let enabled = getEnv(JudgmentEnabledEnv, "")
  if judgmentDisabled(enabled):
    return JudgmentPlan(mode: jOff, reason: JudgmentEnabledEnv & " unset/0 (unarmed)",
      subject: subjectTag)
  if enabled != "1":
    return JudgmentPlan(mode: jExecuted,
      reason: JudgmentEnabledEnv & "='" & enabled & "' is not '1' (fail-closed)",
      subject: subjectTag)
  let testedTreeOid = getEnv(JudgmentTestedTreeOidEnv, "")
  if not isHexOfLen(testedTreeOid, 40):
    return JudgmentPlan(mode: jExecuted,
      reason: JudgmentTestedTreeOidEnv & " must be a 40-hex git tree OID (fail-closed)",
      subject: subjectTag)
  let recordPath = getEnv(subjectRecordPathEnv(s), "")
  if recordPath.len == 0:
    return JudgmentPlan(mode: jExecuted,
      reason: subjectRecordPathEnv(s) & " is not set — the record has no store path (fail-closed)",
      subject: subjectTag)
  var closure: JudgmentClosure
  var closureNotes: seq[string] = @[]
  try:
    let collected = collectJudgmentClosureBundle(s, testedTreeOid)
    if collected.isErr:
      return JudgmentPlan(mode: jExecuted, reason: "closure collection: " & collected.error,
        subject: subjectTag)
    closure = collected.get.closure
    closureNotes = collected.get.notes
  except CatchableError as exc:
    return JudgmentPlan(mode: jExecuted, reason: "closure collection raised: " & exc.msg,
      subject: subjectTag)
  let key = deriveJudgmentKey(closure)
  var plan = JudgmentPlan(
    mode: jExecuted,
    reason: "no verifiable record",
    evidenceKey: key,
    recordPath: recordPath,
    repo: resolveEvidenceCasRepo(),
    refName: EvidenceCasRefName,
    subject: subjectTag,
    probeTreeOid: testedTreeOid,
    closureNotes: closureNotes)
  # Landing-venue marker (redecision 2026-10-18): merge_group is RECORDED on
  # the plan — a venue marker for the decision file, never a consult block.
  # The read-only ledger consult below runs on EVERY venue: an eligible REUSED
  # is now admissible on the landing venue, and every jReused plan carries the
  # root-EXECUTED provenance marker (rootRecord) binding the re-fetched
  # record. All mismatches/UNKNOWN still fail closed to jExecuted — the
  # consult chain below is the only path to jReused.
  if judgmentLandingVenueMarker(getEnv(JudgmentForceExecutionEnv, ""),
      getEnv("GITHUB_EVENT_NAME", "")):
    plan.landingVenue = JudgmentMergeGroupEvent
  # s1a on the LANDING venue is NO LONGER special-cased (v5, the 2026-10-18
  # redecision became the contract): the s1a judgment takes the SAME
  # 5-condition reuse path as every other subject — the plan-time ledger
  # consult, the attest-side re-verification and the rootRecord provenance
  # marker. The GO lane's s1a REUSED rejection and the attest's s1a
  # EXECUTED+PASS requirement were removed in the same generation
  # (.github/workflows/admission-check.yml), so a REUSED s1a decision is
  # admissible on the landing venue under exactly the conditions §5 states.
  # Read-only ledger consult. Membership anomalies → jExecuted (the test
  # re-runs); a present record must pass EVERY reuse condition.
  let has = hasEvidence(transport, plan.repo, key, plan.refName)
  if has.isErr:
    plan.reason = "ledger membership read failed: " & has.error & " — the original " &
      subjectTag & " execution runs"
    return plan
  if not has.get:
    plan.reason = "no record for the current closure (fresh judgment)"
    return plan
  let record = fetchEvidenceRecord(transport, plan.repo, key, plan.refName)
  if record.isErr:
    plan.reason = "record fetch/verify failed: " & record.error & " — the original " &
      subjectTag & " execution runs"
    return plan
  var node: JsonNode
  try:
    node = parseJson(record.get.payload)
  except CatchableError as exc:
    plan.reason = "stored payload unparsable: " & exc.msg & " — the original " &
      subjectTag & " execution runs"
    return plan
  let measured = validateJudgmentPayloadNode(node)
  if measured.isErr:
    plan.reason = "stored payload failed the judgment contract: " & measured.error
    return plan
  let epoch = captureReuseVerificationContext().currentEpoch
  let storedEpoch = node{"executionEpoch"}
  if storedEpoch.isNil or storedEpoch.kind != JString or storedEpoch.getStr() != epoch:
    plan.reason = "executionEpoch mismatch (§15.3(e) staleness) — the original " &
      subjectTag & " execution runs"
    return plan
  plan.mode = jReused
  plan.reason = "closure re-derivation + executionEpoch + per-read re-hash all passed"
  # The root-EXECUTED provenance marker: the re-fetched record IS the root —
  # the ledger's exactly-once append guarantees every record's root is the
  # pipeline-minted EXECUTED run (redecision §1.3), and the checks above
  # verified §5 (a)(b)(c) against THESE bytes. Sealed onto the decision file
  # by writeJudgmentDecisionFile and re-verified field-by-field at the
  # armed attest (the REUSED leg) before any skip certifies.
  plan.rootEvidenceKey = record.get.evidenceKey
  plan.rootPayloadSha256 = record.get.payloadSha256
  plan.rootExecutionEpoch = storedEpoch.getStr()
  plan

proc planJudgmentCasWithTransport*(transport: LedgerTransport): JudgmentPlan {.
  raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## The s1a plan (the landed subject) — the same machine, s1a's closure.
  planJudgmentCasForSubjectWithTransport(jsS1aGolden, transport)

proc planJudgmentCasForSubject*(s: JudgmentSubject): JudgmentPlan {.
  raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Live plan for one subject — GITHUB_TOKEN fail-closed (no token = no
  ## ledger read = no reuse claim), transport = liveLedgerTransport.
  let enabled = getEnv(JudgmentEnabledEnv, "")
  if judgmentDisabled(enabled):
    return JudgmentPlan(mode: jOff, reason: JudgmentEnabledEnv & " unset/0 (unarmed)",
      subject: subjectName(s))
  let token = getEnv("GITHUB_TOKEN", "")
  if token.len == 0:
    return JudgmentPlan(mode: jExecuted,
      reason: "GITHUB_TOKEN not set — ledger read refused, the original " &
        subjectName(s) & " execution runs (fail-closed)",
      subject: subjectName(s))
  planJudgmentCasForSubjectWithTransport(s, liveLedgerTransport(token, EvidenceCasRefName))

proc planJudgmentCas*(): JudgmentPlan {.
  raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Live plan — GITHUB_TOKEN fail-closed (no token = no ledger read = no
  ## reuse claim), transport = liveLedgerTransport against EvidenceCasRefName.
  planJudgmentCasForSubject(jsS1aGolden)

# ---------------------------------------------------------------------------
# Record build + reuse verification (the attest stage's judgment branch)
# ---------------------------------------------------------------------------

func judgmentProjectionDigest*(payload: string): string {.raises: [].} =
  ## sha256 over the projection bytes — the witness binding digest (the mint
  ## compares this against the witness's recorded projectionSha256).
  sha256Hex(payload)

proc buildJudgmentRecord*(key: string; payload: string): Result[EvidenceCasRecord, string] {.
  raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## The judgment record for the emitted projection: the SAME EvidenceCasRecord
  ## envelope the landing CAS uses (payloadSha256 derived, artifact digests
  ## informational). The evidenceDigest is the judgment module's OWN single
  ## definition — judgmentProjectionDigest over the exact projection bytes
  ## (a self-contained payload: the projection is its own evidence object,
  ## ADR-0034) — computed in-process, never caller-injected. The trusted mint
  ## appends it idempotently — a REUSED rebound record (same key + same
  ## payload bytes) lands as a no-op.
  let digests = collectArtifactDigests(".")
  if digests.isErr:
    return err("judgment_cas: record artifact digests: " & digests.error)
  var digestsNode = newJObject()
  for a in digests.get:
    digestsNode[a.name] = %a.digest
  makeEvidenceRecord(key, payload, digestsNode, currentUtcTimestamp(),
    judgmentProjectionDigest(payload))

# ---------------------------------------------------------------------------
# Witness judgment binding — the .semantic.judgment node contract (SSOT)
# ---------------------------------------------------------------------------

const
  JudgmentWitnessBasisExecuted* = "EXECUTED"
    ## The basis label of a certificate whose projection came from a
    ## freshly-executed s1a judgment (the evidence file was required).
  JudgmentWitnessBasisReused* = "REUSED"
    ## The basis label of a certificate whose projection came from a stored,
    ## fully re-verified ledger record (no kernel ran in this run).

func judgmentWitnessNode*(basis, evidenceKey, projection: string): JsonNode {.
    raises: [].} =
  ## The `.semantic.judgment` witness node: which basis produced the
  ## projection, the evidence key it belongs to, and the sha256 over the
  ## EXACT projection bytes — the mint's P7c binds this digest to the ledger
  ## payload before appending. Absent entirely on the unarmed path (the
  ## witness bytes stay byte-identical to the pre-judgment-CAS format).
  %*{
    "basis": basis,
    "evidenceKey": evidenceKey,
    "projection": projection,
    "projectionSha256": judgmentProjectionDigest(projection)}

func judgmentWitnessNodeFor*(s: JudgmentSubject; basis, evidenceKey,
    projection: string): JsonNode {.raises: [].} =
  ## The subject-tagged witness node — the extension subjects carry their
  ## subject name (the mint pairs `.semantic.judgments[]` elements to their
  ## per-subject record files by it). The s1a node keeps its landed shape
  ## (no subject field — the s1a mint block is untouched).
  var node = judgmentWitnessNode(basis, evidenceKey, projection)
  if s != jsS1aGolden:
    node["subject"] = %subjectName(s)
  node

func validateJudgmentWitnessNode*(node: JsonNode): string {.raises: [].} =
  ## "" = a well-formed judgment witness binding; otherwise the rejection
  ## reason (fail-closed). Wire-shape validation only — the byte-level
  ## projection↔ledger-record binding is the mint's P7c step.
  if node.isNil or node.kind != JObject:
    return "witness: judgment binding must be a JSON object (fail-closed)"
  let basis = node{"basis"}
  if basis.isNil or basis.kind != JString or
      (basis.getStr() != JudgmentWitnessBasisExecuted and
       basis.getStr() != JudgmentWitnessBasisReused):
    return "witness: judgment basis must be '" & JudgmentWitnessBasisExecuted & "' or '" &
      JudgmentWitnessBasisReused & "' (fail-closed)"
  let key = node{"evidenceKey"}
  if key.isNil or key.kind != JString or not isHexOfLen(key.getStr(), 64):
    return "witness: judgment evidenceKey must be 64 lowercase hex (fail-closed)"
  let projection = node{"projection"}
  if projection.isNil or projection.kind != JString or projection.getStr().len == 0:
    return "witness: judgment projection must be non-empty (fail-closed)"
  let digest = node{"projectionSha256"}
  if digest.isNil or digest.kind != JString or not isHexOfLen(digest.getStr(), 64):
    return "witness: judgment projectionSha256 must be 64 lowercase hex (fail-closed)"
  if digest.getStr() != judgmentProjectionDigest(projection.getStr()):
    return "witness: judgment projectionSha256 does not bind the projection bytes (fail-closed)"
  ""

func judgmentDecisionBasis*(mode: JudgmentPlanMode): string {.raises: [].} =
  ## The decision-file basis label of a plan mode — "OFF" is honest: an
  ## unarmed plan writes its decision too (the armed attest will reject any
  ## basis that is not EXECUTED/REUSED, fail-closed).
  case mode
  of jOff: "OFF"
  of jReused: JudgmentWitnessBasisReused
  of jExecuted: JudgmentWitnessBasisExecuted

func judgmentRootRecordMarkerShape*(marker: JsonNode): string {.raises: [].} =
  ## The rootRecord provenance marker's wire shape — "" = well-formed
  ## (3 non-empty string fields; the two identity fields are 64 lowercase
  ## hex); otherwise the rejection reason (fail-closed). Pure — the attest
  ## consumes it BEFORE any ledger IO, so an unattributable REUSED decision
  ## fails without a transport.
  if marker.isNil or marker.kind != JObject:
    return "rootRecord provenance marker must be a JSON object (fail-closed)"
  for field in ["evidenceKey", "payloadSha256", "executionEpoch"]:
    let f = marker{field}
    if f.isNil or f.kind != JString or f.getStr().len == 0:
      return "rootRecord marker field '" & field &
        "' must be a non-empty string (fail-closed)"
  if not isHexOfLen(marker{"evidenceKey"}.getStr(), 64):
    return "rootRecord marker evidenceKey must be 64 lowercase hex (fail-closed)"
  if not isHexOfLen(marker{"payloadSha256"}.getStr(), 64):
    return "rootRecord marker payloadSha256 must be 64 lowercase hex (fail-closed)"
  ""

func judgmentRootRecordMarkerMismatch*(marker: JsonNode; record: EvidenceCasRecord;
    payloadNode: JsonNode): string {.raises: [].} =
  ## The binding check: "" = the decision's marker names EXACTLY the
  ## re-fetched record (its key, its envelope payloadSha256, and the payload's
  ## executionEpoch — the root EXECUTED run this skip re-adopts); otherwise
  ## the mismatch reason (fail-closed — a marker naming a different root is
  ## not this record's provenance, and a reuse of a reuse has no root to
  ## name: the ledger's exactly-once append makes such an entry
  ## unrepresentable, redecision §1.3).
  let shape = judgmentRootRecordMarkerShape(marker)
  if shape.len > 0:
    return shape
  if marker{"evidenceKey"}.getStr() != record.evidenceKey:
    return "rootRecord marker evidenceKey " &
      marker{"evidenceKey"}.getStr()[0 ..< min(marker{"evidenceKey"}.getStr().len, 12)] &
      " != re-fetched record key " & record.evidenceKey[0 ..< 12] &
      " (provenance mismatch, fail-closed)"
  if marker{"payloadSha256"}.getStr() != record.payloadSha256:
    return "rootRecord marker payloadSha256 != re-fetched record payloadSha256 " &
      "(provenance mismatch, fail-closed)"
  let storedEpoch = payloadNode{"executionEpoch"}
  if storedEpoch.isNil or storedEpoch.kind != JString or
      marker{"executionEpoch"}.getStr() != storedEpoch.getStr():
    return "rootRecord marker executionEpoch != re-fetched record executionEpoch " &
      "(provenance mismatch, fail-closed)"
  ""

proc writeJudgmentDecisionFile*(plan: JudgmentPlan; path: string): Result[string, string] {.
  raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Write the plan stage's decision file ({basis, evidenceKey, reason}) —
  ## the attest stage's sole judgment input. Canonical JSON bytes. Extension
  ## subjects add their subject name (the s1a decision keeps its landed
  ## byte shape — absence means s1a). A landing-venue plan records
  ## `landingVenue` (marker — redecision 2026-10-18); a REUSED plan seals the
  ## `rootRecord` provenance marker {evidenceKey, payloadSha256,
  ## executionEpoch} naming the root ledger record it re-adopts — the armed
  ## attest re-verifies all three fields against the re-fetched record
  ## before the skip certifies.
  var wireNode = %*{
    "basis": judgmentDecisionBasis(plan.mode),
    "evidenceKey": plan.evidenceKey,
    "reason": plan.reason}
  if plan.subject.len > 0 and plan.subject != "s1a":
    wireNode["subject"] = %plan.subject
  if plan.probeTreeOid.len > 0:
    wireNode["probeTreeOid"] = %plan.probeTreeOid
  if plan.landingVenue.len > 0:
    wireNode["landingVenue"] = %plan.landingVenue
  if plan.mode == jReused:
    wireNode["rootRecord"] = %*{
      "evidenceKey": plan.rootEvidenceKey,
      "payloadSha256": plan.rootPayloadSha256,
      "executionEpoch": plan.rootExecutionEpoch}
  # The closure's dependency audit trail (v5) — every (b)/(c)/(d) import hit
  # is recorded: a pinned external dependency, a build-generated module and
  # an unresolved/unpinned import. A "skipped unpinned dependency" is never
  # silent — and a (d) hit never reaches this file: it makes the closure
  # non-reusable, so the plan is EXECUTED (the reason names the hit).
  if plan.closureNotes.len > 0:
    var notesNode = newJArray()
    for n in plan.closureNotes:
      notesNode.add(%n)
    wireNode["closureNotes"] = notesNode
  let wire = canonicalJsonString(wireNode)
  try:
    writeFile(path, wire)
  except CatchableError as exc:
    return err("judgment_cas: decision file write failed: " & path & ": " & exc.msg)
  ok(wire)

type
  JudgmentReuseCheck* = object
    ok*: bool
    reason*: string
    payload*: string   ## the re-verified projection bytes (witness projection source)

proc verifyJudgmentReuse*(record: EvidenceCasRecord; requestedKey: string): JudgmentReuseCheck {.
  raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## The full reuse re-verification at the attest stage (independent of the
  ## plan's read — per-read re-hash already happened in fetchEvidenceRecord):
  ##   1. the record's key binds the requested (freshly derived) key,
  ##   2. the payload passes the full judgment contract,
  ##   3. the completeness keys equal the CURRENTLY re-derived ones,
  ##   4. the execution epoch equals the CURRENT one (§15.3(e)).
  ## Any failure → not reusable (the caller executes the original s1a or
  ## fails closed — never a guessed reuse).
  if record.evidenceKey != requestedKey:
    return JudgmentReuseCheck(ok: false,
      reason: "ledger record key " & record.evidenceKey[0 ..< 12] & " != requested " &
        requestedKey[0 ..< 12] & " (closure re-derivation mismatch, fail-closed)")
  var node: JsonNode
  try:
    node = parseJson(record.payload)
  except CatchableError as exc:
    return JudgmentReuseCheck(ok: false, reason: "stored payload unparsable: " & exc.msg)
  let measured = validateJudgmentPayloadNode(node)
  if measured.isErr:
    return JudgmentReuseCheck(ok: false, reason: measured.error)
  let epoch = captureReuseVerificationContext().currentEpoch
  let storedEpoch = node{"executionEpoch"}
  if storedEpoch.isNil or storedEpoch.kind != JString or storedEpoch.getStr() != epoch:
    return JudgmentReuseCheck(ok: false,
      reason: "executionEpoch mismatch (§15.3(e) staleness) — the original s1a execution runs")
  JudgmentReuseCheck(ok: true, reason: "reuse re-verified", payload: record.payload)

# ---------------------------------------------------------------------------
# Attest-stage judgment branch (ax cert attest --witness-only)
# ---------------------------------------------------------------------------

type JudgmentAttestOutcome* = object
  armed*: bool            ## false = the judgment CAS is OFF (legacy witness bytes)
  basis*: string          ## EXECUTED | REUSED (armed runs)
  evidenceKey*: string    ## the freshly re-derived key the record binds
  reason*: string         ## the honest why (from the plan's decision file)
  node*: JsonNode         ## the witness judgment binding (armed runs)
  recordPath*: string     ## where the record file was (re)published
  subject*: string = ""   ## the branch's subject name ("" = s1a legacy)
  rootEvidenceKey*: string = "" ## REUSED: the decision's rootRecord key (the
                                ## root EXECUTED run this skip re-adopts)

proc runJudgmentAttestBranchForSubject*(s: JudgmentSubject): Result[JudgmentAttestOutcome, string] {.
  raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## The attest stage's judgment branch for ONE subject (runWitnessOnlyCli).
  ## Consumes the subject's plan-stage decision file and produces the
  ## witness's judgment binding + the record file the trusted mint appends:
  ##
  ##   * unarmed (env unset/0) → armed=false, ZERO extra behavior (legacy wire).
  ##   * EXECUTED → the test's evidence file is REQUIRED (absent/unparsable =
  ##     fail-closed — an execution without its measured judgment never
  ##     certifies), a fresh local record is built from its bytes.
  ##   * REUSED → the ledger record is re-fetched and FULLY re-verified
  ##     (verifyJudgmentReuse); any failure fails the run — the test step was
  ##     skipped, so an unverifiable reuse can never certify (fail-closed).
  ##
  ## The evidence key is re-derived HERE from the current workspace closure —
  ## the decision file's key is cross-checked, never trusted. The decision
  ## file's optional subject field (absent = s1a) must name THIS subject.
  let subjectTag = subjectName(s)
  let enabled = getEnv(JudgmentEnabledEnv, "")
  if judgmentDisabled(enabled):
    return ok(JudgmentAttestOutcome(armed: false))
  if enabled != "1":
    return err("judgment_cas: " & JudgmentEnabledEnv & "='" & enabled &
      "' is not '1' — an armed attest requires exactly 1 (fail-closed)")
  let decisionPathEnv = subjectDecisionPathEnv(s)
  let decisionPath = getEnv(decisionPathEnv, "")
  if decisionPath.len == 0:
    return err("judgment_cas: " & decisionPathEnv &
      " not set — an armed attest requires the plan stage's decision file (fail-closed)")
  if not fileExists(decisionPath):
    return err("judgment_cas: decision file not found (fail-closed): " & decisionPath)
  var decision: JsonNode
  try:
    decision = parseJson(readFile(decisionPath))
  except CatchableError as exc:
    return err("judgment_cas: decision file unparsable (fail-closed): " & exc.msg)
  if decision.isNil or decision.kind != JObject:
    return err("judgment_cas: decision file must be a JSON object (fail-closed)")
  let decisionSubjectNode = decision{"subject"}
  let decisionSubject =
    if decisionSubjectNode.isNil or decisionSubjectNode.kind != JString or
        decisionSubjectNode.getStr().len == 0: "s1a" else: decisionSubjectNode.getStr()
  if decisionSubject != subjectTag:
    return err("judgment_cas: decision file subject '" & decisionSubject &
      "' != branch subject '" & subjectTag & "' (fail-closed)")
  let basisNode = decision{"basis"}
  if basisNode.isNil or basisNode.kind != JString:
    return err("judgment_cas: decision basis missing (fail-closed)")
  let basis = basisNode.getStr()
  let reasonNode = decision{"reason"}
  let reason = if reasonNode.isNil or reasonNode.kind != JString: "" else: reasonNode.getStr()
  if basis != JudgmentWitnessBasisExecuted and basis != JudgmentWitnessBasisReused:
    return err("judgment_cas: decision basis '" & basis & "' is not '" &
      JudgmentWitnessBasisExecuted & "'/'" & JudgmentWitnessBasisReused & "' (fail-closed)")
  let testedTreeOid = getEnv(JudgmentTestedTreeOidEnv, "")
  if not isHexOfLen(testedTreeOid, 40):
    return err("judgment_cas: armed attest requires " & JudgmentTestedTreeOidEnv &
      " as a git tree OID (fail-closed)")
  let recordPathEnv = subjectRecordPathEnv(s)
  let recordPath = getEnv(recordPathEnv, "")
  if recordPath.len == 0:
    return err("judgment_cas: " & recordPathEnv &
      " not set — the record has no store path (fail-closed)")
  # Probe provenance (b-probe-tree p3): a decision that names its probe tree
  # must name THIS run's probe tree — plan and attest derived from the same
  # tested tree within one admission run. Absent (legacy wire) = no claim.
  let decisionProbeNode = decision{"probeTreeOid"}
  if not decisionProbeNode.isNil and decisionProbeNode.kind == JString and
      decisionProbeNode.getStr().len > 0:
    if decisionProbeNode.getStr() != testedTreeOid:
      return err("judgment_cas: decision probeTreeOid " &
        decisionProbeNode.getStr()[0 ..< 12] & " != current probe " &
        testedTreeOid[0 ..< 12] &
        " — the plan and the attest saw different trees (fail-closed)")
  var closure: JudgmentClosure
  try:
    let collected = collectJudgmentClosureFor(s, testedTreeOid)
    if collected.isErr:
      return err("judgment_cas: closure re-derivation failed (fail-closed): " & collected.error)
    closure = collected.get
  except CatchableError as exc:
    return err("judgment_cas: closure re-derivation raised (fail-closed): " & exc.msg)
  let freshKey = deriveJudgmentKey(closure)
  let decisionKey = decision{"evidenceKey"}
  if decisionKey.isNil or decisionKey.kind != JString or decisionKey.getStr() != freshKey:
    return err("judgment_cas: decision file key " &
      (if decisionKey.isNil or decisionKey.kind != JString: "<missing>" else: decisionKey.getStr()[0 ..< 12]) &
      " != freshly re-derived " & freshKey[0 ..< 12] &
      " — the plan and the attest saw different closures (fail-closed)")
  var payload = ""
  if basis == JudgmentWitnessBasisExecuted:
    let evidencePathEnv = subjectEvidencePathEnv(s)
    let evidencePath = getEnv(evidencePathEnv, "")
    if evidencePath.len == 0:
      return err("judgment_cas: EXECUTED basis requires " &
        evidencePathEnv & " — the run claims a fresh judgment it cannot show (fail-closed)")
    let parsed = parseJudgmentEvidenceFile(evidencePath)
    if parsed.isErr:
      return err("judgment_cas: " & parsed.error)
    payload = parsed.get
    var record: EvidenceCasRecord
    try:
      let built = buildJudgmentRecord(freshKey, payload)
      if built.isErr:
        return err(built.error)
      record = built.get
      writeFile(recordPath, evidenceRecordToCanonicalJson(record))
    except CatchableError as exc:
      return err("judgment_cas: judgment record publish failed (fail-closed): " & exc.msg)
  else:
    # The rootRecord provenance marker is REQUIRED on every REUSED decision
    # (redecision 2026-10-18): shape first — BEFORE any ledger IO, so an
    # unattributable skip fails without a transport; binding after the
    # re-fetch — the marker must name EXACTLY the re-fetched record.
    let marker = decision{"rootRecord"}
    let shape = judgmentRootRecordMarkerShape(marker)
    if shape.len > 0:
      return err("judgment_cas: REUSED decision carries no valid rootRecord " &
        "provenance marker — the skip's root EXECUTED record is unattributable " &
        "(fail-closed): " & shape)
    let token = getEnv("GITHUB_TOKEN", "")
    if token.len == 0:
      return err("judgment_cas: REUSED basis requires GITHUB_TOKEN — a skipped " &
        subjectTag & " whose record cannot be re-verified fails the run (fail-closed)")
    var record: EvidenceCasRecord
    try:
      let fetched = fetchEvidenceRecord(liveLedgerTransport(token, EvidenceCasRefName),
        resolveEvidenceCasRepo(), freshKey, EvidenceCasRefName)
      if fetched.isErr:
        return err("judgment_cas: REUSED record fetch failed — the skipped " &
          subjectTag & " cannot be re-verified, the run fails (fail-closed): " & fetched.error)
      record = fetched.get
    except CatchableError as exc:
      return err("judgment_cas: REUSED ledger transport raised — the run fails (fail-closed): " & exc.msg)
    let reuse = verifyJudgmentReuse(record, freshKey)
    if not reuse.ok:
      return err("judgment_cas: REUSED re-verification failed — the run fails (fail-closed): " & reuse.reason)
    payload = reuse.payload
    var boundPayload: JsonNode
    try:
      boundPayload = parseJson(record.payload)
    except CatchableError as exc:
      return err("judgment_cas: REUSED record payload unparsable — the run fails " &
        "(fail-closed): " & exc.msg)
    let markerBind = judgmentRootRecordMarkerMismatch(marker, record, boundPayload)
    if markerBind.len > 0:
      return err("judgment_cas: REUSED rootRecord marker does not bind the " &
        "re-fetched record — the run fails (fail-closed): " & markerBind)
    try:
      # Rebind: publish the stored record verbatim — the mint's append of an
      # identical (key, payload) is an exactly-once no-op.
      writeFile(recordPath, evidenceRecordToCanonicalJson(record))
    except CatchableError as exc:
      return err("judgment_cas: judgment record rebind failed (fail-closed): " & exc.msg)
    let rootKey = marker{"evidenceKey"}.getStr()
    return ok(JudgmentAttestOutcome(armed: true, basis: basis, evidenceKey: freshKey,
      reason: reason, node: judgmentWitnessNodeFor(s, basis, freshKey, payload),
      recordPath: recordPath, subject: subjectTag, rootEvidenceKey: rootKey))
  ok(JudgmentAttestOutcome(armed: true, basis: basis, evidenceKey: freshKey,
    reason: reason, node: judgmentWitnessNodeFor(s, basis, freshKey, payload),
    recordPath: recordPath, subject: subjectTag))

proc runJudgmentAttestBranch*(): Result[JudgmentAttestOutcome, string] {.
  raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## The s1a attest branch (the landed subject).
  runJudgmentAttestBranchForSubject(jsS1aGolden)

# ---------------------------------------------------------------------------
# Execution records — append-only PASS/FAIL/UNKNOWN accounting, separated
# from reusable-PASS eligibility (B/M/CAS execution–reuse separation)
# ---------------------------------------------------------------------------
## The landing-record surface above answers "is the stored judgment fact
## re-verifiable?"; THIS surface answers "what did THIS run actually
## execute?" — the two are deliberately different records:
##
##   * Execution records are append-only and record EVERY lane execution
##     outcome — PASS, FAIL, and UNKNOWN (a run whose outcome could not be
##     measured). A failed run leaves a FAIL record: the failure is visible
##     history, never a reuse authorization.
##   * Reusable-PASS eligibility is a SEPARATE predicate over the record:
##     the record must carry the current execution-record schemaVersion, the
##     verdict must be PASS, the basis must be EXECUTED (a reuse adoption is
##     not an execution), the measured evidence must be bound (evidenceSha256),
##     and the B/M/executor identities must match the CURRENT run exactly —
##     executor tree (B^{tree}), candidate tree (M^{tree}), overlay manifest
##     digest, toolchain bundle, contract version. Any absent/stale/mismatched
##     member fails the predicate: failed, UNKNOWN, old-generation, and
##     incomplete records are NEVER reusable.
##
## The GO-critical lane emits these records per subject (the workflow is the
## producer — the record shape is THIS module's contract); the s1a subject
## and the evidenceId contract check are additionally never REUSED at all
## (the lane's skip rule), so their records are always EXECUTED outcomes.

const
  JudgmentExecutionRecordSchema* = "axiom.judgment.cas.execution.v2"
    ## The execution-record wire schema. A record under any other version is
    ## an old-generation record: kept (append-only history), never reusable.
  JudgmentExecutionVerdictPass* = "PASS"
  JudgmentExecutionVerdictFail* = "FAIL"
  JudgmentExecutionVerdictUnknown* = "UNKNOWN"
  JudgmentExecutionRecordsDir* = "data/judgment-executions"
    ## The append-only execution-record store (content-addressed per record;
    ## lane artifacts carry the same bytes off-runner).
  CandidateTreeOidEnv* = "AXIOM_JUDGMENT_CANDIDATE_TREE_OID"
    ## M^{tree} — the TESTED candidate tree OID. The lane sets this to the
    ## candidate head's tree (NOT B's) and the attest re-derives the same
    ## value; a record minted under a different candidate tree can never
    ## match this identity.
  CandidateHeadShaEnv* = "AXIOM_JUDGMENT_CANDIDATE_HEAD_SHA"
    ## M commit sha — provenance (the tree OID is the identity member).
  OverlayManifestDigestEnv* = "AXIOM_JUDGMENT_OVERLAY_MANIFEST_DIGEST"
    ## H(sorted path+blob list) of the candidate→workspace overlay (src/ +
    ## the explicit test files). Exact-match identity: an overlay change is
    ## a different executed computation.

type
  JudgmentExecutionVerdict* = enum
    jevPass
    jevFail
    jevUnknown

func executionVerdictName*(v: JudgmentExecutionVerdict): string {.raises: [].} =
  case v
  of jevPass: JudgmentExecutionVerdictPass
  of jevFail: JudgmentExecutionVerdictFail
  of jevUnknown: JudgmentExecutionVerdictUnknown

func parseExecutionVerdict*(name: string): Result[JudgmentExecutionVerdict, string] {.
    raises: [].} =
  case name
  of JudgmentExecutionVerdictPass: ok(jevPass)
  of JudgmentExecutionVerdictFail: ok(jevFail)
  of JudgmentExecutionVerdictUnknown: ok(jevUnknown)
  else: err("judgment_cas: unknown execution verdict '" & name & "'")

type
  JudgmentReuseIdentity* = object
    ## The exact-match identity set of a reusable PASS record — the B/M/
    ## executor/overlay/toolchain/contract separation. A record missing any
    ## member, or carrying values that differ from the current run's, is
    ## never reusable (the predicate fails closed per member).
    schemaVersion*: string        ## execution-record schema the record was written under
    executorTreeOid*: string      ## B^{tree} — the executor workspace tree
    candidateTreeOid*: string     ## M^{tree} — the tested candidate tree
    candidateHeadSha*: string     ## M commit (provenance alongside the tree identity)
    overlayManifestDigest*: string## H(path+blob list) of the applied overlay
    toolchainBundle*: string      ## closure ④ — the measured toolchain bundle digest
    contractVersion*: string      ## the evidenceId contract version in force

  JudgmentExecutionRecord* = object
    ## One append-only record of ONE lane execution outcome.
    schemaVersion*: string
    subject*: string
    verdict*: JudgmentExecutionVerdict
    basis*: string                ## EXECUTED | REUSED | OFF (the plan's decision basis)
    evidenceKey*: string          ## 64-hex judgment key ("" when unarmed)
    evidenceSha256*: string       ## sha256 of the measured evidence bytes ("" when none)
    identities*: JudgmentReuseIdentity
    observedAtUtc*: string

func currentExecutionSchemaVersion*(): string {.raises: [].} =
  JudgmentExecutionRecordSchema

func executionRecordWire*(r: JudgmentExecutionRecord): string {.raises: [].} =
  ## Canonical JSON serialization (canonicalJsonString — RFC 8785 bytes).
  canonicalJsonString(%*{
    "schemaVersion": r.schemaVersion,
    "subject": r.subject,
    "verdict": executionVerdictName(r.verdict),
    "basis": r.basis,
    "evidenceKey": r.evidenceKey,
    "evidenceSha256": r.evidenceSha256,
    "identities": {
      "schemaVersion": r.identities.schemaVersion,
      "executorTreeOid": r.identities.executorTreeOid,
      "candidateTreeOid": r.identities.candidateTreeOid,
      "candidateHeadSha": r.identities.candidateHeadSha,
      "overlayManifestDigest": r.identities.overlayManifestDigest,
      "toolchainBundle": r.identities.toolchainBundle,
      "contractVersion": r.identities.contractVersion
    },
    "observedAtUtc": r.observedAtUtc})

func executionRecordId*(r: JudgmentExecutionRecord): string {.raises: [].} =
  ## Content address of the record — the append-only store keys by it.
  sha256Hex(executionRecordWire(r))

func validateJudgmentExecutionRecord*(r: JudgmentExecutionRecord): string {.
    raises: [].} =
  ## "" = well-formed; otherwise the rejection reason (fail-closed).
  if r.schemaVersion != JudgmentExecutionRecordSchema:
    return "judgment_cas: execution record schemaVersion must be " &
      JudgmentExecutionRecordSchema & " (fail-closed)"
  if r.subject.len == 0:
    return "judgment_cas: execution record subject must be non-empty (fail-closed)"
  if parseJudgmentSubject(r.subject).isErr:
    return "judgment_cas: execution record subject '" & r.subject &
      "' is not a judgment subject (fail-closed)"
  if r.basis != JudgmentWitnessBasisExecuted and r.basis != JudgmentWitnessBasisReused and
      r.basis != "OFF":
    return "judgment_cas: execution record basis must be EXECUTED/REUSED/OFF (fail-closed)"
  if r.evidenceKey.len > 0 and not isHexOfLen(r.evidenceKey, 64):
    return "judgment_cas: execution record evidenceKey must be 64 lowercase hex (fail-closed)"
  if r.evidenceSha256.len > 0 and not isHexOfLen(r.evidenceSha256, 64):
    return "judgment_cas: execution record evidenceSha256 must be 64 lowercase hex (fail-closed)"
  if r.observedAtUtc.len == 0:
    return "judgment_cas: execution record observedAtUtc must be non-empty (fail-closed)"
  # Identity members: the tree OIDs and digests must be well-formed WHEN
  # present; the REUSE predicate (below), not the shape validator, demands
  # exact presence — a partial record is shaped history, never reusable.
  for (label, value, hexLen) in [
      ("identities.executorTreeOid", r.identities.executorTreeOid, 40),
      ("identities.candidateTreeOid", r.identities.candidateTreeOid, 40),
      ("identities.candidateHeadSha", r.identities.candidateHeadSha, 40),
      ("identities.overlayManifestDigest", r.identities.overlayManifestDigest, 64),
      ("identities.toolchainBundle", r.identities.toolchainBundle, 64)]:
    if value.len > 0 and not isHexOfLen(value, hexLen):
      return "judgment_cas: execution record " & label & " must be " & $hexLen &
        " lowercase hex when present (fail-closed)"
  ""

func reusablePassRejection*(r: JudgmentExecutionRecord;
    current: JudgmentReuseIdentity): string {.raises: [].} =
  ## "" = the record IS a reusable PASS under the current identity set;
  ## otherwise the rejection reason. The eligibility contract, per member:
  ##   schemaVersion (current) · verdict=PASS · basis=EXECUTED · executed
  ##   evidence bound (evidenceKey + evidenceSha256 present) · exact
  ##   B/M/executor/overlay/toolchain/contract identity match.
  ## Failed/UNKNOWN/old/incomplete records are never reusable — every
  ## mismatch returns a reason, never a silent pass.
  if r.schemaVersion != current.schemaVersion:
    return "schemaVersion '" & r.schemaVersion & "' != current '" &
      current.schemaVersion & "' (old-generation record, never reusable)"
  if r.verdict != jevPass:
    return "verdict is " & executionVerdictName(r.verdict) &
      " — only PASS is reusable (fail-closed)"
  if r.basis != JudgmentWitnessBasisExecuted:
    return "basis is '" & r.basis & "' — only an EXECUTED (not adopted/reused) " &
      "record carries reusable execution evidence (fail-closed)"
  if not isHexOfLen(r.evidenceKey, 64):
    return "evidenceKey absent/malformed — no executed evidence key (fail-closed)"
  if not isHexOfLen(r.evidenceSha256, 64):
    return "evidenceSha256 absent/malformed — the measured evidence is unbound (fail-closed)"
  if r.identities != current:
    for member in ["schemaVersion", "executorTreeOid", "candidateTreeOid",
                   "candidateHeadSha", "overlayManifestDigest",
                   "toolchainBundle", "contractVersion"]:
      let got = case member
        of "schemaVersion": r.identities.schemaVersion
        of "executorTreeOid": r.identities.executorTreeOid
        of "candidateTreeOid": r.identities.candidateTreeOid
        of "candidateHeadSha": r.identities.candidateHeadSha
        of "overlayManifestDigest": r.identities.overlayManifestDigest
        of "toolchainBundle": r.identities.toolchainBundle
        else: r.identities.contractVersion
      let want = case member
        of "schemaVersion": current.schemaVersion
        of "executorTreeOid": current.executorTreeOid
        of "candidateTreeOid": current.candidateTreeOid
        of "candidateHeadSha": current.candidateHeadSha
        of "overlayManifestDigest": current.overlayManifestDigest
        of "toolchainBundle": current.toolchainBundle
        else: current.contractVersion
      if got != want:
        return "identity member '" & member & "' mismatch — record carries '" &
          (if got.len > 16: got[0 ..< 16] & "…" else: got) & "', current is '" &
          (if want.len > 16: want[0 ..< 16] & "…" else: want) &
          "' (exact-match identity required, fail-closed)"
  ""

proc appendExecutionRecord*(baseDir: string; r: JudgmentExecutionRecord): Result[string, string] {.
    raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect,
    tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Append ONE execution record to the append-only store: content-addressed
  ## `<baseDir>/<JudgmentExecutionRecordsDir>/<subject>/<id>.json`. Never
  ## overwrites: an existing file must byte-equal the canonical wire (the
  ## same execution re-observed) or the append fails closed — mutation of
  ## recorded history is unrepresentable.
  let shape = validateJudgmentExecutionRecord(r)
  if shape.len > 0:
    return err(shape)
  let wire = executionRecordWire(r)
  let id = executionRecordId(r)
  let dir = baseDir / JudgmentExecutionRecordsDir / r.subject
  let path = dir / (id & ".json")
  if not dirExists(dir):
    try:
      createDir(dir)
    except CatchableError as e:
      return err("judgment_cas: execution record dir create failed: " & dir & ": " & e.msg)
  if fileExists(path):
    var existing = ""
    try:
      existing = readFile(path)
    except CatchableError as e:
      return err("judgment_cas: execution record read failed: " & path & ": " & e.msg)
    if existing != wire:
      return err("judgment_cas: execution record id collision with different bytes " &
        "(recorded history mutation refused, fail-closed): " & path)
    return ok(path)
  try:
    writeFile(path, wire)
  except CatchableError as e:
    return err("judgment_cas: execution record append failed: " & path & ": " & e.msg)
  ok(path)

proc collectReuseIdentity*(executorTreeOid, candidateTreeOid, candidateHeadSha,
    overlayManifestDigest: string): Result[JudgmentReuseIdentity, string] {.
    raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect,
    tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Assemble the CURRENT run's reuse identity — fail-closed on any
  ## unmeasurable member (an identity can never rest on a guessed value).
  ## The toolchain bundle is the closure-④ measurement; the contract version
  ## is the core SSOT constant shared with the contract checker.
  if not isHexOfLen(executorTreeOid, 40):
    return err("judgment_cas: executor tree OID must be 40-hex (fail-closed)")
  if not isHexOfLen(candidateTreeOid, 40):
    return err("judgment_cas: candidate tree OID must be 40-hex (fail-closed): set " &
      CandidateTreeOidEnv)
  if not isHexOfLen(candidateHeadSha, 40):
    return err("judgment_cas: candidate head sha must be 40-hex (fail-closed): set " &
      CandidateHeadShaEnv)
  if not isHexOfLen(overlayManifestDigest, 64):
    return err("judgment_cas: overlay manifest digest must be 64-hex (fail-closed): set " &
      OverlayManifestDigestEnv)
  let bundle = collectToolchainBundleDigest()
  if bundle.isErr:
    return err("judgment_cas: toolchain bundle unmeasurable (fail-closed): " & bundle.error)
  ok(JudgmentReuseIdentity(
    schemaVersion: currentExecutionSchemaVersion(),
    executorTreeOid: executorTreeOid,
    candidateTreeOid: candidateTreeOid,
    candidateHeadSha: candidateHeadSha,
    overlayManifestDigest: overlayManifestDigest,
    toolchainBundle: bundle.get,
    contractVersion: EvidenceIdContractVersion))

{.pop.}
