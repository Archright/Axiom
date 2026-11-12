## IR Pipeline Runner — Orchestrates the 4-stage IR verification pipeline.
##
## Stage 1: Deserialize IR (axiom_ir.deserializeIRFuncDef)
## Stage 2: Generate SMT-LIB2 (ir_to_smt.irToSmtScript)
## Stage 3: Generate Lean 4 (ir_to_lean.irToLeanModule)
## Stage 4: Cross-validate + Z3 check-sat
##
## This module is called from loop_driver.nim when --legacy-uap is NOT set.
##
## W4 Optimizations:
##   W4-A: Cross-validation builds CrossValidationResult inline from
##         already-computed smtScript/leanSource instead of regenerating them.
##   W4-B: ValidatedIrEntry caches IRFuncDef deserialization (one-time cost)
##         to avoid double deserialization across selection + pipeline.
##   W4-C: Provenance set to vpZ3Bmc when Z3 returns unsat (property holds).
##   W4-D: Pipeline stays sequential — Z3 check-sat bottleneck already
##         parallelized via z3_pool subprocess isolation. IR generation
##         is pure CPU-bound on small inputs where spawn overhead dominates.
##         malebolgia spawn blocked by Nim 2.2 isolation check on seq/ref fields.

import core/trusted/layer_declaration
axiomLayer "infrastructure"
import std/[strutils, tables, sets, math, options, algorithm, sequtils, os]
import core/axiom_pragmas
import core/lean_lsp_types
import core/trusted/axiom_ir
import core/trusted/symbol_table_types
import core/trusted/evidence_capture
import core/trusted/specification_artifact
import core/trusted/evidence_calculus
import core/trusted/claim_authority
import core/trusted/assurance_profile
import core/trusted/semantic_profile
import core/trusted/binding_inventory
import core/trusted/ir_to_smt
import core/trusted/private/ir_loop_to_horn
import verification/obligation/canonical_obligation_generator
import verification/obligation/obligation_ir  ## P3: ObligationGenerationResultKind type
import verification/obligation/obligation_types  ## P3: ObligationSkipReason
import verification/obligation/canonical_verification  ## S1-A: executeCanonicalVerification
import verification/obligation/kernel_acceptance_authority  ## CanonicalLeanEvidence
import verification/obligation/semantic_environment  ## WP4-j.2 Phase C+D: semantic facts
import core/trusted/semantic_fact_types
import core/trusted/private/chc_build_result
import core/trusted/private/chc_types
import core/trusted/private/loop_transition_lowering
import core/trusted/private/obligation_smt_lowering
import core/proof/proof_budget
import core/trusted/verification_result_types as vrt except SolverStatus
import core/types/solver_types as coreSolverTypes
import core/logic/smt_logic
import core/trusted/ir_to_lean
import core/trusted/contract_synthesis
import core/trusted/ir_inline_pass  # inlineSmallFunctions — pre-SMT inlining
import core/orchestrator/orchestrator_request_types
import core/sorter/sorter_core_index_base
import verification/cross_validation
import core/results
import verification/solver/z3_pool
import sieve/trivial_lean_router
import infrastructure/logging_facade
import infrastructure/external_ir_materializer
import infrastructure/evidence_artifact_io
import core/deterministic_cas_key
import core/utils/repo_root
import engine/proof_certificate  ## AGENT-C: ProofCertificate ADT
import verification/obligation/canonical_outcome  ## P5: outcome contract invariant
import verification/obligation/verification_result_interpreter  ## P3: SemanticOutcome
import core/telemetry/complexity
import core/crypto/hash_kernel
import core/parsers/safe_parsers
import verification/ax_tautology
import verification/ax_classify
import verification/ax_implication
import verification/admissibility
import verification/obligation/candidate_eligibility
import core/trusted/candidate_evidence
import core/trusted/backend_capability
import core/trusted/verification_model_types
import verification/evidence_validator
import verification/solver_adapter
import core/trusted/solver_invocation
import verification/counterexample_validator

type
  ## Backend that actually executed, per C13.
  VerificationBackend* = enum
    vbCanonicalChc  ## VerificationModel-derived canonical CHC pipeline
    vbLegacy        ## Pre-VerificationModel CHC encoding (buildChcTransitionSystem)

  ## Backend policy — controls whether canonical CHC failure may fall back
  ## to the legacy encoder. bpRequire (default) is fail-closed: canonical
  ## failure/decline → Inconclusive/NotEncodable, no silent legacy.
  ## bpAllowFallback permits the legacy encoder only after explicit opt-in.
  BackendPolicy* = enum
    bpRequire       ## Fail-closed: no implicit legacy fallback (default)
    bpAllowFallback ## Permit legacy encoder after canonical failure

  VerificationProvenance* = enum
    vpNone                ## 미검증
    vpZ3Bmc               ## Z3 BMC (check-sat unsat)
    vpTypeLevelEncoding   ## Lean 커널 type-level encoding (trivial_lean_router)
    vpDual                ## Z3 + Lean 모두 통과
    vpBmcSkipped          ## BMC skipped — float/string types not representable in QF_BV
    vpInductiveLoop       ## Spacer/CHC inductive invariant — loop verified via CHC

  ## Obligation generation verdict — attached to every IrPipelineResult so
  ## downstream stages (loop_driver stage2Budget) can distinguish obligation
  ## absence reasons without re-running the generator.
  ## DEBT#422: Legacy skipReason 'no_obligation' / 'bmc_skipped' mapping inconsistency between ir_pipeline_runner and loop_driver.
  ObligationVerdictInfo* = object
    kind*: ObligationGenerationResultKind  ## ogrGenerated / ogrNoApplicableObligation / ogrUnsupported / ogrIllFormed
    reason*: string  ## human-readable reason for non-generated variants
    obligationCount*: int  ## number of obligations generated; preserved (never zeroed)
                           ## on post-generation early-return paths (DEBT#423: TheaterGuard
                           ## must not bypass the obligation-attempted count).

  ## DEBT#423: TheaterGuard wrapper allows early-return paths that bypass obligation-attempted count accumulator.
  IrPipelineResult* = object
    funcName*: string
    modulePath*: string  ## Repo-relative module path (from ve.entry.sourcePath)
    irDigest*: string
    smtScript*: string
    leanSource*: string
    crossValidation*: CrossValidationResult
    z3Sat*: bool
    success*: bool
    skipped*: bool
    verification*: vrt.VerificationResult  ## Unified verification result
    provenance*: VerificationProvenance  ## Backward-compat provenance (legacy)
    ## C13 Backend Activation / Provenance: which semantic pipeline actually
    ## ran, and whether an implicit fallback was forced (must be observable).
    backend*: VerificationBackend
    actualBackend*: VerificationBackend
    fallbackOccurred*: bool
    fallbackReason*: string
    requestedBackend*: VerificationBackend
    selectedBackend*: VerificationBackend
    complexity*: float  ## Cyclomatic complexity for VKD metric
    verifiedClaim*: Option[VerifiedClaim]  ## Phase-4a: Evidence->Claim (deriveClaim), projection-only downstream
    obligationVerdict*: ObligationVerdictInfo  ## P3: obligation generation result
    ## S2: canonical evidence — populated only when the canonical Lean
    ## verification path produced a genuine KAA.  None on all other paths.
    evidence*: Option[CanonicalLeanEvidence] = none(CanonicalLeanEvidence)
    obligationExecution*: ObligationExecutionRecord
    ## S4-S5 PROPOSITION_DISPROVED payload — populated ONLY when the P4 promotion
    ## (cvConfirmed) survived replay agreement: exact input bindings, the
    ## violated property, and the replay record folds. Empty on every other
    ## path; projected into ProofCertificate.counterExample (slot pre-exists).
    counterExample*: seq[string] = @[]

  ## W4-B: Cached deserialization — avoids double deserializeIRFuncDef.
  ## Value type (not ref) for safe move semantics across call boundaries.
  ValidatedIrEntry* = object
    entry*: RuntimeAxiomEntry    ## Original registry entry
    funcDef*: IRFuncDef          ## Cached deserialization (one-time cost at selection)
    parseBound*: SubjectParseBoundComponents = SubjectParseBoundComponents()
      ## §2.1a parse-bound components (pnodeV2 + extraction agreement), measured
      ## on the MAIN thread at the selection boundary and threaded into the
      ## gcsafe IR-worker chain as this value — the worker chain never parses
      ## subject source (see SubjectParseBoundComponents). All-empty = unmeasured
      ## → the canonical binding fails closed.
    sourceBindingInventory*: Option[BindingInventory] = none(BindingInventory)
      ## Phase 1A: the independently observed source-side binding inventory of
      ## this entry's funcDef definition, measured on the MAIN thread at the
      ## selection boundary (same trusted observer the external materializer
      ## uses) and threaded into the gcsafe worker chain as a value. none =
      ## unmeasured → `measuredKernelCompletenessEvidence` fails
      ## `bindingUniverseComplete` closed.
    completenessCapture*: CompletenessCaptureIdentity = CompletenessCaptureIdentity()
      ## Phase 1A: the measured strict-binding identity inputs at capture time
      ## (canonical sourceIdentity composite + module sha256), measured on the
      ## MAIN thread with the subject root the pipeline threads to the reader.
      ## Empty sourceIdentity = unmeasurable → the strict dual-write is
      ## refused and only the legacy artifact is written.

  SelectionReport* = object
    ## Integrity report for topology-to-registry mapping.
    selected*: seq[ValidatedIrEntry]  ## Successfully mapped entries (topology order preserved)
    skippedNodes*: seq[string]         ## Topology nodes with no @axiom IR registry entry
    skippedCount*: int                 ## len(skippedNodes) — for quick anomaly detection

# DEBT#423 / ADR-0014 §4: obligation verdict constructors for every pipeline
# exit that happens AFTER obligations were generated. The generated count
# must be preserved on early-return paths — the TheaterGuard must not
# short-circuit obligation counting.

func generatedObligationVerdict*(count: int): ObligationVerdictInfo {.raises: [], axiomDebt: "DEBT#422".} =
  ## Verdict for post-generation exits (CHC loops, BMC-skip, tautology, admission,
  ## legacy encoder, type-level fast-path): kind stays ogrGenerated and the count
  ## is preserved instead of defaulting to 0.
  ObligationVerdictInfo(kind: ogrGenerated, reason: "", obligationCount: count)

func theaterDetectedVerdict*(count: int): ObligationVerdictInfo {.raises: [], axiomDebt: "DEBT#423".} =
  ## TheaterGuard verdict (ADR-0014 §4): a theater-classified target is recorded
  ## with the distinguishable reason "theater_detected" AND the generated
  ## obligation count is preserved (the guard fails closed, it does not bypass
  ## obligation accounting).
  ObligationVerdictInfo(kind: ogrIllFormed, reason: "theater_detected", obligationCount: count)

func selectBackend*(policy: BackendPolicy; canonicalSucceeded: bool): tuple[
  backend: VerificationBackend,
  fallbackOccurred: bool,
  fallbackReason: string
] {.raises: [].} =
  ## Pure backend-selection decision. Given the policy and whether the
  ## canonical CHC path succeeded, returns which backend was selected,
  ## whether a fallback occurred, and a human-readable reason.
  ## bpRequire (default) never silently routes to legacy — canonical
  ## failure stays on vbCanonicalChc with fallbackOccurred=false.
  if canonicalSucceeded:
    (vbCanonicalChc, false, "")
  elif policy == bpAllowFallback:
    (vbLegacy, true, "Canonical CHC did not prove loop; legacy encoder activated under bpAllowFallback")
  else:
    (vbCanonicalChc, false, "")

func admissionDecision*(obligation: VerificationModel; policy: BackendPolicy): tuple[
  permitted: bool, backend: VerificationBackend, reason: string
] {.axiomDecision(
  id = "DECISION-0619",
  reason = "Admission gate: permits backend selection only when the obligation is encodable for a runnable backend; bkChc is the sole executable backend, bkBmc is capability-registered but has no executor",
  adr = "docs/spec/verification_result_types.md",
  introduced = "v37").} =
  if canEncode(obligation, bkChc) and isRunnable(bkChc):
    (true, vbCanonicalChc, "primary CHC encodable and runnable")
  elif policy == bpAllowFallback and canEncode(obligation, bkChc):
    (true, vbLegacy, "legacy CHC transition-system encoder under bpAllowFallback")
  else:
    (false, vbCanonicalChc, "not-admitted: bkChc only executable backend; obligation not encodable or not-runnable")

func classifyZ3Output*(raw: string; elapsedMs: int; timeoutMs: int): solver_adapter.SolverStatus {.raises: [].} =
  ## SAT is minted only through the trusted discriminators (DECISION-0824/0825):
  ## `solverResponse(raw) == srSat` holds only when the stream carries no
  ## `(error ...)` response and its first exact verdict token is `sat`. The
  ## persistent pool exposes no per-query exit code, so the stdout predicate is
  ## the whole gate here (see solver_invocation.nim, `solverResponse` stream-only
  ## overload). An error-bearing stream that also prints a bare `sat` — Z3
  ## answers a refused command with `(error …)` on stdout and still answers the
  ## following `(check-sat)` (calcDynamicTimeoutCore incident) — lands on
  ## `sosUnknown`, never on `sosSat`. Clean streams are byte-identical: the
  ## gate sits on the SAT mint only.
  for line in raw.splitLines():
    let trimmed = line.strip()
    if trimmed.len == 0:
      continue
    if trimmed.startsWith("("):
      continue
    let lower = trimmed.toLowerAscii()
    if lower == "unsat":
      return sosUnsat
    if lower == "sat":
      if solverResponse(raw) == srSat:
        return sosSat
      return sosUnknown
    if lower == "unknown":
      return sosUnknown
    if lower.contains("timeout"):
      return sosTimeout
    if lower.contains("resource"):
      return sosResourceLimit
    if trimmed.startsWith("(error") or trimmed.startsWith("error"):
      continue
  result = sosUnknown
  if elapsedMs >= timeoutMs:
    result = sosTimeout

func extractCertificate(raw: string): string {.raises: [].} =
  var depth = 0
  var statusEnd = -1
  var exprStart = -1
  var i = 0
  while i < raw.len:
    let c = raw[i]
    if c == '(':
      if depth == 0:
        if exprStart < 0:
          exprStart = i
      inc depth
    elif c == ')':
      if depth > 0:
        dec depth
        if depth == 0 and exprStart >= 0:
          if statusEnd >= 0:
            let expr = raw[exprStart .. i]
            # `(error ...)` — Z3's reply to `(get-model)` after `unsat` — is
            # never an inductive-property certificate (S4 capture keeps the
            # UNSAT path byte-identical).
            if not expr.startsWith("(error"):
              return expr
          exprStart = -1
    elif depth == 0:
      if statusEnd < 0 and (c == 'u' or c == 's'):
        var j = i
        while j < raw.len and raw[j] notin {' ', '\n', '\r', '\t'}:
          inc j
        let tok = raw[i ..< j]
        if tok.toLowerAscii() in ["unsat", "sat"]:
          statusEnd = j
          exprStart = -1
    inc i
  ""

proc runZ3CheckViaIR*(funcDef: IRFuncDef, phase: SmtPhase = spBmc;
    canonicalEnvelopeDigest: var string; transportPayloadDigest: var string): SolverOutcome {.gcsafe, raises: []} =
  let smtScript = irToSmtScript(funcDef)
  if smtScript.len == 0:
    return SolverOutcome(status: sosUnknown)
  try:
    let budget = getBudgetFor(phase)
    let res = z3ExecPersistent(smtScript, timeoutMs = budget.timeoutMs,
      canonicalEnvelopeDigest = canonicalEnvelopeDigest, transportPayloadDigest = transportPayloadDigest)
    if res.isOk:
      let output = res.get()
      let status = classifyZ3Output(output, 0, budget.timeoutMs)
      result.status = status
      if status == sosUnsat:
        let cert = extractCertificate(output)
        if cert.len > 0:
          result.certificate.predicateInvariants[canonicalStateRelationKey] = cert
      if status == sosSat:
        # S4: concrete assignments from the `(get-model)` reply.
        result.modelBindings = parseSatModelBindings(output)
      result.certificate.solverMetadata = output
      result.diagnostics = output
    else:
      result.status = sosProcessError
      result.diagnostics = res.error()
  except CatchableError:
    result.status = sosProcessError

proc runZ3CheckViaIR*(smtScript: string, phase: SmtPhase = spBmc;
    canonicalEnvelopeDigest: var string; transportPayloadDigest: var string): SolverOutcome {.gcsafe, raises: []} =
  if smtScript.len == 0:
    return SolverOutcome(status: sosUnknown)
  try:
    let budget = getBudgetFor(phase)
    let res = z3ExecPersistent(smtScript, timeoutMs = budget.timeoutMs,
      canonicalEnvelopeDigest = canonicalEnvelopeDigest, transportPayloadDigest = transportPayloadDigest)
    if res.isOk:
      let output = res.get()
      let status = classifyZ3Output(output, 0, budget.timeoutMs)
      result.status = status
      if status == sosUnsat:
        let cert = extractCertificate(output)
        if cert.len > 0:
          result.certificate.predicateInvariants[canonicalStateRelationKey] = cert
      if status == sosSat:
        # S4: concrete assignments from the `(get-model)` reply.
        result.modelBindings = parseSatModelBindings(output)
      result.certificate.solverMetadata = output
      result.diagnostics = output
    else:
      result.status = sosProcessError
      result.diagnostics = res.error()
  except CatchableError:
    result.status = sosProcessError

proc evidenceVerdict*(model: VerificationModel; ce: CandidateEvidence; z3Path: string; timeoutMs: int): VerificationResult {.raises: [].} =
  let validator = newEvidenceValidator(z3Path, timeoutMs)
  let validated = validator.validate(model, ce)
  let overall = validated.overall
  # P4 I3 binding: a SAT counterexample is only a DISPROVED verdict once the
  # candidate witness is semantically re-validated against the model. A raw
  # candidate without an explicit solver model (or without a model string) is
  # left as rkCandidateCounterexample (Inconclusive) — never promoted without
  # a genuine witness. This is the anti-theater admission for DISPROVED.
  if overall.status == vsInconclusive and overall.reason == rkCandidateCounterexample and ce.model.len > 0:
    let cx = newCounterexampleValidator(z3Path, timeoutMs)
    let cv = validateCounterexample(cx, model, ce, z3Path, timeoutMs)
    var promoted = finalizeVerdict(overall, cv)
    # S4: exact solver model carriage — the promoted disproof must carry the
    # raw solver output (incl. the `(get-model)` reply) so the downstream
    # replay adapter can recover the concrete assignment. Metadata only.
    promoted.model = ce.model
    return promoted
  overall

func classifySmtLogic*(f: IRFuncDef): SmtLogic {.axiomDecision(
     id = "DECISION-0020",
     reason = "Select SMT logic (QF_BV/QF_AUFBV) based on function's IR type profile — no side effects, pure type-level dispatch",
     adr = "docs/spec/ir_pipeline_integration.md",
     introduced = "v32"), raises: [].} =
  if hasListType(f.retType):
    return slQfAufbv
  for p in f.params:
    if hasListType(p.ty):
      return slQfAufbv
  if bodyContainsListType(f.body):
    return slQfAufbv
  slQfBv

func findLoopExpr(e: IRExpr): IRExpr {.raises: [].} =
  ## Return the first irLoop node in the expression tree, or nil.
  if e == nil: return nil
  if e.kind == irLoop: return e
  case e.kind
  of irLet:
    let v = findLoopExpr(e.letVal)
    if v != nil: return v
    return findLoopExpr(e.letBody)
  of irIf:
    let c = findLoopExpr(e.ifCond)
    if c != nil: return c
    let t = findLoopExpr(e.ifThen)
    if t != nil: return t
    return findLoopExpr(e.ifElse)
  of irBinOp:
    let l = findLoopExpr(e.binLhs)
    if l != nil: return l
    return findLoopExpr(e.binRhs)
  of irUnaryOp:
    return findLoopExpr(e.unaryArg)
  of irCall:
    for a in e.callArgs:
      let r = findLoopExpr(a)
      if r != nil: return r
  of irRecCall:
    for a in e.recArgs:
      let r = findLoopExpr(a)
      if r != nil: return r
  of irCase:
    let s = findLoopExpr(e.caseScrutinee)
    if s != nil: return s
    for b in e.caseBranches:
      let r = findLoopExpr(b.body)
      if r != nil: return r
    return findLoopExpr(e.caseDefault)
  of irCast:
    return findLoopExpr(e.castExpr)
  of irLit, irFloatLit, irVar, irStringLit, irLoop:
    return nil

func contractFromFuncDef*(funcDef: IRFuncDef): ContractInfo {.raises: [].} =
  ## Pipeline-boundary extraction of the funcDef's semantic contract into the
  ## CHC layer's shallow ContractInfo. The CHC layer (ir_loop_to_horn) must NOT
  ## import IRFuncDef — this func is the decoupling seam.
  ContractInfo(
    preConditions: funcDef.preConditions,
    postConditions: funcDef.postConditions
  )

func lowerPostconditionModel*(funcDef: IRFuncDef; contract: ContractInfo): Option[VerificationModel] {.raises: [].} =
  ## C20 — the BMC route's VerificationModel for NON-loop postconditions.
  ## `lowerLoopToTransition` (loop_transition_lowering) is the loop precedent;
  ## this is its straight-line counterpart: one-state model whose entry binds
  ## every parameter to itself and `result` to the actual IR body, an identity
  ## transition (frame condition), and the contract's postconditions as the
  ## exit property. The discharge (evidenceVerdict → EvidenceValidator) then
  ## decides the verdict from the solver's raw output — Z3 UNSAT alone can
  ## never produce Proved (the evidence gate requires non-empty candidate
  ## evidence plus all three obligation families), and Z3 cannot mint a KAA,
  ## so the VDA's verified-verdict authority stays out of reach by
  ## construction (verification_decision_authority.nim:105-107).
  ##
  ## none = not modelable here (loop present — the CHC lane owns loops, or no
  ## postcondition property) → the caller keeps the fail-closed verdict.
  if funcDef.body == nil or findLoopExpr(funcDef.body) != nil:
    return none(VerificationModel)
  var property: IRExpr = nil
  for post in contract.postConditions:
    if post != nil:
      if property == nil:
        property = post
      else:
        property = IRExpr(kind: irBinOp, binOp: boAnd, binLhs: property,
                          binRhs: post, typ: irTypeBool())
  if property == nil:
    return none(VerificationModel)
  var sem = VMSemantic()
  for p in funcDef.params:
    let origin = if funcDef.symbolTable.hasSymbol(p.name):
      funcDef.symbolTable.getSymbol(p.name).origin
    else:
      SymbolOrigin(kind: sokImplicit)
    sem.initState(p.name, p.ty, origin)
    sem.initExprs.add(IRExpr(kind: irVar, varName: p.name, varType: p.ty, typ: p.ty))
  # The result state var IS the computed return value: its entry expression is
  # the actual body, so the discharge reasons about the real computation.
  let resultOrigin = if funcDef.symbolTable.hasSymbol("result"):
    funcDef.symbolTable.getSymbol("result").origin
  else:
    SymbolOrigin(kind: sokImplicit)
  sem.initState("result", funcDef.retType, resultOrigin)
  sem.initExprs.add(funcDef.body)
  # Identity entry→exit edge: every state var frames (C5.1 golden semantics),
  # the computation already happened in the init.
  sem.initTransition(NodeId(1), NodeId(2), nil, ParallelUpdate())
  sem.logicalDomain = ldBitVec
  sem.resultStateName = some("result")
  sem.property = some(property)
  some(VerificationModel(
    semantic: sem,
    metadata: VMMetadata(
      functionExit: NodeId(0),
      symbolMap: funcDef.symbolTable,
      sourceLocation: "",
      resultStateName: sem.resultStateName
    )
  ))

func derivePipelineClaim(funcDef: IRFuncDef; solverStatus: coreSolverTypes.SolverStatus): VerifiedClaim {.raises: [].} =
  ## Phase-4a: Evidence->Claim (first production deriveClaim caller).
  ## proofSignal is derived from the solver status; the claim is derived from the
  ## captured evidence. Downstream (writer) is projection-only — it never re-derives.
  let bundle = captureEvidence(funcDef, soCanonicalDerived, "v1")
  let signal = case solverStatus
    of coreSolverTypes.solverUnsat: psUnsat
    of coreSolverTypes.solverSat: psCounterexample
    else: psUnknown
  var ctx = ClaimContext(
    subjectId: funcDef.name, sourceIdentity: "",
    specification: bundle.specificationArtifact,
    semanticProfileId: SemanticProfileV1Hash,
    obligationGenerated: funcDef.postConditions.len > 0,
    supported: true,
    dependenciesSatisfied: true,
    proofSignal: signal,
    evidenceBundle: bundle,
    policyId: "apV1"
  )
  deriveClaim(ctx, apV1)

proc runIrPipeline*(ve: ValidatedIrEntry,
                     lspClient: LeanLspClient = nil,
                     policy: BackendPolicy = bpRequire,
                     subjectRepoRoot: string = ""): IrPipelineResult {.raises: [].} =
  ## Run the full IR pipeline for a single validated entry.
  ## W4-B: Uses cached funcDef from ValidatedIrEntry (no re-deserialization).
  ## Returns success=false if any stage fails (sentinel: funcDef.name.len == 0).
  ## AGENT-L: Defense-in-depth Defect isolation wall at pipeline boundary.
  let entry = ve.entry
  var funcDef = ve.funcDef
  # DEBT#423: obligation-attempted count accumulator. Populated immediately
  # after obligation generation; every post-generation exit (including the
  # TheaterGuard and the defect/error guards) reports this count instead of
  # silently zeroing it on early-return paths.
  var generatedObligationCount = 0
  try:
    if funcDef.name.len == 0:
      return IrPipelineResult(
        funcName: entry.name, modulePath: entry.sourcePath,
        success: false, verification: vrt.makeInconclusive(vrt.rkNoProperty),
        provenance: vpNone, complexity: 0.0,
        backend: vbCanonicalChc, actualBackend: vbCanonicalChc,
        fallbackOccurred: false, fallbackReason: "",
        requestedBackend: vbCanonicalChc, selectedBackend: vbCanonicalChc)
    let fnComplexity = computeCyclomaticComplexity(funcDef)

    # ── Stage 0b: Contract Synthesis ────────────────────────────────────────
    # Populate preConditions/postConditions from IR body analysis. Previously
    # postConditions was ALWAYS empty (convertFuncDef never sets it), so
    # irToSmtScript returned "" → vpBmcSkipped with no Z3 query and no Lean
    # theorem. Synthesizing here (single point before SMT/Lean generation)
    # lets int clamp kernels like clampTimeoutMs emit a real postcondition.
    synthesizeContracts(funcDef)

    # ── P3: Obligation Generation ───────────────────────────────────
    # Generate canonical obligations once per function at the pipeline
    # entry point. The result drives downstream routing:
    #   ogrGenerated       → continue to SMT/Lean/Z3 pipeline
    #   ogrNoApplicableObligation → vsNoObligation (proven absence)
    #   ogrUnsupported     → rkObligationUnsupported (backend cannot encode)
    #   ogrIllFormed       → rkObligationIllFormed (semantic validation failure)
    let scopePolicy = defaultScopePolicy()
    let ogr = generateCanonicalObligations(funcDef, scopePolicy)
    case ogr.kind
    of ogrNoApplicableObligation:
      # Proven absence of obligations — distinct from "not encodable".
      # Reuse vsNoObligation (existing enum) with a new reason string
      # so downstream telemetry can distinguish "no obligation exists"
      # from "obligation exists but backend cannot encode it".
      return IrPipelineResult(
        funcName: entry.name, modulePath: entry.sourcePath,
        irDigest: computeDeterministicCasKey(computeIrDigest(funcDef)),
        verification: vrt.deriveVerdict(vsNoObligation, rkNoObligation, tkCompleted, smNone, pkNone, psUnbounded),
        provenance: vpNone,
        success: true, skipped: true,
        crossValidation: CrossValidationResult(consistent: false),
        complexity: fnComplexity,
        backend: vbCanonicalChc, actualBackend: vbCanonicalChc,
        fallbackOccurred: false, fallbackReason: "",
        requestedBackend: vbCanonicalChc, selectedBackend: vbCanonicalChc,
        obligationVerdict: ObligationVerdictInfo(
          kind: ogrNoApplicableObligation,
          reason: "semanticNoApplicable",
          obligationCount: 0))
    of ogrUnsupported:
      return IrPipelineResult(
        funcName: entry.name, modulePath: entry.sourcePath,
        irDigest: computeDeterministicCasKey(computeIrDigest(funcDef)),
        verification: vrt.makeInconclusive(rkObligationUnsupported),
        provenance: vpNone,
        success: false, skipped: false,
        crossValidation: CrossValidationResult(consistent: false),
        complexity: fnComplexity,
        backend: vbCanonicalChc, actualBackend: vbCanonicalChc,
        fallbackOccurred: false, fallbackReason: "",
        requestedBackend: vbCanonicalChc, selectedBackend: vbCanonicalChc,
        obligationVerdict: ObligationVerdictInfo(
          kind: ogrUnsupported,
          reason: $ogr.unsupportedReason,
          obligationCount: 0))
    of ogrIllFormed:
      return IrPipelineResult(
        funcName: entry.name, modulePath: entry.sourcePath,
        irDigest: computeDeterministicCasKey(computeIrDigest(funcDef)),
        verification: vrt.makeInconclusive(rkObligationIllFormed),
        provenance: vpNone,
        success: false, skipped: false,
        crossValidation: CrossValidationResult(consistent: false),
        complexity: fnComplexity,
        backend: vbCanonicalChc, actualBackend: vbCanonicalChc,
        fallbackOccurred: false, fallbackReason: "",
        requestedBackend: vbCanonicalChc, selectedBackend: vbCanonicalChc,
        obligationVerdict: ObligationVerdictInfo(
          kind: ogrIllFormed,
          reason: $ogr.illFormedReason,
          obligationCount: 0))
    of ogrGenerated:
      # Obligations generated — continue to SMT/Lean/Z3 pipeline.
      # The obligation count is recorded for downstream telemetry.
      # S1-A: Attempt canonical Lean-backed verification first.
      # If the kernel accepts the obligation theorem, use that as the
      # pipeline result (genuine verified). Otherwise, fall through
      # to the existing SMT/Lean/Z3 pipeline.
      let canonicalResult = executeCanonicalVerification(
        funcDef, entry.sourcePath, entry.name, entry.sourceContent,
        subjectRepoRoot = subjectRepoRoot,
        # §2.1a completeness anchor: the materializer saves the CompletenessEvidence
        # artifact against the PRE-synthesis funcDef (ve.funcDef — value-copied, the
        # synthesizeContracts mutation at :439 touches only `funcDef`), while the
        # canonical path sees the post-synthesis one. Same deterministic two-anchor
        # evidence search the runner performs at :982-997 — never AST re-interpretation.
        preSynthesisIrDigest = computeDeterministicCasKey(serializeIRFuncDef(ve.funcDef)),
        parseBound = ve.parseBound
      )
      if canonicalResult.success:
        # Genuine Lean kernel acceptance. Dual evidence is claimed ONLY when
        # the Z3 leg actually ran in THIS execution on the SAME proposition
        # the Lean theorem states: `okContractPost`. `obligations[0]` is the
        # division-safety guard (kind ordinal order), so lowering it here
        # would bind the certificate to a different proposition — theater,
        # not dual verification. An absent/refused/non-unsat Z3 leg leaves
        # the honest Lean-only result untouched (fail-closed).
        var dualSmtScript = ""
        var dualZ3Sat = false
        var dualDetail = "no okContractPost obligation"
        if ogr.kind == ogrGenerated:
          let dualSmtLogic = classifySmtLogic(funcDef)
          let irDigestPreInline = computeDeterministicCasKey(serializeIRFuncDef(ve.funcDef))
          var completeness = loadEvidenceArtifact(irDigestPreInline).get(
            default(CompletenessEvidence))
          var instWitnesses = loadInstantiationWitnesses(irDigestPreInline)
          if not completeness.translationLossFree or instWitnesses.isNone:
            let irDigestCurrent = computeDeterministicCasKey(serializeIRFuncDef(funcDef))
            let altCompleteness = loadEvidenceArtifact(irDigestCurrent)
            let altWitnesses = loadInstantiationWitnesses(irDigestCurrent)
            if altCompleteness.isSome:
              completeness = altCompleteness.get
            if altWitnesses.isSome:
              instWitnesses = altWitnesses
          if not completeness.translationLossFree or
              not completeness.bindingUniverseComplete:
            dualDetail = "completeness evidence not measured for this subject"
          else:
            # The canonical Lean artifact proves every postcondition of the
            # synthesized contract; the classic SMT emitter conjoins exactly
            # those postconditions (asserted preconditions include the
            # division guard) against the same body. The typed obligation
            # lowerer cannot express an `irIf` body and would refuse this
            # subject, so the canonical script is the same-proposition leg.
            # `includeOverflowDefines=false` is deliberate: the Lean theorem is
            # over Int and states no BV no-overflow goal. Conjoining one would
            # make the Z3 query a strictly stronger proposition than the KAA
            # proved (measured: the i+1 goal is SAT at i=2^63-1), so dual
            # evidence would be claimed for a proposition Lean never accepted.
            let dualScript = irToSmtScript(funcDef,
              includeOverflowDefines = false, logic = dualSmtLogic)
            if dualScript.len == 0:
              dualDetail = "classic SMT emitter refused the contract"
            else:
              var ceDigest, tpDigest: string
              let outcome = runZ3CheckViaIR(dualScript & '\n' & "(get-model)",
                phase = spBmc, canonicalEnvelopeDigest = ceDigest,
                transportPayloadDigest = tpDigest)
              if outcome.status == sosUnsat:
                dualSmtScript = dualScript
                dualZ3Sat = true
                dualDetail = "z3 unsat"
              else:
                dualDetail = "z3 " & $outcome.status
        if not dualZ3Sat:
          logWarn("ir_pipeline_runner", "[dual-declined] " & entry.name &
            " — " & dualDetail & " (Lean KAA remains lean-only)")
        return IrPipelineResult(
          funcName: entry.name,
          modulePath: entry.sourcePath,
          irDigest: computeDeterministicCasKey(computeIrDigest(funcDef)),
          smtScript: dualSmtScript,
          leanSource: canonicalResult.leanSourceHash,
          crossValidation: CrossValidationResult(consistent: false),
          z3Sat: dualZ3Sat,
          verification: vrt.deriveVerdict(vsProved, rkNone, tkCompleted,
            (if dualZ3Sat: smBMC else: smNone),
            (if dualZ3Sat: pkDual else: pkLean), psBounded),
          provenance: (if dualZ3Sat: vpDual else: vpTypeLevelEncoding),
          success: true,
          skipped: false,
          complexity: fnComplexity,
          backend: vbCanonicalChc,
          actualBackend: vbCanonicalChc,
          fallbackOccurred: false,
          fallbackReason: "",
          requestedBackend: vbCanonicalChc,
          selectedBackend: vbCanonicalChc,
          obligationVerdict: ObligationVerdictInfo(
            kind: ogrGenerated,
            reason: "canonicalVerified",
            obligationCount: generatedObligationCount),
          evidence: canonicalResult.canonicalEvidence)
      # §0.9 (no silent discard): the canonical path DECLINED for this funcDef.
      # The declined result carries the exact refusal point (sealError — the
      # §2.1a binding component that was unmeasurable — or the kernel-check
      # outcome). Dropping it here would leave the failure cause unattributable
      # while the pipeline silently falls through to BMC, so the decline and its
      # reason are surfaced before the fall-through (DEBT#465 attribution
      # addendum: the canonical-I6 pre-kernel decline was previously discarded
      # with no kernel-check dump or log record).
      var decline = "[canonical-declined] " & entry.name & " — evidence=" &
        canonicalResult.evidence
      if canonicalResult.sealError.len > 0:
        decline.add(" sealError=" & canonicalResult.sealError)
      logWarn("ir_pipeline_runner", decline)

    # DEBT#423: from this point forward every return must preserve the count —
    # early-return paths (BMC pre-check, CHC loops, tautology, admission, legacy
    # encoder, type-level fast-path, TheaterGuard) must NOT report 0 for
    # obligations that were actually generated.
    generatedObligationCount = len(ogr.obligations.value)

    # Phase-2 Evidence Capture: capture the (already-synthesized) postconditions as
    # an immutable SpecificationArtifact + DependencySnapshot + minimal SolverEvidence
    # via a pure collector. This is a local, side-effect-free capture — it does NOT
    # decide PROVED/assurance/cert/VKD (Claim Authority). The bundle is retained only
    # in-memory (internal accumulator); it is NOT threaded as a pipeline DTO and is
    # NOT serialized to certificates in this phase.
    discard captureEvidence(funcDef, soCanonicalDerived, "v1")

    # Contract must be captured AFTER Stage 0b so synthesized postconditions
    # (populated by synthesizeContracts) are threaded into the CHC bridge.
    let contract = contractFromFuncDef(funcDef)

    # ── Stage 0: BMC-Skip Pre-Check ────────────────────────────────────────
    # Functions with string return types or IEEE-754 float operations cannot
    # be verified via QF_BV (quantifier-free bitvector) BMC. The SMT-LIB2
    # FloatingPoint theory requires QF_FP; the Strings theory requires
    # QF_SLIA. Our pipeline uses QF_BV exclusively, so these types are
    # unsupported. Return vpBmcSkipped → psSkip (not vpFail/psError).
    #
    # SSOT: use the compile-time `entry.bmcSkippable` field (computed by
    # isBmcSkippable on the macro-time convertFuncDef IR) rather than
    # re-evaluating on the deserialized funcDef — the two IR representations
    # can disagree on string-literal detection, which would skip kernel-scope
    # symbols that collectKernelSymbols already admitted (bmcSkippable=false).
    if ve.entry.bmcSkippable:
      logInfo("ir_pipeline_runner",
        "[runIrPipeline] BMC skip: " & entry.name &
        " — retType=" & $funcDef.retType.kind &
        " (float/string not representable in QF_BV)")
      return IrPipelineResult(
        funcName: entry.name,
        modulePath: entry.sourcePath,
        irDigest: computeDeterministicCasKey(computeIrDigest(funcDef)),
        verification: vrt.makeInconclusive(vrt.rkNoProperty),
        provenance: vpBmcSkipped,
        success: true,
        skipped: true,
        crossValidation: CrossValidationResult(consistent: false),
        complexity: fnComplexity,
        backend: vbCanonicalChc,
        actualBackend: vbCanonicalChc,
        fallbackOccurred: false,
        fallbackReason: "",
        requestedBackend: vbCanonicalChc,
        selectedBackend: vbCanonicalChc,
        obligationVerdict: generatedObligationVerdict(generatedObligationCount))

    # ── T4: Tier Classification ──────────────────────────────────────────────────
    let tierInfo = classifyFunction(funcDef)
    logInfo("ir_pipeline_runner", "[classify] " & entry.name & " → " & $tierInfo.tier & " (" & tierInfo.reason & ")")

    # ── T4a: Loop BMC Soundness Gate ────────────────────────────────────
    # Fixed-depth unroll (irLoopBmcBound=10, ir_to_smt.nim:28) is an
    # under-approximation: UNSAT-at-depth-N proves nothing for loops that may
    # exceed N iterations. Tier-2 loops reach SMT ONLY when a static upper bound
    # is resolved AND <= 10; otherwise honest skip (docs/spec/loop_bmc_soundness.md).
    if tierInfo.tier == vtStructural and bodyHasLoop(funcDef.body):
      let loopExpr = findLoopExpr(funcDef.body)
      if loopExpr != nil:
        # C13: canonical backend is attempted first. `buildChcFromLoop` returns
        # an explicit classification — a bare nothing must never drop into the
        # legacy encoder silently (that is theater, §0.9).
        let chcBuild = buildChcFromLoop(loopExpr, funcDef.symbolTable, contract)
        if chcBuild.kind == cbSuccess:
          let chcScript = chcBuild.program
          var chcCanonicalDigest, chcTransportDigest: string
          let chcOutcome = runZ3CheckViaIR(chcScript, phase = spBmc,
            canonicalEnvelopeDigest = chcCanonicalDigest, transportPayloadDigest = chcTransportDigest)
          let chcCe = toCandidateEvidence(chcOutcome)
          let loopModel = lowerLoopToTransition(loopExpr, funcDef.symbolTable, contract)
          let chcResult = if loopModel.isSome:
            evidenceVerdict(loopModel.get, chcCe, "z3", getBudgetFor(spBmc).timeoutMs)
          else:
            makeInconclusive(rkEvidenceRejected)
          if vrt.isUnboundedProved(chcResult):
            logInfo("ir_pipeline_runner",
              "[loop-chc-vm] " & entry.name & " — inductive loop verified via CHC/Spacer (VerificationModel route), backend=" & $vbCanonicalChc)
            let (selBackend, fbOccurred, fbReason) = selectBackend(policy, true)
            var r = IrPipelineResult(
              funcName: entry.name,
              modulePath: entry.sourcePath,
              irDigest: computeDeterministicCasKey(computeIrDigest(funcDef)),
              smtScript: chcScript,
              leanSource: "",
              crossValidation: CrossValidationResult(consistent: false),
              z3Sat: true,
              verification: chcResult,
              provenance: vpInductiveLoop,
              success: true,
              requestedBackend: vbCanonicalChc,
              selectedBackend: selBackend,
              actualBackend: selBackend,
              fallbackOccurred: fbOccurred,
              fallbackReason: fbReason,
              complexity: fnComplexity,
              obligationVerdict: generatedObligationVerdict(generatedObligationCount)
            )
            r.backend = vbCanonicalChc
            return r
          # Canonical CHC did not prove the loop.
          logInfo("ir_pipeline_runner",
            "[loop-chc-vm] " & entry.name & " — CHC/Spacer via VerificationModel did not prove loop (backend=" & $vbCanonicalChc & ")")
          if policy == bpRequire:
            # Fail-closed: no implicit legacy fallback.
            logInfo("ir_pipeline_runner",
              "[loop-chc-vm] " & entry.name & " — bpRequire: canonical CHC did not prove loop; refusing silent legacy fallback")
            let (selBackend, fbOccurred, fbReason) = selectBackend(policy, false)
            return IrPipelineResult(
              funcName: entry.name,
              modulePath: entry.sourcePath,
              irDigest: computeDeterministicCasKey(computeIrDigest(funcDef)),
              verification: makeInconclusive(rkEvidenceRejected),
              provenance: vpNone,
              success: false,
              crossValidation: CrossValidationResult(consistent: false),
              backend: vbCanonicalChc,
              actualBackend: vbCanonicalChc,
              fallbackOccurred: fbOccurred,
              fallbackReason: fbReason,
              requestedBackend: vbCanonicalChc,
              selectedBackend: selBackend,
              complexity: fnComplexity,
              obligationVerdict: generatedObligationVerdict(generatedObligationCount)
            )
          # bpAllowFallback: fall through to legacy encoder.
          # Admission gate: only route to legacy if the obligation is
          # admitted for a runnable backend (bkChc is the sole executable
          # backend; bkBmc has no executor wired — routing to it would
          # be theater per §0.9).
          let admission = admissionDecision(loopModel.get, policy)
          if not admission.permitted:
            logInfo("ir_pipeline_runner",
              "[loop-chc-vm] " & entry.name & " — admission declined: " & admission.reason)
            return IrPipelineResult(
              funcName: entry.name,
              modulePath: entry.sourcePath,
              irDigest: computeDeterministicCasKey(computeIrDigest(funcDef)),
              verification: makeInconclusive(rkEvidenceRejected),
              provenance: vpNone,
              success: false,
              crossValidation: CrossValidationResult(consistent: false),
              backend: vbCanonicalChc,
              actualBackend: vbCanonicalChc,
              fallbackOccurred: false,
              fallbackReason: "",
              requestedBackend: vbCanonicalChc,
              selectedBackend: vbCanonicalChc,
              complexity: fnComplexity,
              obligationVerdict: generatedObligationVerdict(generatedObligationCount))
          logInfo("ir_pipeline_runner",
            "[loop-chc-vm] " & entry.name & " — bpAllowFallback: routing to legacy CHC encoder")
        else:
          # Canonical CHC declined (not encodable/unsupported).
          logInfo("ir_pipeline_runner",
            "[loop-chc-vm] " & entry.name & " — canonical CHC declined: " & chcBuildMessage(chcBuild))
          if policy == bpRequire:
            # Fail-closed: no implicit legacy fallback.
            logInfo("ir_pipeline_runner",
              "[loop-chc-vm] " & entry.name & " — bpRequire: canonical CHC declined; refusing silent legacy fallback")
            let (selBackend, fbOccurred, fbReason) = selectBackend(policy, false)
            # Distinguish a genuinely vacuous function (nothing to prove —
            # cnaNoObligations) from one that HAS an obligation but the canonical
            # CHC encoder could not encode/discharge it. Both short-circuit under
            # bpRequire, but they carry different semantics (§0.9 Anti-Theater:
            # "no obligations" must never be conflated with "cannot prove").
            let reason = if chcBuild.kind == cbNotApplicable and
                            chcBuild.notApplicableReason == cnaNoObligations:
              makeNoObligation()
            else:
              makeNotEncodable()
            return IrPipelineResult(
              funcName: entry.name,
              modulePath: entry.sourcePath,
              irDigest: computeDeterministicCasKey(computeIrDigest(funcDef)),
              verification: reason,
              provenance: vpBmcSkipped,
              success: true,
              skipped: true,
              crossValidation: CrossValidationResult(consistent: false),
              backend: vbCanonicalChc,
              actualBackend: vbCanonicalChc,
              fallbackOccurred: fbOccurred,
              fallbackReason: fbReason,
              requestedBackend: vbCanonicalChc,
              selectedBackend: selBackend,
              complexity: fnComplexity,
              obligationVerdict: generatedObligationVerdict(generatedObligationCount)
             )
          # bpAllowFallback: fall through to legacy encoder.
          # Admission gate: only route to legacy if the obligation is
          # admitted for a runnable backend (bkChc is the sole executable
          # backend; bkBmc has no executor wired — routing to it would
          # be theater per §0.9).
          let loopModel2 = lowerLoopToTransition(loopExpr, funcDef.symbolTable, contract)
          let admission2 = if loopModel2.isSome:
            admissionDecision(loopModel2.get, policy)
          else:
            (false, vbCanonicalChc, "not-admitted: cannot lower loop to transition model")
          if not admission2.permitted:
            logInfo("ir_pipeline_runner",
              "[loop-chc-vm] " & entry.name & " — admission declined: " & admission2.reason)
            return IrPipelineResult(
              funcName: entry.name,
              modulePath: entry.sourcePath,
              irDigest: computeDeterministicCasKey(computeIrDigest(funcDef)),
              verification: makeInconclusive(rkEvidenceRejected),
              provenance: vpNone,
              success: false,
              crossValidation: CrossValidationResult(consistent: false),
              backend: vbCanonicalChc,
              actualBackend: vbCanonicalChc,
              fallbackOccurred: false,
              fallbackReason: "",
              requestedBackend: vbCanonicalChc,
              selectedBackend: vbCanonicalChc,
              complexity: fnComplexity,
              obligationVerdict: generatedObligationVerdict(generatedObligationCount))
          logInfo("ir_pipeline_runner",
            "[loop-chc-vm] " & entry.name & " — bpAllowFallback: routing to legacy CHC encoder")
        # === Legacy encoder path (only reached under bpAllowFallback) ===
        let model = buildChcTransitionSystem(loopExpr, funcDef.symbolTable, useIntSort = true)
        case model.kind
        of cmBuilt:
          let property = buildChcProperty(funcDef, loopExpr, model, funcDef.symbolTable)
          case property.kind
          of cpBuilt:
            var lines: seq[string] = @[]
            lines.add(model.prelude)
            if property.postDeclarations.len > 0:
              lines.add(property.postDeclarations)
            lines.add(model.stateRel)
            lines.add("(declare-rel error ())")
            lines.add(model.initRule)
            lines.add(model.transRule)
            lines.add(property.propertyRule)
            lines.add(property.queryCmd)
            lines.add("(check-sat)")
            let fullScript = lines.join("\n")
            var chcCanonicalDigest, chcTransportDigest: string
            let chcOutcome = runZ3CheckViaIR(fullScript, phase = spBmc,
              canonicalEnvelopeDigest = chcCanonicalDigest, transportPayloadDigest = chcTransportDigest)
            let chcCe = toCandidateEvidence(chcOutcome)
            let legacyModel = lowerLoopToTransition(loopExpr, funcDef.symbolTable, contract)
            let chcResult = if legacyModel.isSome:
              evidenceVerdict(legacyModel.get, chcCe, "z3", getBudgetFor(spBmc).timeoutMs)
            else:
              makeInconclusive(rkEvidenceRejected)
            if vrt.isUnboundedProved(chcResult):
              logInfo("ir_pipeline_runner",
                "[loop-chc] " & entry.name & " — inductive loop verified via CHC/Spacer (legacy backend)")
              let (selBackend, fbOccurred, fbReason) = selectBackend(policy, false)
              var r = IrPipelineResult(
                funcName: entry.name,
                modulePath: entry.sourcePath,
                irDigest: computeDeterministicCasKey(computeIrDigest(funcDef)),
                smtScript: fullScript,
                leanSource: "",
                crossValidation: CrossValidationResult(consistent: false),
                z3Sat: true,
                verification: chcResult,
                provenance: vpInductiveLoop,
                success: true,
                requestedBackend: vbCanonicalChc,
                selectedBackend: selBackend,
                actualBackend: selBackend,
                fallbackOccurred: fbOccurred,
                fallbackReason: fbReason,
                complexity: fnComplexity,
                obligationVerdict: generatedObligationVerdict(generatedObligationCount)
              )
              r.backend = vbLegacy
              return r
            logInfo("ir_pipeline_runner",
              "[loop-chc] " & entry.name & " — CHC/Spacer did not prove loop (or counterexample)")
          of cpNoProperty:
            logInfo("ir_pipeline_runner",
              "[loop-chc] " & entry.name & " — no postcondition — CHC property not built")
            let (selBackend, fbOccurred, fbReason) = selectBackend(policy, false)
            return IrPipelineResult(
              funcName: entry.name,
              modulePath: entry.sourcePath,
              irDigest: computeDeterministicCasKey(computeIrDigest(funcDef)),
              verification: makeNoProperty(),
              provenance: vpNone,
              success: true,
              skipped: true,
              crossValidation: CrossValidationResult(consistent: false),
              backend: vbLegacy,
              actualBackend: vbLegacy,
              fallbackOccurred: fbOccurred,
              fallbackReason: fbReason,
              requestedBackend: vbCanonicalChc,
              selectedBackend: selBackend,
              complexity: fnComplexity,
              obligationVerdict: generatedObligationVerdict(generatedObligationCount)
            )
        of cmNotEncodable:
          logInfo("ir_pipeline_runner",
            "[loop-chc] " & entry.name & " — loop not CHC-encodable (" & model.notEncodableReason & ")")
      else:
        logInfo("ir_pipeline_runner",
          "[loop-chc] " & entry.name & " — no loop expression found")
      if tierInfo.loopBound.isSome:
        logInfo("ir_pipeline_runner",
          "[loop-chc] " & entry.name & " — CHC failed, falling back to BMC (bound=" & $tierInfo.loopBound.get & ")")
      else:
        logInfo("ir_pipeline_runner",
          "[loop-bmc] " & entry.name & " — loop bound unresolved — honest skip (§loop_bmc_soundness)")
        return IrPipelineResult(
          funcName: entry.name,
          modulePath: entry.sourcePath,
          irDigest: computeDeterministicCasKey(computeIrDigest(funcDef)),
          verification: makeNotEncodable(),
          provenance: vpBmcSkipped,
          success: true,
          skipped: true,
          crossValidation: CrossValidationResult(consistent: false),
          complexity: fnComplexity,
          backend: vbCanonicalChc,
          actualBackend: vbCanonicalChc,
          fallbackOccurred: false,
          fallbackReason: "",
          requestedBackend: vbCanonicalChc,
          selectedBackend: vbCanonicalChc,
          obligationVerdict: generatedObligationVerdict(generatedObligationCount)
        )

    # ── T3: Tautology Check ──────────────────────────────────────────────────────
    if funcDef.preConditions.len > 0:
      let tautResult = checkInvariantVacuity(funcDef.preConditions)
      if tautResult == tcTautology:
        logWarn("ir_pipeline_runner", "[tautology] " & entry.name & ": invariant is tautological — REJECT")
        return IrPipelineResult(
          funcName: entry.name,
          modulePath: entry.sourcePath,
          irDigest: computeDeterministicCasKey(computeIrDigest(funcDef)),
          verification: vrt.makeInconclusive(vrt.rkNoProperty),
          provenance: vpBmcSkipped,
          success: false,
          crossValidation: CrossValidationResult(consistent: false),  # no cross-validation ran
          complexity: fnComplexity,
          backend: vbCanonicalChc,
          actualBackend: vbCanonicalChc,
          fallbackOccurred: false,
          fallbackReason: "",
          requestedBackend: vbCanonicalChc,
          selectedBackend: vbCanonicalChc,
          obligationVerdict: generatedObligationVerdict(generatedObligationCount))

    # ── T5: Implication Check ─────────────────────────────────────────────────────
    if funcDef.preConditions.len > 0 and funcDef.postConditions.len > 0:
      let implResult = checkAllImplications(funcDef.preConditions, funcDef.postConditions)
      if implResult == irNotImplied:
        logWarn("ir_pipeline_runner", "[implication] " & entry.name & ": invariant does not imply postcondition")

    # ── Stage 1.5: Type-Level Encoding Fast-Path ──────────────────────────────
    if lspClient != nil:
      {.push warning[BareExcept]: off.}
      try:
        let routerVerdict = routeToTypeLevel(funcDef, lspClient)
        if routerVerdict.compiled:
          logInfo("ir_pipeline_runner",
            "[type-level] " & entry.name & " — type-level encoding compiled; awaiting VerificationModel for evidence validation")
          return IrPipelineResult(
            funcName: entry.name,
            modulePath: entry.sourcePath,
            irDigest: computeDeterministicCasKey(computeIrDigest(funcDef)),
            leanSource: routerVerdict.leanSource,
            crossValidation: CrossValidationResult(consistent: false),  # no SMT→structural cross-validation
            z3Sat: false,
            verification: makeInconclusive(rkEvidenceRejected),
            provenance: vpTypeLevelEncoding,
            success: true,
            complexity: fnComplexity,
            backend: vbCanonicalChc,
            actualBackend: vbCanonicalChc,
            fallbackOccurred: false,
            fallbackReason: "",
            requestedBackend: vbCanonicalChc,
            selectedBackend: vbCanonicalChc,
            obligationVerdict: generatedObligationVerdict(generatedObligationCount))
      except CatchableError as e:
        logWarn("ir_pipeline_runner",
          "LSP route failed (" & e.msg & ") — falling back to standard pipeline")
      {.pop.}
    else:
      if classifyTypeLevel(funcDef):
        logInfo("ir_pipeline_runner",
          "type-level candidate '" & entry.name & "' but no LSP — routed to standard SMT pipeline")
      # Fall through to Stage 2-4 (standard SMT+Lean+Z3 pipeline)

    # ── Stage 2-4: Standard SMT + Lean + Cross-Validation Pipeline ───────────
    # W4-A: Generate each representation exactly once. Build CrossValidationResult
    # inline instead of calling crossValidate(funcDef) which would regenerate both.
    # This eliminates 2x redundant irToSmtScript + irToLeanModule calls per entry.
    let smtLogic = classifySmtLogic(funcDef)
    # W4 overflow semantics are governed by the Semantic Profile (V1), not a hardcoded bool:
    # same build → same IR → same SMT output across every path (pipeline, cross-validation, tests).
    # The V1 VERIFIED profile (spOverflowObligationDischarged) and the nominal bounded
    # profile (spOverflowBounded) both emit the no-overflow goal defines: the 2026-10-07
    # declaration weakening (DEBT#494) is a declaration move only — SMT emission is
    # byte-identical to the pre-weakening pipeline.
    let includeOverflowDefines = GlobalSemanticProfileV1.overflowMode in
      {spOverflowBounded, spOverflowObligationDischarged}
    var smtScript = irToSmtScript(funcDef, includeOverflowDefines = includeOverflowDefines, logic = smtLogic)
    # ── P3 Typed Obligation Lowering (primary path for ogrGenerated) ──
    # When obligations were generated with typed propositions,
    # lower the first obligation's proposition through the typed
    # ProofIR → SMT path. This produces a semantically grounded
    # SMT script from the obligation's typed IRExpr, rather than
    # relying solely on the classic adapter's string-based output.
    # The classic adapter output is kept as the fallback so that
    # the TheaterGuard below correctly fires when typed lowering
    # is unsupported (empty result → fail-closed).
    # ── P3 Obligation Execution Ledger (v10) ──────────────────
    # Capture all generated obligation ids and classify them:
    # exactly ONE golden obligation (the one actually lowered/executed)
    # goes into plans; all other generated ids are recorded as dropped
    # with reason osrDroppedOutsideScope.
    var obligationExec: ObligationExecutionRecord
    var goldenOblId: string
    var goldenOblDerivationRule: string
    var goldenOblLowered: bool
    var goldenOblSemanticOutcome: SemanticOutcome = smOutcomeNotExecuted
    if ogr.kind == ogrGenerated:
      obligationExec.generatedObligationIds = ogr.obligations.value.mapIt(it.id)
      var firstObl = ogr.obligations.value[0]
      # ── S6: synthesized-claim golden-obligation selection ───────────────────
      # For a synthesized claim carrier (the overlay β-composite AND the
      # single-origin carrier — base32 rem / base36 buffer pattern) the
      # contract-post obligation IS the claim (the relational roundtrip or
      # buffer-binding theorem); the div guards are literal tautologies
      # (`179 ≠ 0` / `277 ≠ 0`) whose SMT check can never observe a mutation
      # of the sizing bodies. When the kernel lane could not seal (a
      # kernel-REJECTED subject — the PROPOSITION_DISPROVED direction), the BMC lane must
      # check the CLAIM, so the golden obligation is the okContractPost entry
      # and the overlay domain preconditions are asserted as semantic facts
      # (in-domain counterexamples only — an out-of-domain SAT model would be
      # a wrap artifact, not a bug). Kernel-sealed carriers return upstream
      # before this lane, so the selection change is observable only for
      # kernel-rejected synthesized claims. Single-symbol entries keep the
      # existing selection (zero-diff).
      var domainFacts: seq[SemanticFact] = @[]
      if ve.parseBound.synthesizedComposite:
        for obl in ogr.obligations.value:
          if obl.kind == okContractPost and obl.proposition != nil:
            firstObl = obl
            break
        for pre in funcDef.preConditions:
          if pre == nil:
            continue
          domainFacts.add(SemanticFact(
            id: "s6-composite-domain:" & sha256Hex(serializeIRExpr(pre)),
            proposition: pre,
            provenance: FactProvenance(
              origin: foCompileTimeBinding,
              occurrenceRef: "composite-domain-precondition",
              sourceRef: "")))
      if firstObl.proposition != nil:
        # ── WP4-j.2 Phase D step 4: completeness gate + fact injection ──
        # NOTE: artifact keys are anchored to the PRE-synthesis funcDef
        # (ve.funcDef — the materializer's product) so that save-time and
        # load-time keys agree regardless of synthesizeContracts mutation.
        # ve.funcDef still references the original body; funcDef (var) is
        # the mutated one after synthesizeContracts at :439.
        # WP4-j.4: witness artifacts are saved by the materializer against
        # the PRE-INLINE IR, while the runner cache hashes the INLINED one.
        # Lookup therefore tries both anchors — this is evidence search
        # (deterministic key set), never re-interpretation of the AST.
        let irDigestPreInline = computeDeterministicCasKey(serializeIRFuncDef(ve.funcDef))
        # WP4-j.4: evidence lookup tries both anchors — the materializer saves
        # against the pre-inline IR; the runner cache hashes the inlined one.
        # This is deterministic evidence search, never AST re-interpretation.
        var completeness = loadEvidenceArtifact(irDigestPreInline).get(
          default(CompletenessEvidence))
        var instWitnesses = loadInstantiationWitnesses(irDigestPreInline)
        if not completeness.translationLossFree or instWitnesses.isNone:
          let irDigestCurrent = computeDeterministicCasKey(serializeIRFuncDef(funcDef))
          let altCompleteness = loadEvidenceArtifact(irDigestCurrent)
          let altWitnesses = loadInstantiationWitnesses(irDigestCurrent)
          if altCompleteness.isSome or altWitnesses.isSome:
            if altCompleteness.isSome:
              completeness = altCompleteness.get
            if altWitnesses.isSome:
              instWitnesses = altWitnesses
        let E_all = deriveSemanticFactsFromIR(funcDef)
        var E_safe = filterResolvableFacts(completeness, funcDef, firstObl.proposition, E_all)
        # WP4-j.4 — inject instantiation ladder facts via artifact (witness path).
        var instFacts: seq[SemanticFact] = @[]
        if instWitnesses.isSome:
          for w in instWitnesses.get:
            instFacts.add(deriveInstantiationFacts(w, funcDef))
        E_safe.facts = E_safe.facts & instFacts
        E_safe.facts.sort(proc(a, b: SemanticFact): int =
          cmp(a.proposition.binLhs.varName, b.proposition.binLhs.varName))
        let loweringCtx = SmtLoweringContext(
          # `SmtLoweringContext.logic` is caller authority and is decided HERE.
          # `set-logic` states what the whole script is, and the pipeline is what
          # composes the script; `classifySmtLogic` reads the function's own type
          # profile, which never sees the uninterpreted symbol a binding's right-
          # hand side introduces. `selectLoweringLogic` widens only when the
          # obligation needs something the declared logic cannot carry, and the
          # lowerer still refuses such a script if a caller gets this wrong.
          logic: selectLoweringLogic(smtLogic, firstObl.proposition),
          rlimit: z3DeterministicBudget,
          obligationKind: $firstObl.kind,
          # S6: for the β-composite the domain preconditions ride as asserted
          # facts — the counterexample must be in-domain (an out-of-domain SAT
          # model would be a bv-wrap artifact, not a bug).
          semanticFacts: E_safe.facts & domainFacts,
          # The bindings that define the proposition's free variables live here,
          # not in the proposition; the lowerer decides which of them become
          # nested SMT `let`s from their `lossFree` flag and the proposition.
          sourceBindings: funcDef.recordedBindings,
          # DEBT#465 body-binding restoration: the subject funcDef rides along so
          # the proposition's `result` binds to the actual body via the typed
          # define-fun impl form (classic emitter precedent) instead of an
          # unconstrained 0-ary constant. A body outside the typed slice makes
          # the lowering refuse (fail-closed) and the classic script below stays.
          funcDef: some(funcDef))
        let lowered = lowerObligationToSmt(firstObl.proposition, loweringCtx)
        if not lowered.empty:
          smtScript = lowered.smtScript
          goldenOblId = firstObl.id
          goldenOblDerivationRule = firstObl.derivationRule
          goldenOblLowered = true
    # ── P3 TheaterGuard: silent-skip protection ───────────────────────
    ## If obligation generation reported ogrGenerated (obligations exist)
    ## but the SMT adapter produced an empty script, this means the adapter
    ## dropped obligations silently — a classic "theater" pattern (§0.9).
    ## Even if the script is genuinely empty for some edge case, we must
    ## NOT silently skip; instead flag it as ill-formed so downstream
    ## stages cannot hide the inconsistency. C0/C7 protection.
    if smtScript.len == 0 and ogr.kind == ogrGenerated:
      logWarn("ir_pipeline_runner",
        "[TheaterGuard] " & entry.name &
        " — obligation generated but adapter produced empty SMT script")
      return IrPipelineResult(
        funcName: entry.name,
        modulePath: entry.sourcePath,
        irDigest: computeDeterministicCasKey(computeIrDigest(funcDef)),
        verification: vrt.makeInconclusive(rkObligationIllFormed),
        provenance: vpNone,
        success: false, skipped: false,
        crossValidation: CrossValidationResult(consistent: false),
        z3Sat: false,
        complexity: fnComplexity,
        backend: vbCanonicalChc,
        actualBackend: vbCanonicalChc,
        fallbackOccurred: false,
        fallbackReason: "",
        requestedBackend: vbCanonicalChc,
        selectedBackend: vbCanonicalChc,
        obligationVerdict: theaterDetectedVerdict(generatedObligationCount))
    if smtScript.len == 0:
      # Vacuous proof — no postconditions to check.
      # NOTE (DEBT#423): statically unreachable today — the case dispatch above
      # returns for every non-generated ogr.kind, so this branch can only be
      # entered with ogr.kind == ogrGenerated, which the TheaterGuard just
      # returned for. Kept as defense-in-depth; its pre-generation (0) verdict
      # is retained deliberately.
      return IrPipelineResult(
        funcName: entry.name,
        modulePath: entry.sourcePath,
        irDigest: computeDeterministicCasKey(computeIrDigest(funcDef)),
        verification: makeNoProperty(),
        provenance: vpBmcSkipped,
        success: true,
        skipped: true,
        crossValidation: CrossValidationResult(consistent: false),
        z3Sat: false,
        complexity: fnComplexity,
        backend: vbCanonicalChc,
        actualBackend: vbCanonicalChc,
        fallbackOccurred: false,
        fallbackReason: "",
        requestedBackend: vbCanonicalChc,
        selectedBackend: vbCanonicalChc,
        obligationVerdict: ObligationVerdictInfo(
          kind: ogrNoApplicableObligation,
          reason: "noPostconditions",
          obligationCount: 0))
    let leanSource = irToLeanModule(funcDef)
    let structurallyConsistent = checkStructuralConsistency(funcDef, smtScript, leanSource)
    let cv = CrossValidationResult(
      consistent: structurallyConsistent,
      z3Result: smtScript,
      leanResult: leanSource,
      irDigest: computeDeterministicCasKey(computeIrDigest(funcDef))
    )
    var bmcCanonicalDigest, bmcTransportDigest: string
    let bmcOutcome = runZ3CheckViaIR(smtScript & '\n' & "(get-model)", phase = spBmc,
      canonicalEnvelopeDigest = bmcCanonicalDigest, transportPayloadDigest = bmcTransportDigest)
    # C20: the BMC route now discharges through a VerificationModel. The raw
    # solver outcome becomes neutral CandidateEvidence (toCandidateEvidence)
    # and the existing evidenceVerdict (EvidenceValidator over the non-loop
    # model) produces the verdict — raw solver unsat must NOT set Proved by
    # itself: the gate requires non-empty candidate evidence plus all three
    # obligation families, and Z3 cannot mint a KAA, so the single verified-
    # verdict authority (VDA) stays unreachable from solver output by
    # construction (verification_decision_authority.nim:105-107). A loop body
    # is not modelable here → none → honest fail-closed (unchanged path).
    # WP4-j.3: provenance normalization below records the REAL solver
    # invocation regardless of the verdict label.
    # NOTE: solver_adapter.SolverStatus → core/types SolverStatus conversion.
    let bmcModel = lowerPostconditionModel(funcDef, contract)
    let bmcCe = toCandidateEvidence(bmcOutcome)
    var bmcResult = if bmcModel.isSome:
      if bmcOutcome.status == sosSat and bmcCe.model.len > 0:
        # BMC SAT on a loop-less contract model: the family validator has no
        # initiation/consecution/safety families to discharge over a one-state
        # contract model (its honest answer there is rkNotEncodable), so the
        # designed authority for a concrete SAT model is the P4 witness
        # admission — re-validate pre ∧ ¬post under the exact solver model and
        # promote to vsDisproved ONLY on cvConfirmed (I3 binding). Every other
        # outcome keeps the candidate inconclusive (fail-closed).
        let cx = newCounterexampleValidator("z3", getBudgetFor(spBmc).timeoutMs)
        let cv = validateCounterexample(cx, bmcModel.get, bmcCe, "z3",
          getBudgetFor(spBmc).timeoutMs)
        finalizeVerdict(makeCandidateCounterexample(bmcCe.model, smBMC, pkZ3Bmc), cv)
      else:
        evidenceVerdict(bmcModel.get, bmcCe, "z3", getBudgetFor(spBmc).timeoutMs)
    else:
      makeInconclusive(rkEvidenceRejected)
    # psBounded discipline: this is the BMC backend — any proved verdict it
    # issues is bounded by construction. The shared validator labels unbounded
    # (Spacer scope); the BMC route must never forward that label.
    if bmcResult.isUnboundedProved:
      bmcResult.proofScope = psBounded
    bmcResult.solverMethod = case bmcOutcome.status
      of sosSat:    smBMC
      of sosUnsat:  smBMC
      else:         smNone
    bmcResult.provenance = if bmcOutcome.status == sosUnsat: pkZ3Bmc else: pkNone
    bmcResult.solverStatus = case bmcOutcome.status
      of sosSat:    coreSolverTypes.solverSat
      of sosUnsat:  coreSolverTypes.solverUnsat
      else:         coreSolverTypes.solverUnknown

    # ── P3 Ledger Population ──────────────────────────
    # Populate the obligation execution ledger with the golden
    # obligation's attempt record and terminal outcome.
    if goldenOblLowered:
      let semOutcome = interpretQueryResult(bmcOutcome.status)
      let attempt = AttemptRecord(
        attemptNumber: 1,
        solverInvocationId: "z3:" & $z3DeterministicBudget & ":" & bmcCanonicalDigest,
        solverInputDigest: sha256Hex(smtScript),
        canonicalEnvelopeDigest: bmcCanonicalDigest,
        transportPayloadDigest: bmcTransportDigest,
        rawSolverStatus: $bmcOutcome.status,
        semanticAttemptOutcome: semOutcome,
        derivationProvenance: "generated:" & funcDef.name & ":" & goldenOblDerivationRule)
      var plan = PlanExecutionRecord(
        planRevision: 1,
        obligationId: goldenOblId,
        attempts: @[attempt])
      obligationExec.plans = @[plan]
      obligationExec.terminalOutcome = some(semOutcome)
      # All other generated ids are dropped outside scope.
      for oid in obligationExec.generatedObligationIds:
        if oid != goldenOblId:
          obligationExec.droppedObligations.add(DroppedObligationRecord(
            obligationId: oid,
            dropReason: $osrDroppedOutsideScope,
            planRevision: 1))
    else:
      # No obligation was executed (lowering empty or no proposition).
      obligationExec.terminalOutcome = some(smOutcomeFailedClosed)
      for oid in obligationExec.generatedObligationIds:
        obligationExec.droppedObligations.add(DroppedObligationRecord(
          obligationId: oid,
          dropReason: $osrDroppedNoPlan,
          planRevision: 1))

    # W4-C: Set provenance to pkZ3Bmc when Z3 confirms property holds (unsat).
    let coreSolverStatus = case bmcOutcome.status
      of sosSat:    coreSolverTypes.solverSat
      of sosUnsat:  coreSolverTypes.solverUnsat
      else:         coreSolverTypes.solverUnknown
    let pipelineClaim = derivePipelineClaim(funcDef, coreSolverStatus)
    IrPipelineResult(
      funcName: entry.name,
      modulePath: entry.sourcePath,
      irDigest: cv.irDigest,
      smtScript: smtScript,
      leanSource: leanSource,
      crossValidation: cv,
      z3Sat: bmcOutcome.status == sosUnsat,
      verification: bmcResult,
      provenance: if bmcOutcome.status == sosUnsat: vpZ3Bmc else: vpNone,
      success: cv.consistent and bmcOutcome.status == sosUnsat,
      complexity: fnComplexity,
      verifiedClaim: some(pipelineClaim),
      backend: vbCanonicalChc,
      actualBackend: vbCanonicalChc,
      fallbackOccurred: false,
      fallbackReason: "",
      requestedBackend: vbCanonicalChc,
      selectedBackend: vbCanonicalChc,
      obligationVerdict: ObligationVerdictInfo(
        kind: ogrGenerated,
        reason: "",
        obligationCount: generatedObligationCount),
      obligationExecution: obligationExec
    )
  except Defect:
    # Defense-in-depth: catch Defects that bypass {.raises: []}.
    # IndexDefect, NilAccessDefect, etc. can escape noRaise procs.
    IrPipelineResult(
      funcName: entry.name,
      success: false,
      verification: vrt.makeInconclusive(vrt.rkBackendError, vrt.tkFailed),
      provenance: vpNone,
      complexity: 0.0,
      backend: vbCanonicalChc,
      actualBackend: vbCanonicalChc,
      fallbackOccurred: false,
      fallbackReason: "",
      requestedBackend: vbCanonicalChc,
      selectedBackend: vbCanonicalChc,
      obligationVerdict: ObligationVerdictInfo(
        kind: ogrIllFormed,
        reason: "backendDefect",
        obligationCount: generatedObligationCount)
    )
  except CatchableError:
    # Should not happen with {.raises: []} but defense-in-depth.
    IrPipelineResult(
      funcName: entry.name,
      success: false,
      verification: vrt.makeInconclusive(vrt.rkBackendError),
      provenance: vpNone,
      complexity: 0.0,
      backend: vbCanonicalChc,
      actualBackend: vbCanonicalChc,
      fallbackOccurred: false,
      fallbackReason: "",
      requestedBackend: vbCanonicalChc,
      selectedBackend: vbCanonicalChc,
      obligationVerdict: ObligationVerdictInfo(
        kind: ogrIllFormed,
        reason: "backendError",
        obligationCount: generatedObligationCount)
    )

# ---------------------------------------------------------------------------
# CAS memoization cache — 동일 IRFuncDef = 동일 출력 (멱등성)
# ---------------------------------------------------------------------------
# AGENT-T: irMemoCache moved from {.global.} to per-worker field in
# ParallelIrContext (axiom_engine.nim) to eliminate cross-thread sharing.
# Each thread now receives its own Table via `memoCache: var` parameter.

proc measuredKernelCompletenessEvidence*(eaAgreed: bool; funcDef: IRFuncDef;
    sourceInventory: Option[BindingInventory]): CompletenessEvidence {.raises: [].} =
  ## Phase 1A — the REAL source↔IR binding-inventory correspondence
  ## measurement behind `ensureKernelCompleteness`, exported so the negative
  ## controls exercise the exact producer logic. The IR side is
  ## `irBindingNames(funcDef)` (lets + params + loop vars); the source side is
  ## the independently observed `sourceInventory` (binding_inventory lock-21
  ## observer). Correspondence reuses `correspondenceHolds` — the SAME
  ## bidirectional multiset comparison the external materializer applies; the
  ## number equality alone is never treated as correspondence. The five
  ## fields:
  ##   translationLossFree     — the measured extraction agreement (unchanged;
  ##                             EA byte-equality IS a measurement)
  ##   bindingUniverseComplete — true ONLY when the EA agreed AND the source
  ##                             and IR binding multisets correspond AND no
  ##                             opaque construct boundary was observed
  ##   opaqueExpansionStatus   — from the measured inventory; "none" only
  ##                             when the observation saw none
  ##   sourceBindingCount      — non-opaque witness count from the inventory
  ##   irBindingCount          — the IR side's own binding count
  ## Unmeasurable inventory (none) → `bindingUniverseComplete=false` and an
  ## honest "source-inventory-unmeasured" status — fail-closed, never a
  ## fabricated complete/universe record.
  let irNames = irBindingNames(funcDef)
  if sourceInventory.isNone:
    return CompletenessEvidence(
      translationLossFree: eaAgreed,
      bindingUniverseComplete: false,
      opaqueExpansionStatus: "source-inventory-unmeasured",
      sourceBindingCount: 0,
      irBindingCount: irNames.len)
  let inv = sourceInventory.get
  let correspondence = correspondenceHolds(irNames, inv)
  let hasOpaque = inv.opaqueBoundaries.len > 0
  CompletenessEvidence(
    translationLossFree: eaAgreed,
    bindingUniverseComplete: eaAgreed and correspondence and not hasOpaque,
    opaqueExpansionStatus: (if hasOpaque: "opaque-boundary-present" else: "none"),
    sourceBindingCount: inv.witnesses.filterIt(not it.opaque).len,
    irBindingCount: irNames.len)

proc ensureKernelCompleteness(ve: ValidatedIrEntry) {.raises: [].} =
  ## Materialize the measured CompletenessEvidence for a kernel-registry entry
  ## at the canonical pre-synthesis anchor, and (Phase 1A) dual-write the
  ## authenticated strict CompletenessBinding sibling at the same anchor.
  ## The five fields are the REAL source↔IR binding-inventory correspondence
  ## measurement (`measuredKernelCompletenessEvidence` — source identifiers
  ## observed independently of the translator, missing/extra/mismatch compared
  ## as bidirectional multisets); an entry with no measured EA agreement, or
  ## whose source inventory is unmeasurable, lands fail-closed — no complete
  ## universe is ever fabricated. The strict sibling is written only when its
  ## capture identity (canonical sourceIdentity composite + module sha) was
  ## measurable at the selection boundary; an unmeasurable capture keeps the
  ## legacy-only generation, which the strict-first reader accepts only while
  ## AXIOM_EVIDENCE_STRICT is unset.
  if not ve.entry.isKernel:
    return
  if not ve.parseBound.eaAgreed:
    return
  let key = computeDeterministicCasKey(serializeIRFuncDef(ve.funcDef))
  let existing = loadEvidenceArtifact(key)
  let evidence =
    if existing.isSome:
      # An earlier phase may have written the legacy artifact before this
      # generation's capture was threaded. The strict sibling is STILL written
      # from that payload: otherwise one path would emit a legacy cert and
      # another a strict cert for the same irHash, and canonical promotion
      # fails with two identities for one IR.
      existing.get
    else:
      let measured = measuredKernelCompletenessEvidence(
        ve.parseBound.eaAgreed, ve.funcDef, ve.sourceBindingInventory)
      saveEvidenceArtifact(key, measured)
      measured
  discard saveCompletenessEvidenceDual(key, ve.funcDef, ve.completenessCapture,
    evidence)
  logInfo("ir_pipeline_runner", "[completeness] materialized measured binding for " &
    ve.entry.name & " key=" & key &
    " correspondence=" & $evidence.bindingUniverseComplete &
    " opaque=" & evidence.opaqueExpansionStatus)

proc runIrPipelineWithCas*(ve: ValidatedIrEntry,
                             lspClient: LeanLspClient = nil,
                             memoCache: var Table[string, IrPipelineResult],
                             policy: BackendPolicy = bpRequire,
                             subjectRepoRoot: string = ""): IrPipelineResult {.gcsafe, raises: [].} =
  ## CAS 캐시 — 동일 IRFuncDef에 대해 이전 실행 결과를 재사용 (프로세스 수명 내).
  ## serializeIRFuncDef 기반 deterministic key로 멱등성 보장.
  let astHash = serializeIRFuncDef(ve.funcDef)
  let cacheKey = computeDeterministicCasKey(astHash)

  if memoCache.hasKey(cacheKey):
    logInfo("ir_pipeline_runner", "[ir-cas] HIT func=" & ve.funcDef.name & " key=" & cacheKey)
    try:
      return memoCache[cacheKey]
    except KeyError:
      discard

  ensureKernelCompleteness(ve)
  result = runIrPipeline(ve, lspClient, policy, subjectRepoRoot)
  # ── S4-S5: PROPOSITION_DISPROVED payload — replay Execution Adapter (observer-only) ──
  # Fires ONLY on a P4-promoted disproof (cvConfirmed → vsDisproved) with a
  # concrete solver model, and only for the BMC lane: the inductive CHC
  # lanes return early with provenance vpInductiveLoop and their models are
  # transition witnesses, not exact entry inputs (loop replay is out of
  # scope). The adapter (authority 0) replays the model's exact input
  # against the real subject module under the GateEnvLock-fingerprinted
  # toolchain. Agreement completes the PROPOSITION_DISPROVED payload (glossary §2.2);
  # ANY disagreement/unavailability demotes fail-closed to the candidate
  # (cvUnresolved semantics) — the promotion authority itself is unchanged.
  if result.verification.status == vsDisproved and
     result.provenance != vpInductiveLoop and
     result.verification.model.len > 0:
    let replay = replayConfirmedDisproof(subjectRepoRoot, ve.entry.sourcePath,
                                         ve.funcDef, result.verification.model,
                                         ve.parseBound)
    if replay.agreed:
      result.counterExample = replay.payload
      logInfo("ir_pipeline_runner", "[ce-replay] " & ve.funcDef.name &
        " — replay agreed; PROPOSITION_DISPROVED payload assembled (" &
        $replay.payload.len & " records)")
    else:
      let carriedModel = result.verification.model
      result.verification = makeInconclusive(rkCandidateCounterexample)
      result.verification.solverMethod = smBMC
      result.verification.solverStatus = coreSolverTypes.solverSat
      result.verification.model = carriedModel
      result.verification.evidence = "replay:" & replay.diagnostics
      logInfo("ir_pipeline_runner", "[ce-replay] " & ve.funcDef.name &
        " — replay " & replay.diagnostics & "; fail-closed cvUnresolved")
  memoCache[cacheKey] = result
  logInfo("ir_pipeline_runner", "[ir-cas] MISS func=" & ve.funcDef.name & " key=" & cacheKey)

proc extractBareFuncName*(nodeId: SorterNodeId): string =
  ## Extract bare function name from qualified SorterNodeId.
  ## Topology format: "modulePath::funcName" → "funcName"
  ## If no "::" separator found, returns the raw string as-is.
  let raw = sorterNodeIdString(nodeId)
  let sepIdx = raw.find("::")
  if sepIdx >= 0:
    result = raw[sepIdx + 2 .. ^1]
  else:
    result = raw

proc selectEntriesFor*(requests: seq[OrchestrationProofRequest]): SelectionReport =
  ## Map topology-ranked requests to their corresponding registry entries.
  ## Uses O(1) Table lookup (registryLookup from axiom_pragmas).
  ## Preserves strict topological ordering (requests 순방향 순회 → result.add).
  ## Structural Anomaly: topology node에 @axiom IR이 없으면 skippedNodes에 기록.
  result = SelectionReport(selected: @[], skippedNodes: @[], skippedCount: 0)
  for req in requests:
    let bareName = extractBareFuncName(req.nodeId)
    # Try exact match, then with/without * suffix
    if registryLookup.hasKey(bareName):
      let entry = registryLookup[bareName]
      let funcDef = deserializeIRFuncDef(entry.irSerialized)
      result.selected.add(ValidatedIrEntry(entry: entry, funcDef: funcDef))
    elif registryLookup.hasKey(bareName & "*"):
      let entry = registryLookup[bareName & "*"]
      let funcDef = deserializeIRFuncDef(entry.irSerialized)
      result.selected.add(ValidatedIrEntry(entry: entry, funcDef: funcDef))
    elif bareName.len > 1 and bareName[^1] == '*' and registryLookup.hasKey(bareName[0..^2]):
      let entry = registryLookup[bareName[0..^2]]
      let funcDef = deserializeIRFuncDef(entry.irSerialized)
      result.selected.add(ValidatedIrEntry(entry: entry, funcDef: funcDef))
    else:
      result.skippedNodes.add(sorterNodeIdString(req.nodeId))
  result.skippedCount = result.skippedNodes.len
  if result.skippedCount > 0:
    logInfo("ir_pipeline_runner", "[selectEntriesFor] Structural Anomaly: " &
      $result.skippedCount & " topology node(s) have no @axiom IR registry entry: " &
      result.skippedNodes.join(", "))

proc selectRegistryEntries*(limit: int; verifiedFuncs: HashSet[string] = initHashSet[string]();
                            kernelOnly: bool = false;
                            verifiableOnly: bool = false;
                            pureOnly: bool = false): seq[ValidatedIrEntry] {.raises: [].} =
  ## W4-B: Select the first `limit` entries with valid IR, returning
  ## ValidatedIrEntry with cached deserialization. The funcDef is computed
  ## once here and reused by runIrPipeline — eliminating double deserialization.
  ## Skips entries with sentinel IR (deserialize to empty funcDef.name).
  ## Skips entries whose funcDef.name is already in verifiedFuncs.
  ## When kernelOnly=true, only entries marked as kernel are selected.
  ## When verifiableOnly=true, BMC-skippable entries are excluded.
  ## When pureOnly=true, only Pure-effect entries are selected (mirrors the
  ## kernel-scope filter in collectKernelSymbols — effectKind == Pure).
  ## Sorts by (sourcePath, funcDef.name) lexicographically for deterministic
  ## canonical selection order regardless of registry insertion order or cache state.
  var candidates = newSeq[ValidatedIrEntry]()
  for entry in runtimeAxiomRegistry:
    if entry.irSerialized.len > 0 and (not kernelOnly or entry.isKernel) and
       (not verifiableOnly or not entry.bmcSkippable) and
       (not pureOnly or entry.effectKind == Pure):
      let funcDef = deserializeIRFuncDef(entry.irSerialized)
      if funcDef.name.len > 0 and funcDef.name notin verifiedFuncs:
        candidates.add(ValidatedIrEntry(entry: entry, funcDef: funcDef))
  candidates = candidates.sortedByIt((it.entry.sourcePath, it.funcDef.name))
  if candidates.len > limit:
    candidates.setLen(limit)
  result = candidates

func computeVkdRequiredLimit*(cliLimit: int; kernelTotal: int; targetVkd: string): int {.axiomDecision(id = "DECISION-0011",
                    reason = "Monotonic VKD target ratchet; kernelTotal floor guarantees full kernel scope feeds the VKD numerator",
                    adr = "docs/adr/0011-vkd-target-ratchet.md",
                    introduced = "v31"), raises: [].} =
  ## Internal *selection feed* budget for the VKD target — NOT the user's
  ## proof-attempt budget. P4 contract:
  ##   * The caller's CLI `--limit N` is the user-facing proof-attempt cap.
  ##   * This proc computes how many registry entries must be **fetched upstream**
  ##     so that kernel-scope symbols interleaved in registry order are not
  ##     truncated before selection (`kernelTotal` floor). 
  ##   * It may therefore EXCEED `cliLimit` — it is a *fetch* widening, not an
  ##     execution budget. The actual admissible proof-attempt budget that enters
  ##     the executor is bounded separately (frontier + admissibility filter).
  ## Fail-closed: if targetVkd is empty/unparseable/non-positive, fall back to
  ## the kernelTotal floor (no silent under-fetch below full kernel scope).
  if targetVkd.len == 0:
    return max(cliLimit, kernelTotal)
  let parsedVkd = safeParseFloat(targetVkd)
  if parsedVkd.isErr:
    return max(cliLimit, kernelTotal)
  let target = parsedVkd.get
  if target <= 0.0:
    return max(cliLimit, kernelTotal)
  let needed = max(int(ceil(kernelTotal.float * target)) + 1, kernelTotal)
  result = max(cliLimit, needed)

proc selectProofCandidates*(limit: int; kernelTotal: int; targetVkd: string; verifiedFuncs: HashSet[string] = initHashSet[string](); externalCandidates: seq[ExternalIrEntry] = @[]; subjectRepoRoot: string = ""): seq[ValidatedIrEntry] {.raises: [],
     axiomDecision(id = "DECISION-0012",
                   reason = "verifiableOnly+pureOnly selection so every emitted cert targets the kernel scope (verification_scope.lock SSOT) and counts toward the VKD numerator",
                   adr = "docs/adr/0011-vkd-target-ratchet.md",
                   introduced = "v31").} =
  ## IR-pipeline candidate selector with domain-safe defaults. Hardcodes
  ## `verifiableOnly=true` (BMC-skippable string/float entries excluded) and
  ## `pureOnly=true` (effectKind == Pure), so selection mirrors the kernel-scope
  ## filter in collectKernelSymbols exactly — every generated cert targets a
  ## symbol in the kernel scope (verification_scope.lock SSOT) and therefore counts toward the VKD
  ## numerator (countKernelVerified) by construction. Raises the limit to meet
  ## the target VKD ratchet. Already-certified kernels (ProofVault `verifiedFuncs`)
  ## are excluded so the IR pipeline does not re-process them (0ms cache skip).
  ## External candidates (synthesized from subject source) are processed through
  ## the same eligibility gate as registry entries and merged before sorting.
  ## Safe by construction for every caller.
  ##
  ## `subjectRepoRoot` (Phase 1A): the analysis root the pipeline threads to
  ## the strict-first reader — measured into the kernel entries'
  ## `completenessCapture` here so the strict dual-write and the reader
  ## recompute the SAME source identity. Empty (callers without a threaded
  ## root) leaves the capture unmeasurable → the strict dual-write is refused
  ## (fail-closed legacy-only), never bound to a different root.
  let required = computeVkdRequiredLimit(limit, kernelTotal, targetVkd)
  let raw = selectRegistryEntries(required, verifiedFuncs, verifiableOnly=true, pureOnly=true)
  let extMode = externalSubjectMode

  func isCandidateEligible(ve: ValidatedIrEntry): bool =
    let admission = assessAdmissibility(ve.entry, ve.funcDef)
    if admission.decision == INELIGIBLE: return false
    let eligibility = classifyCandidateEligibility(ve.entry, ve.funcDef)
    if eligibility != elProofCandidate: return false
    ve.entry.isKernelScopeMember or (extMode and ve.entry.origin == soExternalSubject)

  for ve in raw:
    if isCandidateEligible(ve):
      result.add(ve)

  # Process external candidates through the same eligibility gate.
  for ext in externalCandidates:
    let ve = ValidatedIrEntry(entry: ext.entry, funcDef: ext.funcDef,
                              parseBound: ext.parseBound)
    if isCandidateEligible(ve):
      result.add(ve)

  result = result.sortedByIt((it.entry.sourcePath, it.funcDef.name))

  # §2.1a parse-bound measurement boundary (MAIN thread): the Nim parser and the
  # extraction differential hold process globals and are NOT gcsafe, so the
  # components are measured here — before the IR worker thread is spawned — and
  # travel into the gcsafe worker chain as ValidatedIrEntry.parseBound values.
  # Unmeasurable legs stay empty and fail the canonical binding closed downstream.
  # Entries that already CARRY components (a synthesized composite's two-leg
  # measurement from its synthesis site) are never re-measured per name — a
  # composite name does not exist in the subject source, so that measurement
  # could only clobber honest legs with a failure.
  for i in 0 ..< result.len:
    if not parseBoundCarried(result[i].parseBound):
      if result[i].entry.sourceContent.len == 0:
        # RuntimeAxiomEntry.sourceContent contract ("not carried" — consumers
        # fall back to path-relative resolution): registry entries carry no
        # in-band bytes, so the §2.1a parse-bound measurement resolves the
        # subject bytes from the entry's repo-relative sourcePath here (MAIN
        # thread) and carries them on the entry — the worker-chain binding
        # site (buildSubjectBinding) then seals over the SAME bytes the
        # components were measured from. resolveSubjectRepoRoot documents
        # exactly this: internal subjects' module bytes are read from the
        # subject repo, contentCarried stays false for them.
        let subjectPath =
          if isAbsolute(result[i].entry.sourcePath): result[i].entry.sourcePath
          else: findRepoRoot() / result[i].entry.sourcePath
        let subjectBytes =
          try: readFile(subjectPath)
          except CatchableError: ""
        if subjectBytes.len > 0:
          result[i].entry.sourceContent = subjectBytes
      result[i].parseBound = measureParseBoundComponents(
        result[i].entry.sourceContent, result[i].funcDef.name)
  # Phase 1A kernel completeness capture boundary (MAIN thread): the source
  # binding inventory (parseStringAST is NOT gcsafe) and the strict-binding
  # capture identity are measured here — where the subject bytes are already
  # resolved and the pipeline's subject root is threaded — and travel into
  # the gcsafe worker chain as ValidatedIrEntry values. Kernel entries only:
  # ensureKernelCompleteness is the sole consumer; external candidates carry
  # their capture from their own producer (materializer / carrier synthesis).
  for i in 0 ..< result.len:
    if result[i].entry.isKernel:
      if result[i].entry.sourceContent.len > 0:
        result[i].sourceBindingInventory = measureSourceBindingInventory(
          result[i].entry.sourceContent, result[i].funcDef.name,
          result[i].entry.sourcePath)
      # Kernel entries are repo-resolved subjects: their bytes were read from
      # the subject repo (not carried in-band), so an unthreaded root may fall
      # back to the CWD git root — the SAME resolution the strict-first reader
      # applies. contentCarried=true here would make every caller that does not
      # thread a root (loop_driver) silently unmeasurable.
      result[i].completenessCapture = measureCompletenessSourceCapture(
        subjectRepoRoot, result[i].entry.sourcePath,
        result[i].entry.sourceContent, contentCarried = false)

proc runAllIrPipelines*(lspClient: LeanLspClient = nil,
                            policy: BackendPolicy = bpRequire): seq[IrPipelineResult] {.raises: [].} =
  ## Convenience: iterate the entire runtimeAxiomRegistry through the IR pipeline.
  ## Respects per-entry CAS caching via a local memoCache (process-lifetime).
  var memoCache: Table[string, IrPipelineResult]
  result = @[]
  for entry in runtimeAxiomRegistry:
    if entry.irSerialized.len > 0:
      let funcDef = deserializeIRFuncDef(entry.irSerialized)
      if funcDef.name.len > 0:
        let ve = ValidatedIrEntry(entry: entry, funcDef: funcDef)
        result.add(runIrPipelineWithCas(ve, lspClient, memoCache, policy))

proc runIrPipelinesFor*(entries: seq[ValidatedIrEntry],
                         memoCache: var Table[string, IrPipelineResult],
                         lspClient: LeanLspClient = nil,
                         policy: BackendPolicy = bpRequire,
                         subjectRepoRoot: string = ""): seq[IrPipelineResult] {.gcsafe, raises: [].} =
  ## Execute IR pipeline for the given bounded collection.
  ## W4-B: Accepts ValidatedIrEntry — cached funcDef avoids re-deserialization.
  ## AGENT-T: memoCache is per-worker — eliminates cross-thread global state.
  ## W4-D: Stays sequential — Z3 bottleneck is parallelized in z3_pool.nim
  ## (subprocess isolation). IR generation is pure CPU on small inputs where
  ## thread spawn overhead (malebolgia) exceeds computation time. Additionally,
  ## Nim 2.2.10 isolation check rejects seq/ref fields on spawn boundaries.
  ## No internal limit or counter — iterates exactly entries.len times.
  ## IR Inline Pass: Before SMT encoding, inline small non-recursive functions
  ## to eliminate uninterpreted function overhead in Z3 BMC.
  var allFuncDefs: seq[IRFuncDef]
  for ve in entries:
    allFuncDefs.add(ve.funcDef)

  result = @[]
  for ve in entries:
    # Apply IR inline pass — inlineSmallFunctions returns a new IRExpr (pure),
    # so the original funcDef in `entries` is not mutated.
    var inlinedEntry = ve
    inlinedEntry.funcDef.body = inlineSmallFunctions(ve.funcDef.body, allFuncDefs)
    result.add(runIrPipelineWithCas(inlinedEntry, lspClient, memoCache, policy, subjectRepoRoot))

# ---------------------------------------------------------------------------
# AGENT-C: ProofCertificate conversion — IrPipelineResult → ProofCertificate
# ---------------------------------------------------------------------------

func resultMethodToSolverMethod(m: vrt.SolverMethod): proof_certificate.SolverMethod =
  case m
  of vrt.smCHC:    proof_certificate.smSpacer
  of vrt.smBMC:   proof_certificate.smCLI
  of vrt.smTypeLevel: proof_certificate.smTypeLevel
  of vrt.smNone:  proof_certificate.smNone

## S4-S5: ProofCertificate projection carries the PROPOSITION_DISPROVED payload in the
## pre-existing counterExample slot — non-empty ONLY when the replay adapter
## agreed on the promoted disproof (runIrPipelineWithCas post-processing);
## the whole payload is covered by the cert JSON signature.
func toProofCertificate*(r: IrPipelineResult): ProofCertificate =
  var status: ProofStatus
  var sm: proof_certificate.SolverMethod
  var prov: string

  ## P5: obligationVerdict takes priority over legacy verification.status
  ## because it carries the finer-grained semantic classification from the
  ## obligation generator.  Check these first so they are never shadowed
  ## by the coarser vsNoObligation / vsInconclusive paths.
  if r.obligationVerdict.kind == ogrNoApplicableObligation:
    ## P5: NoApplicable — obligation generator proved no obligation applies.
    ## Cert classification: 증명된 분류 (proven classification).
    ## Exit code 0 (R5 regression guard: same as psNoObligation).
    status = psNoObligation
    sm = resultMethodToSolverMethod(r.verification.solverMethod)
    prov = "solverMethod=" & $r.verification.solverMethod & ",provenance=" & $r.verification.provenance & ",ObliSemanticNoApplicable"
  elif r.obligationVerdict.kind in {ogrUnsupported, ogrIllFormed}:
    ## P5: Unsupported / IllFormed — obligation generator could not produce
    ## a verifiable obligation.  Distinguished from psSkip by the
    ## "not_verifiable:<reason>" provenance prefix and by the
    ## solverMeta.notVerifiable field in the certificate JSON.
    ## Exit code 0 (R5 regression guard: same as psSkip).
    status = psSkip
    sm = resultMethodToSolverMethod(r.verification.solverMethod)
    let reasonStr = case r.obligationVerdict.kind
      of ogrUnsupported: "unsupported"
      of ogrIllFormed: "illFormed"
      else: "unknown"
    prov = "not_verifiable:" & reasonStr & ",solverMethod=" & $r.verification.solverMethod & ",provenance=" & $r.verification.provenance
  elif r.verification.status == vsNoObligation:
    status = psNoObligation
    sm = resultMethodToSolverMethod(r.verification.solverMethod)
    prov = "solverMethod=" & $r.verification.solverMethod & ",provenance=" & $r.verification.provenance & ",no-obligation"
  elif r.verification.status in {vsInconclusive} and r.verification.reason in {rkNoProperty, rkNotEncodable}:
    status = psSkip
    sm = resultMethodToSolverMethod(r.verification.solverMethod)
    prov = "solverMethod=" & $r.verification.solverMethod & ",provenance=" & $r.verification.provenance
  elif r.success:
    status = psPass
    sm = resultMethodToSolverMethod(r.verification.solverMethod)
    prov = "solverMethod=" & $r.verification.solverMethod & ",provenance=" & $r.verification.provenance
  elif r.funcName.len == 0 or (r.irDigest.len == 0 and r.smtScript.len == 0):
    status = psError
    sm = proof_certificate.smNone
    prov = "solverMethod=" & $r.verification.solverMethod & ",provenance=" & $r.verification.provenance
  else:
    status = psFail
    sm = resultMethodToSolverMethod(r.verification.solverMethod)
    prov = "solverMethod=" & $r.verification.solverMethod & ",provenance=" & $r.verification.provenance

  let cert = ProofCertificate(
    functionName: r.funcName,
    sourceFile: r.modulePath,
    status: status,
    solverMethod: sm,
    metrics: SolverMetrics(),
    smtScript: r.smtScript,
    leanSource: r.leanSource,
    irHash: r.irDigest,
    provenance: prov,
    counterExample: r.counterExample,
    error: if not r.success and status == psError: "IR pipeline failure" else: "",
    crossValidated: r.crossValidation.consistent,
    obligationVerdict: r.obligationVerdict.kind
  )
  if not verifyOutcomeContract(cert):
    var demoted = cert
    demoted.status = psError
    demoted.error = "fail-closed: contract violation status=" & $cert.status &
                     " verdict=" & $cert.obligationVerdict
    return demoted
  cert

func toProofCertificates*(results: seq[IrPipelineResult]): seq[ProofCertificate] =
  result = newSeq[ProofCertificate](results.len)
  for i, r in results:
    result[i] = toProofCertificate(r)

func toCertificateBatch*(results: seq[IrPipelineResult]): CertificateBatch =
  result.certificates = toProofCertificates(results)
  for cert in result.certificates:
    case cert.status
    of psPass:
      inc result.passCount
    of psNoObligation:
      inc result.skipCount
    of psFail, psVacuousCounter:
      inc result.failCount
    of psTimeout:
      inc result.timeoutCount
    of psSkip:
      inc result.skipCount
    of psError:
      inc result.errorCount
    of psVacuousTrivial:
      inc result.skipCount

