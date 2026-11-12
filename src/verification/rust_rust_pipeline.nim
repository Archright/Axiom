import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

## Rust subject pipeline (feat/rust-subject-v1) — the thin entry point that
## CHAINS the existing, individually verified pieces of the Rust subject
## path. This module owns NO new verification logic, NO new verdict
## vocabulary, NO new gate, NO new authority — it is plumbing:
##
##   LLBC text --(llbc_to_canonical)--> RustCanonical        (rce* stage)
##             --(rust_extraction_agreement)--> ea* verdict  (INV-4 stage)
##                 canonical → wire → Nim leg / Lean reference leg →
##                 byte-compare (the wire step lives inside
##                 runRustExtractionAgreement)
##
## CLASSIFICATION (the honesty contract; docs/spec/rust_certified_subset.md
## §2, docs/spec/llbc_quirks.md Q2/Q3):
##   producer rceUnsupportedGrammar → OUT-OF-SCOPE / fail-closed UNKNOWN.
##     Surfaced as eaUnsupported with the producer reason — NEVER verified,
##     NEVER an internal error (e.g. is_zero lowers to Switch outside the
##     closed straight-line grammar).
##   producer rceMalformed          → fail-closed internal (OUR producer or
##     lookup failed) — eaInternalError.
##   eaAgree                        → the extraction path is sound; the only
##     proceed-to-proof classification.
##   eaMismatch / eaUnsupported / eaReferenceError / eaInternalError
##                                  → fail-closed, no seal.
## A producer rejection is classified BEFORE any differential worker runs —
## no Lean invocation, no partial evidence, fully deterministic.
##
## INPUT CONTRACT STAGE (Phase 1-A, opt-in via non-empty `subjectRoot`):
## rustSubjectInputContract runs BEFORE the producer — LLBC file-table
## pre-validation, Cargo crate identity (Cargo.lock/Cargo.toml digests) and
## the LLBC↔source file-set equivalence, fail-closed before anything
## consumes the LLBC. A contract rejection is STALENESS (the dvcNotCurrent
## precedent, certificate_verifier.nim): the LLBC is structurally valid but
## not-current product truth, classified on the EXISTING eaMismatch axis by
## contractRejectionAgreement — never eaInternalError, never verified.
##
## Purity note: the parse procs are `proc`, not `func` — std/json parseJson
## is tagged `.sideEffect`, and this follows the parseLlbcFile precedent
## (llbc_to_canonical.nim). Both still carry `{.raises: [].}`: every failure
## is an explicit not-ok value, never an exception.
##
## EXTRACTION PROVENANCE STAGE (Phase 2-D integration, armed by the same
## opt-in as the input contract — non-empty `subjectRoot` + `llbcPath` +
## an EvidenceCas `extractionLedger` transport): after the differential
## agreed (so the input contract provably passed), the lane
##   (1) digests the consumed LLBC raw bytes (llbcFileDigest; the consumed
##       text must byte-match the file, else fail-closed),
##   (2) MEASURES the Rust toolchain (rust_replay_adapter
##       .rustToolchainFingerprint — measurement is never re-implemented),
##   (3) binds the subject exact-commit identity (subjectGitIdentity — the
##       adapter's read-only rev-parse queries; non-git/unavailable roots
##       FAIL CLOSED, the adapter's own precedent — no git value is ever
##       fabricated and no absent literal is invented),
##   (4) records the extraction contract from the LLBC's embedded
##       translated.target_information/options (RECORDED provenance — each
##       member verbatim as canonical JSON text),
##   (5) lands the validated ExtractionJobRecord in the EXISTING EvidenceCas
##       side-ref ledger (appendExtractionJobRecord — exactly-once,
##       content-addressed),
## and at ISSUANCE time re-fetches the record (fetchExtractionJobRecord —
## full identity chain re-verified) and re-compares it against the honestly
## measurable environment (verifyExtractionEnvironment): the Rust toolchain
## MEASURED now via the adapter, the Charon identity against the PINNED
## extraction-pin constants (this lane never runs Charon; the pin SSOT is
## the consumer repo's approved pin, quirk Q3). Violation AND
## unverifiability both fail closed (declared-pin gate pattern); the first
## blocking point is recorded in the issuance record with stage
## "provenance" — never bypassed.
##
## EVIDENCE BINDING: when the provenance stage armed, the v2 evidence wire
## (AttestationInputs — EvidenceScheme) is digested over its seven real
## members (llbcDigest + rustToolchainIdentity among them) and folded into
## the Rust lane's execution-contract digest, which transitively binds the
## LLBC bytes and the measured Rust toolchain identity into
## canonicalizeKaa → kaaDigest → evidenceId → certificate identityDigest
## (the 13th identity field). The provenance-unarmed lane keeps the landed
## mounted-input digest byte-identical (all-or-nothing, the v2 record's own
## empty-binding semantics).
##
## This wiring is what makes the AxiomTrustBoundary rows "LLBC to shared
## canonical translation" and "dual IR derivation from shared canonical"
## (src/core/trusted/trust_boundary.nim) runnable end to end; the rows
## themselves are owned by the trust-boundary module, not here.

import std/[json, options, os, strutils, tables]
import core/axiom_pragmas
import core/crypto/hash_kernel
import core/results
import core/release/version_derive
import core/trusted/axiom_ir
import core/trusted/ir_to_smt  # irToSmtScript — the SMT counterexample queries
import core/trusted/rust_canonical
import core/types/obligation_evidence  # parseModelBindings — the Z3 (get-model) parse
import verification/attestation_orchestrator
import verification/canonical_json
import verification/cert_writer
import verification/counterexample_replay  # ConcreteValue / parseConcreteLiteral / evaluatePostconditions — the sibling attribution check
import verification/extraction_agreement
import verification/extraction_provenance
import verification/ledger_side_ref
import verification/llbc_to_canonical
import verification/obligation/canonical_verification
import verification/obligation/identity
import verification/obligation/obligation_types  # AssumptionOrigin filter
import verification/obligation/kernel_acceptance_authority
import verification/obligation/lean_evidence
import verification/obligation/lean_kernel_boundary
import verification/rust_extraction_agreement
import verification/rust_input_contract
import verification/rust_obligation_render
import verification/rust_replay_adapter
import verification/rust_symbolic_test_synth  # exact-input gate + Rust literal projection
import verification/solver_adapter  # SolverAdapter.solve — the Z3 run idiom

axiomIoBoundary()

proc parseLlbcText(text: string): LlbcFile {.raises: [].} =
  ## parseLlbcFile's in-memory sibling — same explicit not-ok outcome on any
  ## parse failure (never raises; std/json parseJson is tagged `.sideEffect`,
  ## hence proc — see the purity note in the module docstring).
  try:
    LlbcFile(ok: true, root: parseJson(text), reason: "")
  except CatchableError as e:
    LlbcFile(ok: false, root: nil,
             reason: "cannot parse LLBC JSON text: " & e.msg)

proc rustSubjectToCanonical*(llbcText: string; funcName: string):
    LlbcToCanonicalResult {.raises: [].} =
  ## (1) LLBC text → shared Rust canonical via the existing producer
  ## (verification/llbc_to_canonical.llbcFunctionToCanonical). The rce*
  ## vocabulary passes through verbatim; a text-level JSON parse failure is
  ## rceMalformed (the document is structurally unusable — fail-closed).
  let f = parseLlbcText(llbcText)
  if not f.ok:
    return LlbcToCanonicalResult(ok: false, error: rceMalformed, reason: f.reason)
  llbcFunctionToCanonical(f.root, funcName)

func recordedExtractionContract*(root: JsonNode): JsonNode {.raises: [].} =
  ## RECORDED extraction contract for the ExtractionJobRecord, taken from the
  ## LLBC's embedded `translated.target_information` / `translated.options`.
  ## Each PRESENT member is recorded VERBATIM as its RFC 8785 canonical JSON
  ## text (the record's object-of-strings contract) — recorded provenance,
  ## never trust adjudication, never a cherry-picked subset (the whole member
  ## travels). Absent members are omitted; an LLBC without either member
  ## yields the empty contract object (valid — recording is optional
  ## provenance).
  result = newJObject()
  if root.isNil or root.kind != JObject:
    return
  let translated = root{"translated"}
  if translated.isNil or translated.kind != JObject:
    return
  for member in ["target_information", "options"]:
    let node = translated{member}
    if not node.isNil:
      result["translated." & member] = %canonicalJsonString(node)

func producerRejectionAgreement(rejected: LlbcToCanonicalResult):
    ExtractionAgreementResult {.raises: [].} =
  ## Pre-classification of a producer rejection — fail-closed BEFORE any
  ## differential runs. The mapping is the one llbc_to_canonical already
  ## documents (rceUnsupportedGrammar "→ eaUnsupported downstream"); OUR
  ## producer or lookup failing (rceMalformed) is an internal failure, never
  ## an out-of-scope claim and never a success.
  let verdict = case rejected.error
                of rceUnsupportedGrammar: eaUnsupported
                of rceMalformed, rceNone: eaInternalError
  ExtractionAgreementResult(
    verdict: verdict,
    reason: (case verdict
             of eaUnsupported:
               "out-of-scope subject grammar — fail-closed UNKNOWN " &
               "(not verified, not an internal error): "
             else:
               "subject canonical producer failed: ") & rejected.reason,
    nimDigest: "",
    leanDigest: "")

func contractRejectionAgreement(rejected: RustInputContractResult):
    ExtractionAgreementResult {.raises: [].} =
  ## Pre-classification of an INPUT-CONTRACT rejection — fail-closed BEFORE
  ## anything consumes the LLBC. STALENESS NAMING: the dvcNotCurrent
  ## precedent (certificate_verifier.nim) — a mis-bound LLBC is structurally
  ## valid but not-current product truth, so it rides the EXISTING mismatch
  ## axis (eaMismatch), never eaInternalError (reserved for OUR
  ## producer/lookup failures) and never an out-of-scope claim. The result's
  ## reason already carries the classification text and names the offending
  ## paths. No new verdict vocabulary.
  ExtractionAgreementResult(
    verdict: eaMismatch,
    reason: rejected.reason,
    nimDigest: "",
    leanDigest: "")

proc rustSubjectExtractionAgreement*(llbcText: string; funcName: string;
    rcheckExe: string = ""; projectRoot: string = "";
    timeoutMs: int = 60_000; subjectRoot: string = "";
    depInfoPath: string = ""): ExtractionAgreementResult {.
    raises: [CatchableError], axiomEffect: IOEffect,
    tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## (2) LLBC text → the existing ea* verdict (INV-4 differential). A
  ## produced canonical flows through runRustExtractionAgreement verbatim
  ## (canonical → wire → Nim/Lean legs → byte compare). A producer rejection
  ## is pre-classified by producerRejectionAgreement — no worker runs.
  ## With a non-empty `subjectRoot`, the Phase 1-A INPUT CONTRACT
  ## (rustSubjectInputContract) runs FIRST — the LLBC↔source binding is
  ## fail-closed before anything consumes the LLBC (a contract rejection is
  ## pre-classified by contractRejectionAgreement, eaMismatch axis).
  if subjectRoot.len > 0:
    let f = parseLlbcText(llbcText)
    if not f.ok:
      return producerRejectionAgreement(LlbcToCanonicalResult(
        ok: false, error: rceMalformed, reason: f.reason))
    let contract = rustSubjectInputContract(f.root, subjectRoot, depInfoPath)
    if not contract.ok:
      return contractRejectionAgreement(contract)
    let produced = llbcFunctionToCanonical(f.root, funcName)
    if not produced.ok:
      return producerRejectionAgreement(produced)
    return runRustExtractionAgreement(produced.canonical, rcheckExe,
                                      projectRoot, timeoutMs)
  let produced = rustSubjectToCanonical(llbcText, funcName)
  if not produced.ok:
    return producerRejectionAgreement(produced)
  runRustExtractionAgreement(produced.canonical, rcheckExe, projectRoot,
                             timeoutMs)

type
  RustSubjectOutcome* = object
    ## THE single outcome of one (llbcText, funcName) request — both stages
    ## side by side, reusing the EXISTING vocabularies verbatim (no new
    ## enum, no new gate, no new authority). Classify with
    ## outcomeProceedToProof / outcomeOutOfScopeUnknown / outcomeFailClosed.
    producer*: LlbcToCanonicalResult
      ## grammar/structure stage (rce*; rceNone iff the canonical was
      ## produced)
    agreement*: ExtractionAgreementResult
      ## INV-4 differential stage (ea*). When the producer rejected, this
      ## carries ONLY the pre-classification of that rejection (see
      ## producerRejectionAgreement) — no differential ever ran.
    rejection*: RustFileTableRejection
      ## the input contract's structured file-table rejection facts when the
      ## contract refused the LLBC (`rule == ""` otherwise) — §6c v2
      ## production-time rejection binding; verdicts and reasons unchanged
    embeddedFiles*: seq[LlbcEmbeddedEntry]
      ## the §6d embeddedContentAttested entries when the LLBC file table
      ## passed (a LATER sub-check's refusal keeps them — the attestation
      ## stands; measurement for the sidecar identity, never a verdict
      ## input; empty when the table itself was rejected)

func outcomeOutOfScopeUnknown*(o: RustSubjectOutcome): bool {.raises: [].} =
  ## Producer rejected the grammar (rceUnsupportedGrammar) → the subject is
  ## OUT OF SCOPE: fail-closed UNKNOWN — never verified, never an internal
  ## error.
  (not o.producer.ok) and o.producer.error == rceUnsupportedGrammar

func outcomeProceedToProof*(o: RustSubjectOutcome): bool {.raises: [].} =
  ## The extraction path is SOUND (eaAgree) — the only proceed-to-proof,
  ## seal-eligible classification.
  o.producer.ok and o.agreement.verdict == eaAgree

func outcomeFailClosed*(o: RustSubjectOutcome): bool {.raises: [].} =
  ## Everything else — producer malformed, eaMismatch, wire-stage
  ## eaUnsupported, eaReferenceError, eaInternalError — fail-closed, no seal.
  not (outcomeOutOfScopeUnknown(o) or outcomeProceedToProof(o))

proc rustSubjectOutcome*(llbcText: string; funcName: string;
    rcheckExe: string = ""; projectRoot: string = "";
    timeoutMs: int = 60_000; subjectRoot: string = "";
    depInfoPath: string = ""): RustSubjectOutcome {.
    raises: [CatchableError], axiomEffect: IOEffect,
    tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## (3) The single outcome: producer stage + differential stage in one
  ## record. Exactly one of outcomeProceedToProof / outcomeOutOfScopeUnknown
  ## / outcomeFailClosed holds; an out-of-scope rejection can never masquerade
  ## as verified (it is eaUnsupported with the producer reason, and
  ## outcomeProceedToProof requires a produced canonical) nor as an internal
  ## crash (outcomeOutOfScopeUnknown distinguishes it from eaInternalError).
  ## With a non-empty `subjectRoot`, the Phase 1-A INPUT CONTRACT runs
  ## FIRST: the LLBC↔source binding (file table, Cargo identity, file-set
  ## equivalence) is fail-closed before any consumption; a contract
  ## rejection lands in outcomeFailClosed with agreement.verdict ==
  ## eaMismatch (the dvcNotCurrent staleness axis, not eaInternalError).
  if subjectRoot.len > 0:
    let f = parseLlbcText(llbcText)
    if not f.ok:
      result.producer = LlbcToCanonicalResult(ok: false, error: rceMalformed,
        reason: f.reason)
      result.agreement = producerRejectionAgreement(result.producer)
      return
    let contract = rustSubjectInputContract(f.root, subjectRoot, depInfoPath)
    # §6d: a MEASUREMENT, not a verdict input — the attested entries survive
    # a refusal from a LATER contract sub-check (the file table passed;
    # `contract.embeddedFiles` is empty when the table itself was rejected,
    # so no attestation stands for a rejected table).
    result.embeddedFiles = contract.embeddedFiles
    if not contract.ok:
      result.producer = LlbcToCanonicalResult(ok: false,
        error: rceMalformed, reason: contract.reason)
      result.agreement = contractRejectionAgreement(contract)
      result.rejection = contract.rejection
      return
    result.producer = llbcFunctionToCanonical(f.root, funcName)
  else:
    result.producer = rustSubjectToCanonical(llbcText, funcName)
  if result.producer.ok:
    result.agreement = runRustExtractionAgreement(result.producer.canonical,
                                                  rcheckExe, projectRoot,
                                                  timeoutMs)
  else:
    result.agreement = producerRejectionAgreement(result.producer)

# ---------------------------------------------------------------------------
# Guard-obligation attempts — the UNDECLARED lane entries (no spec exists)
# ---------------------------------------------------------------------------
## A lane entry that is extraction-sound (eaAgree) but NOT declared in
## vks_rust has no spec postcondition to render, so the declared issuance
## path is unreachable by construction. The guard attempt asks the only
## mechanical question the body itself poses: does every checked-add stay
## within the operand width? Per goal (one per DISTINCT `+` node):
##   renderRustGuardObligationLean (hypotheses = type ranges ONLY — the
##     overflow condition is the GOAL, never an assumption; spike S1 showed
##     the laundered form is a trivial accept = theater)
##   → canonicalLeanKernelCheck + scanSorryMarkers (receipt alone proves
##     nothing — `sorry` also exits 0; spike S4)
##   → on kernel decline: rustCanonicalToIrFuncDef + irToSmtScript
##     (includeOverflowDefines=false) → Z3 asks
##     `ranges ∧ sibling-goals ∧ ¬goal` — the SIBLING-CONSTRAINED query:
##     asserting every other guard goal makes each SAT model one where all
##     OTHER checked adds are mathematically in range, so an observed
##     overflow panic is the targeted add's (closed-grammar monotone sums;
##     the concrete sibling re-check on the parsed bindings below is
##     defense-in-depth).
##   → on SAT: the model's exact input is REPLAYED against the real subject
##     (confirmGuardByReplay → runRustCounterexampleReplay) and an observed
##     OVERFLOW panic (exit 101 + "attempt to add with overflow" report —
##     the checked-ADD operation's own text, an implementation observation
##     signal, not a contract guarantee; a future toolchain rewording fails
##     closed) that SURVIVES the sibling attribution gate CONFIRMS the
##     counterexample in the reason text. Still NON-CLAIMING: no certificate,
##     no KAA, no writer — the lane classification stays "unknown" and the
##     confirmed reason says so ("not a declared-spec failure; no
##     certificate"). Model literals, the panic report and the measured
##     replay toolchain travel ONLY on RustGuardGoalOutcome log-only fields
##     (z3ModelRaw/replayInputs/panicEvidence/replayToolchain), never inside
##     a report reason. Z3 idiom: SolverAdapter.solve
##     (solver_adapter.nim:118) — it auto-appends `(get-model)` after
##     `(check-sat)` and classifies the status; `diagnostics` carries the raw
##     combined output.

type RustGuardGoalOutcome* = object
  ## The mechanical trace of ONE guard goal. `z3ModelRaw` is for LOG LINES
  ## ONLY — reasons never embed model values (deterministic text contract).
  ## The replay-confirmation fields (`confirmed` plus the three evidence
  ## strings) are likewise LOG-ONLY: `confirmed` refines the reason text,
  ## the evidence strings never enter it.
  goalText*: string            ## canonical predicate text of the goal
  proved*: bool                ## kernel receipt ∧ scanSorryMarkers clean
  declinedByKernel*: bool      ## the kernel gate refused (receipt or sorry)
  z3Sat*: bool                 ## Z3: a refuting candidate exists (SAT)
  z3ScriptDigest*: string      ## sha256Hex of the SMT query when Z3 ran
  z3ModelRaw*: string          ## raw Z3 output incl. the model (logs only)
  confirmed*: bool             ## the replay observed the model's exact input
                               ## panicking with an OVERFLOW report (rroPanicked
                               ## + "with overflow") — log-bound evidence, never
                               ## a status change
  replayInputs*: string        ## "param=literal, …" projection of the replayed
                               ## model (logs only)
  panicEvidence*: string       ## verbatim panic report (logs only)
  replayToolchain*: string     ## measured replay toolchain identity — version +
                               ## channel (logs only)
  reason*: string              ## the goal's own classification text
  admissionNote*: string       ## log-only attribution note (e.g. a sibling
                               ## guard goal violated by the model) — NEVER
                               ## inside the reason text, never a status or
                               ## reason change

type RustGuardAttemptRecord* = object
  ## The mechanical trace of ONE declaration-free attempt. `attempted` = the
  ## producer + INV-4 differential reached eaAgree (the same gate the lane
  ## classifies before the declared check); never a verdict by itself.
  attempted*: bool
  outcome*: RustSubjectOutcome ## the producer/differential outcome (verbatim)
  goalCount*: int              ## rustGuardGoals length (0 = no mechanical goals)
  goalOutcomes*: seq[RustGuardGoalOutcome]
  reason*: string              ## aggregated, lane-ready (see below)

func guardPanicIsAttributedAdd*(evidence: string): bool {.raises: [].} =
  ## THE overflow-attribution marker: the checked-ADD operation's own panic
  ## report text ("attempt to add with overflow"). Single definition — the
  ## confirmation gate and the tests share it. An implementation observation
  ## signal, NOT a contract guarantee: a future toolchain that words the
  ## report differently simply fails closed (unconfirmed), never mis-confirms.
  evidence.contains("attempt to add with overflow")

func guardObservationAdmitted*(outcome: RustReplayOutcome;
                               evidence: string): bool {.raises: [].} =
  ## The single G1 observation-admission predicate: a replay admits the
  ## guard observation ONLY when the outcome is rroPanicked AND the evidence
  ## carries the checked-ADD report text (guardPanicIsAttributedAdd). The
  ## profile-off shape (an exit-0 value observation → rroAgree/rroDisagree)
  ## and every unavailable shape are rejected here, by construction.
  outcome == rroPanicked and guardPanicIsAttributedAdd(evidence)

func guardModelAttributionSafe*(siblings: seq[IRExpr];
                                bindings: seq[ModelBinding];
                                params: seq[IRFuncParam]): bool {.raises: [].} =
  ## Defense-in-depth panic ATTRIBUTION check (pure): every sibling guard
  ## goal must hold under the model's concrete bindings, so an observed
  ## overflow panic belongs to the TARGETED add and not to a sibling checked
  ## add. Empty siblings → trivially safe. Each parameter needs a binding
  ## that projects to a parseable concrete value — `bindingToRustLiteral`
  ## (hex-aware; it already converts the `#x…` form that
  ## `parseConcreteLiteral` rejects) — any missing/unparseable parameter →
  ## NOT safe (fail closed). The sibling conjunction must evaluate to
  ## some(true); none/false → not safe.
  if siblings.len == 0:
    return true
  var env = initTable[string, ConcreteValue]()
  for p in params:
    var literal = ""
    var bound = false
    for b in bindings:
      if b.name == p.name:
        literal = bindingToRustLiteral(b, p.ty)
        bound = true
        break
    if not bound:
      return false
    let parsed = parseConcreteLiteral(literal)
    if parsed.isNone:
      return false
    env[p.name] = parsed.get()
  evaluatePostconditions(siblings, env) == some(true)

func rustParamBoolFlags(canonical: RustCanonical): seq[bool] {.raises: [].} =
  ## Positional source-level bool flags for the replay call site. The IR
  ## keeps one bitVec64 value sort (the v1.4 Bool 0/1 embed), so the model
  ## literal arrives as "0"/"1"; the harness needs the SOURCE type to render
  ## `false`/`true`. Pure projection — no state, no I/O.
  result = @[]
  for p in canonical.params:
    result.add(p.ty.kind == rtyBool)

proc confirmGuardByReplay(g: var RustGuardGoalOutcome; modelRaw: string;
                          subjectRoot: string; subjectModulePath: string;
                          funcDef: IRFuncDef; goal: IRExpr;
                          siblingGoals: seq[IRExpr];
                          paramBool: seq[bool] = @[]) {.
    raises: [], axiomEffect: IOEffect,
    tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  ## Replay-confirmation attempt for ONE declined+SAT guard goal (the
  ## undeclared lane): the Z3 model's exact input is replayed against the
  ## real subject and CONFIRMED only on an observed OVERFLOW panic — the
  ## adapter's `rroPanicked` outcome AND the checked-add report marker
  ## "attempt to add with overflow" (guardPanicIsAttributedAdd; a bare
  ## "panicked at" is evidence about the compile profile, not the overflow
  ## observation the AddChecked structural witness bound; the guard goals
  ## derive only from AddChecked nodes, so the overflow class is the only
  ## honest confirmation — the exact wording is an implementation observation
  ## signal, not a contract guarantee, and a future toolchain rewording
  ## fails closed as unconfirmed). `siblingGoals` are the OTHER guard goals
  ## of the same attempt (the set asserted in the Z3 query): before any
  ## replay, the SIBLING ATTRIBUTION GATE re-checks them concretely on the
  ## parsed bindings (guardModelAttributionSafe) — a model that violates a
  ## sibling could panic at a sibling add instead of the targeted one, so
  ## the attempt is recorded ONLY on the log-only `admissionNote` and
  ## confirmation stays off. Arms only when the subject module is bound and
  ## present; the exact-input gate (every canonical param bound) and the
  ## certified Rust-literal projection (no empty literal) precede the
  ## attribution gate and the replay; the adapter itself fails closed on
  ## non-git/unborn-HEAD subjects and compile failures. EVERY
  ## non-confirmation — model gap, unbound param, unprojectable literal,
  ## unsafe attribution, rroAgree/rroDisagree/rroUnavailable, compile
  ## failure, non-overflow panic, any adapter-raised error — leaves
  ## `confirmed` false so the caller keeps the unconfirmed fallback text
  ## verbatim (honest fallback, never a fabricated confirmation). The
  ## captured evidence fields are LOG-ONLY: the reason text never embeds
  ## literals, panic text, or toolchain identity.
  g.confirmed = false
  if subjectRoot.len == 0 or subjectModulePath.len == 0 or
      not fileExists(subjectModulePath):
    return
  try:
    let bindings = parseModelBindings(modelRaw)
    # Exact-input discipline (S4): replaying a defaulted input would present
    # it as the solver's counterexample — fail closed unless every subject
    # parameter is bound (unboundParameters empty).
    if unboundParameters(bindings, funcDef.params).len > 0:
      return
    let literals = modelToRustTestInputs(bindings, funcDef.params)
    if literals.len == 0:
      return
    var paramNames: seq[string] = @[]
    for p in funcDef.params:
      paramNames.add(p.name)
    for lit in literals:
      if lit.len == 0:
        return  # outside the certified Rust-literal subset — unplayable
    # Sibling attribution gate (defense-in-depth behind the constrained
    # query): the panic must provably belong to the targeted add — a model
    # that violates any sibling goal is NOT attributable, so no replay runs
    # and the observation travels on the log-only note (the reason text and
    # its fallback stay verbatim).
    if not guardModelAttributionSafe(siblingGoals, bindings, funcDef.params):
      g.admissionNote = "sibling guard goal violated by the model — " &
                        "attribution unsafe"
      return
    let record = runRustCounterexampleReplay(RustReplayConfig(
      subjectRepoRoot: subjectRoot,
      subjectModulePath: subjectModulePath,
      funcName: funcDef.name,
      paramNames: paramNames,
      inputLiterals: literals,
      paramBool: paramBool,
      postconditions: @[goal],
      rustcExe: ""))
    if not guardObservationAdmitted(record.outcome, record.panicEvidence):
      return
    g.confirmed = true
    var parts: seq[string] = @[]
    for i, pn in paramNames:
      if i < literals.len:
        parts.add(pn & "=" & literals[i])
    g.replayInputs = parts.join(", ")
    g.panicEvidence = record.panicEvidence
    g.replayToolchain = record.rustVersion &
      (if record.rustChannel.len > 0: " channel=" & record.rustChannel else: "")
  except CatchableError:
    discard # axiom:best-effort(unconfirmed fold — the honest fallback text, never a fabricated confirmation)

proc rustGuardObligationAttempt*(llbcText: string; funcName: string;
    rcheckExe: string = ""; projectRoot: string = "";
    timeoutMs: int = 60_000; subjectRoot: string = "";
    subjectModulePath: string = ""): RustGuardAttemptRecord {.
    raises: [CatchableError], axiomEffect: IOEffect,
    tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  ## The declaration-free attempt for one (llbcText, funcName): producer +
  ## INV-4 differential (rustSubjectOutcome, verbatim), then per guard goal
  ## the kernel attempt and — on decline — the Z3 counterexample question,
  ## and — on SAT with the subject module bound (`subjectModulePath`, beside
  ## `subjectRoot`) — the replay confirmation (confirmGuardByReplay; an
  ## observed OVERFLOW panic confirms the candidate in the reason text).
  ## Never issues anything; every reason text is non-claiming by contract.
  ## The default `subjectModulePath = ""` keeps confirmation disarmed for
  ## existing callers (unconfirmed fallback text, byte-identical behavior).
  result.outcome = rustSubjectOutcome(llbcText, funcName, rcheckExe,
                                      projectRoot, timeoutMs, subjectRoot)
  if not outcomeProceedToProof(result.outcome):
    # attempted stays false — the same stages the lane surfaces directly;
    # the stage's own reason passes through (lane text shape).
    let stage = if result.outcome.producer.ok: "extraction" else: "producer"
    result.reason = stage & ": " & result.outcome.agreement.reason
    return
  result.attempted = true
  let canonical = result.outcome.producer.canonical
  let nimDigest = result.outcome.agreement.nimDigest
  let goals = rustGuardGoals(canonical)
  result.goalCount = goals.len
  if goals.len == 0:
    result.reason = "no derivable guard obligation (attempt ran; zero mechanical goals)"
    return
  for gi, goal in goals:
    var g = RustGuardGoalOutcome(goalText: canonicalizePredicate(goal))
    # This goal's SIBLING set — every other guard goal, first-occurrence
    # order. The same set feeds the constrained Z3 query (preExtra) and the
    # replay-side attribution gate.
    var siblingGoals: seq[IRExpr] = @[]
    for j in 0 ..< goals.len:
      if j != gi:
        siblingGoals.add(goals[j])
    let rendered = renderRustGuardObligationLean(canonical, nimDigest, goal)
    if not rendered.ok:
      # Fail-closed, non-claiming: the kernel never saw this goal.
      g.reason = "guard goal '" & g.goalText & "' render refused (" &
                 rendered.reason & "); no claim"
      result.goalOutcomes.add(g)
      continue
    let kernelResult = canonicalLeanKernelCheck(rendered.leanSource,
                                                timeoutMs = 120_000)
    var declined = true
    if kernelResult.isOk:
      let receipt = kernelResult.get()
      # The receipt alone proves nothing — `sorry` also exits 0; the sorry
      # scan is the mandatory second gate (spike S4; canonical_verification
      # .scanSorryMarkers).
      if scanSorryMarkers(rendered.leanSource,
                          receipt.receiptKernelObservation).len == 0:
        declined = false
        g.proved = true
    if not declined:
      g.reason = "guard obligation discharged (proved: '" & g.goalText &
        "'; kernel receipt, sorry-free); non-claiming — no certificate (undeclared)"
      result.goalOutcomes.add(g)
      continue
    g.declinedByKernel = true
    # CONSTRAINED QUERY (structural panic attribution): asserting the
    # sibling guard goals as extra hypotheses makes every SAT model one
    # where all OTHER checked adds are mathematically in range — so any
    # observed overflow panic is the targeted add's (closed-grammar
    # monotone sums; the concrete sibling re-check on the parsed bindings
    # inside confirmGuardByReplay is defense-in-depth).
    let funcDef = rustCanonicalToIrFuncDef(canonical, goal, siblingGoals)
    if funcDef.name.len == 0:
      # Unreachable post-eaAgree (the differential proves the Nim leg);
      # honest non-claiming text, no Z3 claim.
      g.reason = "guard goal '" & g.goalText &
        "' unproven (kernel declined; SMT query construction failed — no " &
        "refuting candidate confirmed); no claim"
      result.goalOutcomes.add(g)
      continue
    let script = irToSmtScript(funcDef, includeOverflowDefines = false)
    g.z3ScriptDigest = sha256Hex(script)
    let z3 = newSolverAdapter("z3", timeoutMs).solve(script)
    case z3.status
    of sosSat:
      g.z3Sat = true
      g.z3ModelRaw = z3.diagnostics  # raw output — LOG LINES ONLY
      # Confirmation attempt: the refuting candidate is replayed against the
      # real subject when the subject module is bound — CONFIRMED only on an
      # observed overflow panic whose report text names the checked add
      # (guardPanicIsAttributedAdd) and only when the SIBLING ATTRIBUTION
      # GATE passes (confirmGuardByReplay; an unsafe attribution travels on
      # the log-only admissionNote). The classification stays unknown either
      # way and the unconfirmed text below is kept VERBATIM on every
      # non-confirmation.
      confirmGuardByReplay(g, z3.diagnostics, subjectRoot, subjectModulePath,
                           funcDef, goal, siblingGoals,
                           rustParamBoolFlags(canonical))
      if g.confirmed:
        g.reason = "guard goal '" & g.goalText &
          "' VIOLATED — declined by kernel; counterexample confirmed by " &
          "replay under the recorded overflow-checking profile " &
          "(overflow-checks=on, debug-assertions=on; extraction witness " &
          "AddChecked; overflow-class observation, out-of-subset per §3 — " &
          "profile-bound, not language semantics); model script digest " &
          g.z3ScriptDigest & "; not a declared-spec failure; no certificate"
      else:
        g.reason = "guard goal '" & g.goalText &
          "' declined by kernel; Z3 confirms a refuting candidate exists " &
          "(script digest " & g.z3ScriptDigest &
          "); counterexample confirmation unavailable (overflow-discretion " &
          "class, out-of-subset per §3)"
    of sosUnsat:
      g.reason = "guard goal '" & g.goalText &
        "' unproven (kernel declined; Z3 unsat — no refuting candidate); no claim"
    else:
      g.reason = "guard goal '" & g.goalText & "' unproven (kernel declined; Z3 " &
        $z3.status & " — no refuting candidate confirmed); no claim"
    result.goalOutcomes.add(g)
  # Aggregation precedence: any declined+SAT reason first (the most
  # informative class), else any declined+unsat, else the all-proved set;
  # the unproved-undeclined residue (render refusals) is the last resort so
  # a refusal can never masquerade as proved. No raw model values — ever.
  var declinedSat, declinedUnsat, provedSet, residue: seq[string] = @[]
  for g in result.goalOutcomes:
    if g.declinedByKernel and g.z3Sat: declinedSat.add(g.reason)
    elif g.declinedByKernel: declinedUnsat.add(g.reason)
    elif g.proved: provedSet.add(g.reason)
    else: residue.add(g.reason)
  var picked = declinedSat
  if picked.len == 0: picked = declinedUnsat
  if picked.len == 0: picked = provedSet
  if picked.len == 0: picked = residue
  result.reason = "guard attempt: " & $result.goalCount & " goal(s); " &
    picked.join("; ")

# ---------------------------------------------------------------------------
# Phase 2-E — Rust lane → EXISTING issuer (KAA → cert_writer)
# ---------------------------------------------------------------------------
## The live-wiring stage: a well-formed Rust case (eaAgree) is driven through
## the EXISTING issuance path — the closed-template renderer
## (rust_obligation_render), the single canonical sink
## (lean_kernel_boundary.canonicalLeanKernelCheck), the single KAA authority
## (kernel_acceptance_authority.bindReceipt), the CanonicalLeanEvidence seal
## (newCanonicalLeanEvidence — splice barrier + theorem binding + measured
## toolchain fingerprint), and the EXISTING v3 writer
## (cert_writer.writeCertificateFromUapResult) carrying the extraction-bounded
## claim gate. NO new issuer, NO parallel issuance path, NO new verdict
## vocabulary: the record below is a mechanical trace of WHICH existing stage
## blocked first (with file:line + the stage's own error), never a verdict.
##
## Honest-failure protocol: the first blocking point is recorded precisely and
## returned — never bypassed, never retried through another route. The irHash
## adoption follows the orchestrator's carrier rule
## (attestation_orchestrator.nim): irHash := agreement.nimDigest (the
## RustCanonical wire sha256) when the differential agreed.

type RustIssuanceRecord* = object
  ## The mechanical trace of ONE issuance attempt. `attempted` = the case
  ## reached the obligation stage (eaAgree); `issued` = the existing writer
  ## persisted the certificate. On any block, `blockStage` names the first
  ## blocking stage, `blockSite` its file:line, `blockReason` the stage's own
  ## error — the exact deliverable shape of the honest-failure protocol.
  attempted*: bool
  issued*: bool
  certPath*: string          ## the emitted projection file when issued
  blockStage*: string        ## "" when issued; else producer/extraction/
                             ## provenance/obligation/kernel/kaa/evidence/writer
  blockSite*: string         ## file:line of the blocking call site
  blockReason*: string       ## the stage's own error text (verbatim)
  irHash*: string            ## adopted nimDigest (empty before the differential agreed)
  proposition*: string       ## the closed-family proposition when rendered
  leanSource*: string        ## the rendered artifact when rendered
  obligationId*: string      ## the C4 obligation identity when rendered
  extractionJobKey*: string  ## 64-hex content address of the ExtractionJobRecord
                             ## landed in the EvidenceCas ledger ("" when the
                             ## provenance stage did not arm)
  counterexampleConfirmed*: bool
    ## true iff a kernel decline was followed by an IN-DOMAIN replayed
    ## counterexample (SMT model → replayConfirmedRustDisproof agreement).
    ## The record still names "kernel" as the blocking stage — confirmation
    ## refines the reason text, never the honest-failure protocol.
  confirmedPayload*: seq[string]
    ## the PROPOSITION_DISPROVED payload lines of the confirmed disproof ("" seq when
    ## unconfirmed); consumed by the lane's "failed" classification only.

proc rustLaneExecutionContractDigest*(leanSourceHash: string;
                                      extractionEvidenceDigest: string = ""): string {.
    raises: [CatchableError], axiomEffect: IOEffect,
    tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Mirror of canonical_verification.buildExecutionContract (private there)
  ## for the Rust lane's evidence seal: the same role-literal execution
  ## contract shape. The mounted input names WHAT the lane consumed and the
  ## kernel executed: the rendered source digest alone (provenance-unarmed
  ## lane — byte-identical to the landed formula), or, when the extraction
  ## provenance armed, a bound digest of the rendered source AND the v2
  ## extraction-evidence wire (AttestationInputs digest over its seven real
  ## members: funcSource/funcName/leanSource/smtlib2/toolchainIdentity +
  ## llbcDigest + rustToolchainIdentity). The bound form is what makes the
  ## consumed LLBC bytes and the measured Rust toolchain identity part of
  ## executionContractDigest → canonicalizeKaa → kaaDigest → evidenceId →
  ## certificate identityDigest.
  var mountedInputs = leanSourceHash
  if extractionEvidenceDigest.len > 0:
    mountedInputs = sha256Hex("leanSource=" & leanSourceHash &
      "|extractionEvidence=" & extractionEvidenceDigest)
  let repoRoot = getCurrentDir()
  executionContractDigest(canonicalExecutionContract(
    invocation = "lake env lean --threads=1 <artifact>.lean",
    platform = hostPlatformId,
    workdir = "<execution>",
    allowedEnv = @[
      EnvVarSpec(name: "AXIOM_LEAN_CMD", canonicalValue: canonicalizeEnvValue("AXIOM_LEAN_CMD", getEnv("AXIOM_LEAN_CMD", ""), repoRoot)),
      EnvVarSpec(name: "PATH", canonicalValue: canonicalizeEnvValue("PATH", getEnv("PATH", ""), repoRoot)),
      EnvVarSpec(name: "TMPDIR", canonicalValue: canonicalizeEnvValue("TMPDIR", getEnv("TMPDIR", ""), repoRoot))
    ],
    fsBoundary = "<subject>",
    networkPolicy = "deny",
    mountedInputs = mountedInputs,
    resourcePolicy = "cpu=1,mem=512MB"))

proc rustSubjectIssuance*(llbcText: string; funcName: string; specPost: IRExpr;
                          certDir: string; modulePath: string;
                          sourceCode: string;
                          rcheckExe: string = ""; projectRoot: string = "";
                          timeoutMs: int = 60_000; subjectRoot: string = "";
                          depInfoPath: string = "";
                          axiomVersion: string = axiomVersionWithPrefix;
                          llbcPath: string = "";
                          extractionLedger: Option[LedgerTransport] = none(LedgerTransport);
                          extractionLedgerRepo: string = ""): RustIssuanceRecord {.
    raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect,
    tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  ## Drive ONE (llbcText, funcName, specPost) request through the existing
  ## issuance path. Blocks are recorded, never bypassed (honest-failure
  ## protocol): the FIRST blocking stage wins and the record is returned.
  ## The EXTRACTION PROVENANCE STAGE arms exactly when the Phase 1-A input
  ## contract arms (non-empty `subjectRoot`); arming REQUIRES `llbcPath`
  ## (the consumed LLBC file whose raw bytes are digested), an
  ## `extractionLedger` transport and `extractionLedgerRepo` (the existing
  ## EvidenceCas side-ref ledger) — a missing arm is fail-closed, never a
  ## silent skip.
  template blockHere(stage: string; reason: string) =
    result.blockStage = stage
    let info = instantiationInfo()
    result.blockSite = info.filename & ":" & $info.line
    result.blockReason = reason
    return result

  # Stage: producer + extraction differential (the Phase 1 outcome).
  let outcome = rustSubjectOutcome(llbcText, funcName, rcheckExe, projectRoot,
                                   timeoutMs, subjectRoot, depInfoPath)
  if outcome.producer.ok:
    result.irHash = outcome.agreement.nimDigest
  else:
    blockHere("producer", outcome.agreement.reason)
  if outcome.agreement.verdict != eaAgree:
    blockHere("extraction", outcome.agreement.reason)
  result.attempted = true

  # Stage: extraction provenance (Phase 2-D integration — see the module
  # docstring). Armed by the same opt-in as the input contract; eaAgree above
  # proves the contract passed, i.e. this lane may consume the LLBC.
  var provenanceArmed = false
  var jobRecord: ExtractionJobRecord
  var jobLlbcDigest = ""
  var jobFingerprint: RustToolchainFingerprint
  if subjectRoot.len > 0:
    if llbcPath.len == 0:
      blockHere("provenance",
        "extraction provenance armed (subjectRoot bound) but llbcPath is empty — " &
        "the consumed LLBC bytes cannot be bound (fail-closed)")
    if extractionLedger.isNone or extractionLedgerRepo.len == 0:
      blockHere("provenance",
        "extraction provenance armed but the EvidenceCas ledger transport/repo " &
        "is not provided — the job record cannot land (fail-closed)")
    # (1) the consumed LLBC bytes: raw-file digest, and the text this lane
    # consumed must BE those bytes (otherwise the evidence would bind bytes
    # the pipeline never saw).
    let digest = llbcFileDigest(llbcPath)
    if digest.isErr:
      blockHere("provenance", digest.error)
    let consumedDigest = sha256Hex(llbcText)
    if consumedDigest != digest.get:
      blockHere("provenance",
        "consumed LLBC text does not match the LLBC file bytes " &
        "(sha256 mismatch — provenance would bind bytes this lane did " &
        "not consume) (fail-closed)")
    # (2) MEASURED Rust toolchain identity — the adapter's measurement,
    # never re-implemented. An empty rustcPath IS the not-found diagnostic.
    let fingerprint = rustToolchainFingerprint("")
    if fingerprint.rustcPath.len == 0:
      blockHere("provenance",
        "rustc not found — the extraction toolchain fingerprint is " &
        "unmeasurable, so no valid job record exists (quirk Q1 fail-closed)")
    # (3) subject exact-commit identity — the adapter's read-only rev-parse
    # queries; unavailable identity fails closed (no fabrication, no absent
    # literal — the bindRustSubjectIntegrity precedent).
    let git = subjectGitIdentity(subjectRoot)
    if git.gitRef.len == 0 or git.treeMerkle.len == 0:
      blockHere("provenance",
        "subject git identity unavailable (rev-parse failed) — exact-commit " &
        "binding required (fail-closed)")
    let moduleDigest = fileSha256Hex(modulePath)
    if moduleDigest.isErr:
      blockHere("provenance", "subject module unreadable: " & moduleDigest.error)
    # (4) the record: pinned Charon pin (consumer-repo SSOT, quirk Q3) +
    # charon_version RECORDED from the LLBC header + the measured
    # fingerprint + the recorded contract + subject identity + llbcDigest.
    let parsed = parseLlbcText(llbcText)
    if not parsed.ok:
      blockHere("provenance", parsed.reason)
    var headerVersion = ""
    let header = parsed.root{"charon_version"}
    if not header.isNil and header.kind == JString:
      headerVersion = header.getStr()
    jobRecord = ExtractionJobRecord(
      charonPinCommit: PinnedCharonPinCommit,
      charonVersion: headerVersion,
      rustcFingerprint: fingerprint,
      extractionContract: recordedExtractionContract(parsed.root),
      subjectGitRef: git.gitRef,
      subjectTreeMerkle: git.treeMerkle,
      moduleSha256: moduleDigest.get,
      llbcDigest: digest.get)
    let problem = validateExtractionJobRecord(jobRecord)
    if problem.len > 0:
      blockHere("provenance", problem)
    let key = extractionJobKey(jobRecord)
    if key.isErr:
      blockHere("provenance", key.error)
    # (5) durable landing — the existing EvidenceCas side-ref ledger,
    # exactly-once under the record's content address.
    let landed = appendExtractionJobRecord(extractionLedger.get,
                                           extractionLedgerRepo, jobRecord,
                                           currentUtcTimestamp())
    if landed.isErr:
      blockHere("provenance", landed.error)
    provenanceArmed = true
    jobLlbcDigest = digest.get
    jobFingerprint = fingerprint
    result.extractionJobKey = key.get

  # Stage: closed-template obligation render (rust_obligation_render).
  let rendered = renderRustObligationLean(outcome.producer.canonical,
                                          result.irHash, specPost)
  if not rendered.ok:
    blockHere("obligation", rendered.reason)
  result.proposition = rendered.proposition
  result.leanSource = rendered.leanSource
  result.obligationId = rendered.obligationId

  # Stage: the single canonical Lean kernel sink.
  let kernelResult = canonicalLeanKernelCheck(rendered.leanSource,
                                              timeoutMs = 120_000)
  if kernelResult.isErr:
    # Declared-lane counterexample confirmation — BEFORE recording the
    # block. The kernel decline is not the last word when the subject root
    # is bound: the SMT query asserts the theorem's hypothesis domain
    # (type ranges ∪ body-derived caller overflow conditions — exactly the
    # standard renderer's hypothesis set, buildWidthPreconditions filtered
    # to aoCallerObligation since rustCanonicalToIrFuncDef adds the ranges)
    # and negates the spec post, so a SAT model is IN-DOMAIN by
    # construction (exit-0 observable disagreements, never overflow-class
    # panic points); replayConfirmedRustDisproof then replays those exact
    # inputs against the real subject. blockStage stays "kernel" either
    # way — confirmation refines the reason text, never the honest-failure
    # protocol. Z3 idiom: SolverAdapter.solve (auto-appends (get-model);
    # diagnostics = raw combined output). Any step that does not seal keeps
    # the unconfirmed text verbatim.
    if subjectRoot.len > 0:
      var confirmed = false
      var payload: seq[string] = @[]
      block confirmStep:
        let canonical = outcome.producer.canonical
        let body = inlineLets(rustCanonicalToIr(canonical).body)
        var preExtra: seq[IRExpr] = @[]
        for pre in buildWidthPreconditions(canonical, body):
          if pre.origin == aoCallerObligation:
            preExtra.add(pre.pred)
        let funcDef = rustCanonicalToIrFuncDef(canonical, specPost, preExtra)
        if funcDef.name.len == 0:
          break confirmStep
        let script = irToSmtScript(funcDef, includeOverflowDefines = false)
        if script.len == 0:
          break confirmStep
        let z3 = newSolverAdapter("z3", timeoutMs).solve(script)
        if z3.status != sosSat:
          break confirmStep
        let replay = replayConfirmedRustDisproof(subjectRoot, modulePath,
                                                 funcDef, z3.diagnostics,
                                                 paramBool = rustParamBoolFlags(canonical))
        if replay.agreed:
          confirmed = true
          payload = replay.payload
        else:
          # Observability ONLY — classification, exit and the state machine
          # are unchanged (the fail-closed cvUnresolved fold is exactly the
          # precedent); the replay diagnostics the unconfirmed path used to
          # discard now ride the reason text, in the Nim lane precedent's
          # format (ir_pipeline_runner.nim:1624). The diagnostics exist only
          # here — every earlier `break confirmStep` ran no replay.
          blockHere("kernel", kernelResult.error & " — replay " &
            replay.diagnostics & "; fail-closed cvUnresolved")
      if confirmed:
        result.counterexampleConfirmed = true
        result.confirmedPayload = payload
        blockHere("kernel", "spec declined by kernel; counterexample " &
          "CONFIRMED: " & payload.join(", "))
    blockHere("kernel", kernelResult.error)
  let receipt = kernelResult.get()

  # Stage: bindReceipt — the ONLY KAA creation path. The axiom profile is the
  # honest record of the kernel's own observation (best-effort probe: a failed
  # probe records an EMPTY axiom set — never a fabricated one; the cert's
  # deep-verification gate treats empty as not-deep, fail-closed).
  var axioms: seq[string] = @[]
  try:
    let probeSource = rendered.leanSource & "\n#print axioms " &
      receipt.receiptTheoremIdentity & "\n"
    let (probeOutput, _) = runLeanProbe(probeSource, "_axioms", 120_000)
    axioms = parseAxiomProfile(probeOutput)
  except CatchableError:
    discard # axiom:best-effort(ioboundary catch) — axiom probe is observational only
  let kaaResult = bindReceipt(receipt, axioms,
                              scanSorryMarkers(rendered.leanSource,
                                               receipt.receiptKernelObservation))
  if kaaResult.isErr:
    blockHere("kaa", kaaResult.error)
  let kaa = kaaResult.get()

  # Stage: the CanonicalLeanEvidence seal (splice barrier + theorem binding +
  # measured toolchain fingerprint — kernel_acceptance_authority.nim). When
  # the provenance stage armed, the v2 evidence wire (AttestationInputs,
  # EvidenceScheme) is digested over its seven real members — leanSource is
  # THIS run's rendered artifact, funcSource/funcPath/funcName are the
  # request's own subject, toolchainIdentity is the pinned D2 identity, and
  # llbcDigest/rustToolchainIdentity are the recorded extraction binding —
  # and folded into the execution-contract digest, which transitively binds
  # the LLBC bytes into kaaDigest → evidenceId → certificate identityDigest.
  # The wire's record-level fields (subjectId/prHeadSha/envDigest/policy/
  # scope digests) belong to the attest() lane, which rebuilds its own
  # AttestationInputs from the subject store; they are not wire members and
  # are never fabricated here.
  var extractionEvidenceDigest = ""
  if provenanceArmed:
    extractionEvidenceDigest = evidenceBundleDigest(AttestationInputs(
      schemaVersion: EvidenceScheme,
      subjectId: "", prNumber: 0, prHeadSha: "",
      leanSource: rendered.leanSource,
      smtlib2: "",
      funcSource: sourceCode,
      funcPath: modulePath,
      funcName: funcName,
      policyDigest: "", scopeDigest: "", envDigest: "",
      toolchainIdentity: pinnedToolchainIdentity(),
      llbcDigest: jobLlbcDigest,
      rustToolchainIdentity: rustToolchainIdentityToken(jobFingerprint)))
  let contractDigest = rustLaneExecutionContractDigest(
    sha256Hex(rendered.leanSource), extractionEvidenceDigest)
  let cleResult = newCanonicalLeanEvidence(
    obligationId = rendered.obligationId,
    proposition = rendered.proposition,
    leanSource = rendered.leanSource,
    kaa = kaa,
    toolchainFingerprint = receipt.receiptToolchainFingerprint,
    executionContractDigest = contractDigest)
  if cleResult.isErr:
    blockHere("evidence", cleResult.error)

  # Stage: attestation-time extraction re-compare (issuance time — the
  # declared-pin gate discipline). The landed job record is re-read through
  # the ledger's full identity chain and compared against the environment
  # THIS lane can honestly measure NOW: the Rust toolchain is MEASURED here
  # via the adapter (an absent measurement is unverifiable — fail-closed),
  # and the Charon identity is compared against the PINNED extraction-pin
  # constants (this lane never runs Charon; the pin SSOT is the consumer
  # repo's approved pin, quirk Q3). Violation AND unverifiability both fail
  # closed; recorded values stay RECORDED provenance.
  if provenanceArmed:
    let refetched = fetchExtractionJobRecord(extractionLedger.get,
                                             extractionLedgerRepo,
                                             result.extractionJobKey)
    if refetched.isErr:
      blockHere("provenance", refetched.error)
    let measuredNow = MeasuredExtractionEnvironment(
      fingerprint: rustToolchainFingerprint(""),
      charonPinCommit: PinnedCharonPinCommit,
      charonVersion: PinnedCharonVersion)
    let recompare = verifyExtractionEnvironment(refetched.get, measuredNow)
    if recompare.isErr:
      blockHere("provenance", recompare.error)

  # Stage: the EXISTING v3 writer with the extraction-bounded claim gate.
  # The claim is measured from THIS run; cert_writer re-verifies it at mint
  # (template allowlist + proposition co-bind + extractor identity).
  let claim = RustBoundedClaim(
    templateHash: rendered.templateHash,
    rustCanonicalDigest: result.irHash,
    obligationDigest: rendered.obligationDigest,
    extractorIdentity: rustExtractorIdentityDigest(rcheckExe))
  var logLines: seq[string] = @[]
  let wrote = writeCertificateFromUapResult(
    certDir, modulePath, funcName, sourceCode,
    leanKernelVerified = false,
    smtlib2 = "",
    solverStatus = "",
    logLines = logLines,
    vacuityProven = false,
    irHash = result.irHash,
    leanProposition = rendered.proposition,
    kaa = some(kaa),
    evidence = some(cleResult.get()),
    rustBoundedClaim = some(claim),
    axiomVersion = axiomVersion)
  if not wrote:
    var detail = ""
    for line in logLines:
      detail = line  # the last log line names the writer's refusal
    blockHere("writer", detail)
  result.issued = true
  result.certPath = joinPath(certDir, result.irHash & ".json")

{.pop.}
