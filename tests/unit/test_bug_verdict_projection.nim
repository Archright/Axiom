## test_bug_verdict_projection.nim — S6/S8 PROPOSITION_DISPROVED·NO_BUG_PROVED projection
## measured end-to-end over the real base36 relational composite.
##
## SSOT: docs/spec/bug_verdict_glossary.md —
##   NO_BUG_PROVED = vrPass ∧ vdVerified ∧ clProved
##   PROPOSITION_DISPROVED = vrFail ∧ clDisproved ∧ classified(icCounterexample)
##   BUG_FOUND is not a machine verdict: it is the report-input attribution value
##   for DISPROVED ∧ recordedBinding (§2.2 verdict table), backed by the
##   4-element record (exact commit · exact input · violated conjunct · replay
##   observation) — a reporting precondition, never machine output.
##
## Golden leg: the composite P_rel = decodedLength(encodedLength(n)) under the
## sizing-bound domain is verified by the REAL Lean kernel
## (executeCanonicalVerification → vdVerified with a sealed subject-bound
## evidence artifact, sealError "") and projects NO_BUG_PROVED at every layer:
## pipeline vsProved, claim clProved (deriveClaim over the committed overlay
## spec — the A5 precedent in test_base36_contract_policy.nim), run-level
## vrPass/rbProven (accounting + VDA, the only run-verdict authority).
##
## Mutant leg: the `+1`-erosion mutant of encodedLength
## (tests/negative/base36_mutant_subject — pure fixture isolation, nim-stew
## itself is untouched) is kernel-rejected, the BMC lane goes SAT with a
## concrete model, the P4 witness admission re-validates pre ∧ ¬post and
## promotes cvConfirmed → vsDisproved, and — only when the worktree is
## porcelain-clean — the replay adapter reproduces the violation with the real
## pinned toolchain and folds the glossary-§2.2 four-element PROPOSITION_DISPROVED payload.
## On a dirty worktree the adapter fail-closes (rvUnavailable → the S4-S5
## cvUnresolved demotion). The test accepts exactly these two states and
## nothing else: a fabricated PROPOSITION_DISPROVED fails either way.
##
## S8 reverse paths (fail-closed bindings):
##   S8-1 unmeasured parse-bound components refuse the seal;
##   S8-2 tampered fixture bytes move the §6a source identity (the sealed
##        golden identity never matches the tampered module);
##   S8-3 a vacuous (tautological-precondition) subject cannot reach VERIFIED
##        — the pipeline tautology guard rejects before any verdict;
##   S8-4 replay disagreement is fail-closed rvDisagree — measured in
##        tests/unit/test_counterexample_replay.nim ("property actually holds
##        on observed result → rvDisagree"), not duplicated here.
##
## The four expensive fixtures (two syntheses + two full pipelines incl. the
## Lean kernel lane) are measured ONCE at module init and shared by the suites.
import std/[json, os, options, strutils, tables, sequtils, unittest]

import ../../src/core/results
import ../../src/core/crypto/hash_kernel
import ../../src/core/utils/repo_root
import ../../src/core/deterministic_cas_key
import ../../src/core/trusted/specification_artifact
import ../../src/core/trusted/evidence_calculus
import ../../src/core/trusted/assurance_profile
import ../../src/core/trusted/claim_authority
import ../../src/core/trusted/axiom_pragmas
import ../../src/core/trusted/axiom_ir
import ../../src/core/types/hubs/sorter_node_id
import ../../src/core/orchestrator/orchestrator_report_types
import ../../src/cli/wf_render
import ../../src/cli/verdict_display
import ../../src/cli/axiom_engine
import ../../src/verification/accounting/run_accounting
import ../../src/verification/obligation/verification_decision_authority
import ../../src/verification/obligation/canonical_verification
import ../../src/verification/obligation/obligation_ir
import ../../src/verification/obligation/canonical_obligation_generator
import ../../src/verification/batch_uap/ir_pipeline_runner
import ../../src/verification/solver/z3_pool
import ../../src/verification/solver_adapter
import ../../src/core/trusted/candidate_evidence
import ../../src/verification/counterexample_validator
import ../../src/infrastructure/external_ir_materializer
import ../../src/verification/ax_tautology
import ../../src/core/trusted/verification_result_types as vrt

# ---------------------------------------------------------------------------
# Fixture plumbing — the same resolver/synthesis the engine drives.
# ---------------------------------------------------------------------------

proc fixtureResolver(root: string): ModuleContentResolver =
  result = proc(modulePath: string): Option[string] {.raises: [].} =
    try:
      some(readFile(root / modulePath))
    except CatchableError:
      none(string)

proc preSynthesisIrAnchor(ve: ExternalIrEntry): string =
  ## The §2.1a completeness anchor, computed at the materializer boundary
  ## exactly as the runner threads it into canonical verification
  ## (ir_pipeline_runner.nim: `preSynthesisIrDigest =
  ## computeDeterministicCasKey(serializeIRFuncDef(ve.funcDef))`) — the
  ## reader searches this anchor before the current funcDef's key.
  computeDeterministicCasKey(serializeIRFuncDef(ve.funcDef))

proc synthFor(root: string): Option[ExternalIrEntry] =
  ## Synthesize the relational composite from the base36 overlay over `root`.
  ## The subject root is threaded like the engine's production call (the
  ## analysis root IS the subject root for the external flow) — the strict
  ## completeness capture is content-carried, so without a threaded root it
  ## is unmeasurable and the dual-write fail-closes.
  var census = ExternalCandidateCensus()
  let domainRes = loadBase36OverlayDomain()
  if domainRes.isErr:
    return none(ExternalIrEntry)
  let synth = synthesizeBase36RelationalCandidate(
    "encodedLength", domainRes.get().modulePath,
    fixtureResolver(root), domainRes.get(), census,
    subjectRepoRoot = root)
  if synth.isErr:
    return none(ExternalIrEntry)
  if census.eligible.len != 1:
    return none(ExternalIrEntry)
  some(census.eligible[0])

proc runPipeline(ve: ExternalIrEntry; root: string): IrPipelineResult =
  var memo = initTable[string, IrPipelineResult]()
  let pve = ValidatedIrEntry(entry: ve.entry, funcDef: ve.funcDef,
                             parseBound: ve.parseBound)
  runIrPipelineWithCas(pve, nil, memo, bpRequire, root)

proc claimCtx(spec: SpecificationArtifact; signal: ClaimSignal): ClaimContext =
  ## A5 precedent (test_base36_contract_policy.nim) — the real overlay spec
  ## through the real claim calculus.
  var bundle: EvidenceBundle
  bundle.specificationArtifact = spec
  bundle.facts.solver.solverIdentity = "z3"
  bundle.facts.solver.smtHash = "abc123"
  ClaimContext(
    subjectId: "stew/base36.nim", sourceIdentity: "h", specification: spec,
    semanticProfileId: spec.specIdentity, obligationGenerated: true,
    supported: true, dependenciesSatisfied: true, proofSignal: signal,
    evidenceBundle: bundle, policyId: "apV1")

proc overlaySpec(): SpecificationArtifact =
  explicitSpecFromOverlay(parseJson(readFile(
    repoRootConst() / "config" / "spec" /
    "base36_sizing_relational_spec.json"))).get()

proc makeNodeReport(unitId, status: string): JsonNode =
  %*{"nodeId": unitId, "status": status, "cacheHit": false,
     "dependencyDepth": 0}

proc runVerdictFor(status: string): RunOutcome =
  ## The run-level projection for a single-node wave with the canonical OGR
  ## eligibility basis (elProofCandidate = REQUIRED) — the same reducer + VDA
  ## the engine drives.
  let wave = %*{"nodeReports": @[makeNodeReport(
    "stew/base36.nim::encodedLength", status)]}
  let elig = %*{"stew/base36.nim::encodedLength": "elProofCandidate"}
  let acc = reduceRunAccounting(@[wave], elig)
  evaluateRunOutcome(acc,
    NoObligationProvenance(universeEnumerated: true,
                           source: "canonical_ogr_eligibility"),
    false)

putEnv("AXIOM_STATE_DIR", getTempDir() / "ax_s6_test_state")

let testsRoot = currentSourcePath().parentDir().parentDir()
let goldenRoot = testsRoot / "golden" / "base36_subject"
let mutantRoot = testsRoot / "negative" / "base36_mutant_subject"

let goldenSynth = synthFor(goldenRoot)
let mutantSynth = synthFor(mutantRoot)
let goldenPipeline =
  if goldenSynth.isSome: some(runPipeline(goldenSynth.get, goldenRoot))
  else: none(IrPipelineResult)
let mutantPipeline =
  if mutantSynth.isSome: some(runPipeline(mutantSynth.get, mutantRoot))
  else: none(IrPipelineResult)

# ---------------------------------------------------------------------------
# S6 golden — NO_BUG_PROVED projection (glossary §2.1)
# ---------------------------------------------------------------------------

suite "S6 golden — NO_BUG_PROVED projection":

  test "synthesis measures the §2.1a composite parse-bound legs":
    check goldenSynth.isSome
    let ve = goldenSynth.get
    check ve.parseBound.synthesizedComposite
    check not ve.parseBound.claimCarrierSingleOrigin
    check ve.parseBound.measuredForFuncName == "decodedLength"
    check ve.parseBound.ea2MeasuredForFuncName == "encodedLength"
    check ve.parseBound.compositeCarrierTypename.len > 0
    check ve.parseBound.eaAgreed and ve.parseBound.ea2Agreed

  test "the real Lean kernel verifies the golden composite (vdVerified, sealed)":
    let ve = goldenSynth.get
    let cres = executeCanonicalVerification(
      ve.funcDef, ve.entry.sourcePath, ve.entry.name, ve.entry.sourceContent,
      subjectRepoRoot = goldenRoot, preSynthesisIrDigest = preSynthesisIrAnchor(ve),
      parseBound = ve.parseBound)
    check cres.verdict == vdVerified
    check cres.success
    check cres.sealError.len == 0
    check cres.evidence == "lean_kernel_accepted"
    # §6a source identity binds the exact measured bytes.
    check cres.inputHash == sha256Hex(ve.entry.sourceContent)

  test "the pipeline projects vsProved on the golden composite":
    check goldenPipeline.isSome
    let res = goldenPipeline.get
    check res.success
    check res.verification.status == vsProved

  test "the claim layer projects clProved (A5 precedent, real overlay spec)":
    check deriveClaim(claimCtx(overlaySpec(), psUnsat), apV1).outcome == clProved

  test "the run level projects vrPass/rbProven":
    let decided = runVerdictFor("verified")
    check decided.verdict == vrPass
    check decided.basis == rbProven

# ---------------------------------------------------------------------------
# S6 mutant — PROPOSITION_DISPROVED 4-element projection (glossary §2.2)
# ---------------------------------------------------------------------------

suite "S6 mutant — PROPOSITION_DISPROVED projection":

  test "the real Lean kernel rejects the eroded mutant":
    check mutantSynth.isSome
    let ve = mutantSynth.get
    let cres = executeCanonicalVerification(
      ve.funcDef, ve.entry.sourcePath, ve.entry.name, ve.entry.sourceContent,
      subjectRepoRoot = mutantRoot, preSynthesisIrDigest = preSynthesisIrAnchor(ve),
      parseBound = ve.parseBound)
    check not cres.success
    check cres.verdict == vdCandidate
    check cres.evidence == "lean_kernel_rejected"

  test "P4 witness admission promotes the BMC SAT model to vsDisproved (cvConfirmed)":
    ## The promotion machinery measured directly (worktree-state-independent):
    ## the exact script the BMC lane ran goes back through z3, the concrete
    ## model becomes candidate evidence, the one-state contract model is
    ## re-validated (pre ∧ ¬post), and cvConfirmed finalizes vsDisproved.
    check mutantPipeline.isSome
    let ve = mutantSynth.get
    let res = mutantPipeline.get
    check res.smtScript.len > 0
    var env, transport: string
    let oc = runZ3CheckViaIR(res.smtScript & "\n(get-model)", spBmc, env, transport)
    check oc.status == sosSat
    check oc.modelBindings.len >= 1
    let ce = toCandidateEvidence(oc)
    check not ce.isEmpty()
    check ce.model.len > 0
    let model = lowerPostconditionModel(ve.funcDef, contractFromFuncDef(ve.funcDef))
    check model.isSome
    let cx = newCounterexampleValidator("z3", getBudgetFor(spBmc).timeoutMs)
    let cv = validateCounterexample(cx, model.get, ce, "z3",
                                    getBudgetFor(spBmc).timeoutMs)
    check cv == cvConfirmed
    let final = finalizeVerdict(
      makeCandidateCounterexample(ce.model, smBMC, pkZ3Bmc), cv)
    check final.status == vsDisproved
    check final.model.len > 0

  test "the pipeline projects the claim leg clDisproved either way":
    check mutantPipeline.isSome
    let res = mutantPipeline.get
    # The claim derives from the solver's SAT (pre-replay authority); the
    # porcelain-gated replay below can demote the VERDICT, never the claim.
    check res.verifiedClaim.isSome
    check res.verifiedClaim.get.outcome == clDisproved

  test "the replay gate folds the §2.2 four-element PROPOSITION_DISPROVED record — or fails closed":
    check mutantPipeline.isSome
    let res = mutantPipeline.get
    if res.counterExample.len > 0:
      # Porcelain-clean worktree: the adapter ran the real toolchain and
      # agreed. All four glossary elements must be present in the payload.
      # ① exact commit (the measured subject git identity)
      check res.counterExample.anyIt(it.startsWith("replay.subjectGitRef=") and
        it.substr("replay.subjectGitRef=".len).len >= 40)
      # ② exact input (the concrete solver model assignment)
      check res.counterExample.anyIt(it.startsWith("input."))
      # ③ the violated conjunct (the roundtrip equation the mutant erodes)
      check res.counterExample.anyIt(
        it.startsWith("propertyViolated=") and it.contains("bvsdiv"))
      # ④ the replay observation (the real-toolchain reproduction record)
      check res.counterExample.anyIt(it == "replay.verdict=rvAgree")
      check res.verification.status == vsDisproved
    else:
      # Dirty worktree: the adapter MUST fail closed — cvUnresolved demotion
      # carrying the replay diagnostics, never a fabricated PROPOSITION_DISPROVED.
      check res.verification.status == vsInconclusive
      check res.verification.reason == rkCandidateCounterexample
      check res.verification.evidence.startsWith("replay:")

  test "the run level projects vrFail (proof-level failure only)":
    let decided = runVerdictFor("failed")
    check decided.verdict == vrFail
    check gateVerdictProjection(decided) == gvFail

# ---------------------------------------------------------------------------
# S8 reverse paths — fail-closed bindings
# ---------------------------------------------------------------------------

suite "S8 reverse paths":

  test "S8-1: unmeasured parse-bound components refuse the seal":
    let ve = goldenSynth.get
    let cres = executeCanonicalVerification(
      ve.funcDef, ve.entry.sourcePath, ve.entry.name, ve.entry.sourceContent,
      subjectRepoRoot = goldenRoot, preSynthesisIrDigest = preSynthesisIrAnchor(ve),
      parseBound = SubjectParseBoundComponents())
    check not cres.success
    check cres.verdict != vdVerified
    check cres.sealError.contains("parse-bound components unmeasured")

  test "S8-2: tampered fixture bytes move the §6a source identity":
    let ve = goldenSynth.get
    let honest = executeCanonicalVerification(
      ve.funcDef, ve.entry.sourcePath, ve.entry.name, ve.entry.sourceContent,
      subjectRepoRoot = goldenRoot, preSynthesisIrDigest = preSynthesisIrAnchor(ve),
      parseBound = ve.parseBound)
    let tamperedContent = ve.entry.sourceContent & "\n# tampered byte stream\n"
    let tampered = executeCanonicalVerification(
      ve.funcDef, ve.entry.sourcePath, ve.entry.name, tamperedContent,
      subjectRepoRoot = goldenRoot, preSynthesisIrDigest = preSynthesisIrAnchor(ve),
      parseBound = ve.parseBound)
    # The source identity moves with the bytes — byte-exact, never composed.
    check tampered.inputHash == sha256Hex(tamperedContent)
    check tampered.inputHash != honest.inputHash
    # The IR identity is stable (a comment does not change the verified IR):
    # the identity split is what makes the sealed golden artifact useless for
    # the tampered module (CAS keying never matches).
    check tampered.irHash == honest.irHash

  test "S8-3: a vacuous subject cannot reach VERIFIED (fail-closed, measured)":
    ## The vacuity guard's SMT conversion measures tcUnknown for free-variable
    ## bv conditions (no constant declarations in its probe script — measured),
    ## so for this subject the active VERIFIED-blocker is the C20 evidence
    ## gate: the BMC lane returns UNSAT (the tautological property holds
    ## trivially) but solver unsat alone can never produce a Proved verdict —
    ## the discharge refuses for missing evidence. Either way VERIFIED is
    ## unreachable: this is the anti-theater admission measured end-to-end.
    let xv = IRExpr(kind: irVar, varName: "x",
                    varType: irTypeBitVec64(), typ: irTypeBitVec64())
    let taut = IRExpr(kind: irBinOp, binOp: boEq, binLhs: xv, binRhs: xv,
                      typ: irTypeBool())
    check checkInvariantVacuity(@[taut]) == tcUnknown
    let vacuousDef = IRFuncDef(
      name: "vacuous_subject",
      params: @[IRFuncParam(name: "x", ty: irTypeBitVec64())],
      retType: irTypeBitVec64(),
      body: IRExpr(kind: irVar, varName: "x",
                   varType: irTypeBitVec64(), typ: irTypeBitVec64()),
      preConditions: @[taut],
      postConditions: @[taut])
    let ve = ValidatedIrEntry(
      entry: RuntimeAxiomEntry(name: "vacuous_subject",
                               sourcePath: "synthetic/vacuous_subject.nim"),
      funcDef: vacuousDef)
    var memo = initTable[string, IrPipelineResult]()
    let res = runIrPipelineWithCas(ve, nil, memo, bpRequire, goldenRoot)
    check not res.success
    check res.verification.status != vsProved
    check res.verification.status == vsInconclusive
    check res.verification.reason == rkEvidenceRejected
    check res.provenance == vpZ3Bmc

  test "S8-4: replay disagreement is fail-closed rvDisagree (measured in test_counterexample_replay)":
    # The full harness measurement lives in tests/unit/test_counterexample_replay.nim
    # ("property actually holds on observed result → rvDisagree"); this pins
    # the same agreement contract at the projection boundary: a property that
    # concretely HOLDS on the observed result can never complete the §2.2
    # record — the pipeline demotes to cvUnresolved (the branch the
    # dirty-worktree case above exercises with rvUnavailable).
    check decideReplayVerdict(true, some(true)) == rvDisagree
    check decideReplayVerdict(true, some(false)) == rvAgree

# ---------------------------------------------------------------------------
# displayInputDigest — pure projection pins (bug-verdict-display-v3)
# ---------------------------------------------------------------------------

suite "displayInputDigest — pure projection pins (v3)":

  proc pinInput(specId: string; specRelPath: string): BugVerdictDisplayInput =
    BugVerdictDisplayInput(
      machineEstablished: true,
      machineTuple: %*{"verdict": "FAIL", "recordComplete": true},
      ruleId: "external:fixture/rule",
      ownership: parseJson("""{"owner":"unrecorded"}"""),
      groundsRefs: @[],
      groundsRawDigest: "absent",
      assessment: GroundsAssessment(),
      targetSymbol: "fixture::unit",
      specId: specId,
      specRelPath: specRelPath)

  test "determinism: identical inputs project identical digests":
    check displayBugVerdict(pinInput("spec-x", "config/spec/a.json")).displayInputDigest ==
      displayBugVerdict(pinInput("spec-x", "config/spec/a.json")).displayInputDigest

  test "specId perturbation moves the digest (overlay identity is bound)":
    check displayBugVerdict(pinInput("spec-a", "config/spec/a.json")).displayInputDigest !=
      displayBugVerdict(pinInput("spec-b", "config/spec/a.json")).displayInputDigest

  test "specRelPath perturbation moves the digest (unit↔overlay link is bound)":
    check displayBugVerdict(pinInput("spec-x", "config/spec/a.json")).displayInputDigest !=
      displayBugVerdict(pinInput("spec-x", "config/spec/b.json")).displayInputDigest

  test "container schemaVersion pins the v3 display vocabulary":
    let container = displayContainerJson(@[])
    check container{"schemaVersion"}.getStr("") == bugVerdictDisplaySchemaVersion
    check container{"schemaVersion"}.getStr("") == "bug-verdict-display-v3"
    check container{"units"}.getElems().len == 0
