import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

## Proof State Machine — pure transition functions for obligation lifecycle.
##
## Implements the state machine defined in docs/spec/obligation_semantics.md §7.
## Phase (workflow progress) and Terminal Result (final verdict) are separate
## fields, isolated from each other.
##
## Transition diagram (§7.3):
##   Candidate → Analyzed → ObligationDecision → ProofAttempted → Terminal
##
## 4-way decideObligations routing:
##   ogrNoApplicableObligation → Terminal(ptNoApplicableObligation)
##   ogrUnsupported            → Terminal(ptUnsupported)
##   ogrIllFormed              → Terminal(ptIllFormed)
##   ogrGenerated              → phase=ObligationDecision (terminal = none)
##
## attemptProof backend outcomes:
##   proved    → phase=Terminal, terminal=Some(ptProved)
##   refuted   → phase=Terminal, terminal=Some(ptRefuted)
##   error     → phase=Terminal, terminal=Some(ptInconclusive), errorDetail set
##   artifact invalid → phase=Terminal, terminal=Some(ptInvalidArtifact),
##                      artifact reason (parse/elaboration/kernel) set
##
## Invariants enforced by transitions:
##   - Invalid transitions return Err("reason")
##   - Terminal states reject all further transitions
##   - Generated obligations never carry a terminal value
##   - NoApplicable/Unsupported/IllFormed always reach terminal immediately

import std/[options]
import core/trusted/axiom_pragmas_lite
import verification/obligation/obligation_types
import verification/obligation/obligation_ir

# ---------------------------------------------------------------------------
# InternalError — captures backend failure context for inconclusive results
# ---------------------------------------------------------------------------

type
  InternalError* = object
    code*: string       ## machine-readable error code (e.g. "TIMEOUT", "OOM")
    detail*: string     ## human-readable description

# ---------------------------------------------------------------------------
# Event types — discriminated union of possible events
# ---------------------------------------------------------------------------

type
  ProofEvent* = enum
    peSettleProved      ## backend returned proved
    peSettleRefuted     ## backend returned refuted
    peSettleError       ## backend returned error/InternalError
    peSettleInvalidArtifact ## backend artifact (e.g. generated Lean) was
                        ## structurally invalid: parse/elaboration/kernel rejection

# ---------------------------------------------------------------------------
# Transition result type — pure functional, no exceptions under raises:[]
# ---------------------------------------------------------------------------

type
  TransitionResult*[T] = ref object
    case ok*: bool
    of true:
      value*: T
    of false:
      reason*: string

func okResult*[T](v: T): TransitionResult[T] {.axiomDecision(
  id = "DECISION-0810",
  reason = "Canonical ok-path constructor for TransitionResult — successful transitions of the obligation proof state machine",
  adr = "docs/spec/obligation_semantics.md",
  introduced = "v39").} =
  TransitionResult[T](ok: true, value: v)

func errResult*[T](r: string): TransitionResult[T] {.axiomDecision(
  id = "DECISION-0811",
  reason = "Fail-closed constructor for TransitionResult — failed transitions carry the rejection reason",
  adr = "docs/spec/obligation_semantics.md",
  introduced = "v39").} =
  TransitionResult[T](ok: false, reason: r)

func isOk*[T](r: TransitionResult[T]): bool {.inline, raises: [], axiomDecision(
  id = "DECISION-0812",
  reason = "Pure discriminator over TransitionResult — splits the ok/err arms of the state-machine result type",
  adr = "docs/spec/obligation_semantics.md",
  introduced = "v39").} = r.ok

# ---------------------------------------------------------------------------
# Helper: build initial candidate outcome
# ---------------------------------------------------------------------------

func makeCandidate*(detail: string = ""): ObligationOutcome =
  ObligationOutcome(phase: ppCandidate, terminal: none(ProofTerminal), detail: detail)

# ---------------------------------------------------------------------------
# C0 invariant: empty-obligation canonical form
# ---------------------------------------------------------------------------

func isCanonicalEmpty*(o: ObligationOutcome): bool {.raises: [].} =
  ## Returns true when o represents the unique canonical form for zero obligations:
  ## phase == ppTerminal AND terminal == Some(ptNoApplicableObligation).
  o.phase == ppTerminal and o.terminal.isSome and
    o.terminal.get == ptNoApplicableObligation

# ---------------------------------------------------------------------------
# Terminal-state guard — shared by all transitions
# ---------------------------------------------------------------------------

func assertNotTerminal*(o: ObligationOutcome): TransitionResult[ObligationOutcome] {.axiomDecision(
  id = "DECISION-0813",
  reason = "Shared terminal-state guard for all state-machine transitions — terminal outcomes reject further transitions",
  adr = "docs/spec/obligation_semantics.md",
  introduced = "v39").} =
  if o.phase == ppTerminal:
    errResult[ObligationOutcome]("cannot transition from terminal state")
  else:
    okResult(o)

# ---------------------------------------------------------------------------
# analyze — Candidate → Analyzed
# ---------------------------------------------------------------------------

func analyze*(outcome: ObligationOutcome): TransitionResult[ObligationOutcome] {.axiomDecision(
  id = "DECISION-0814",
  reason = "Candidate → Analyzed transition — the single allowed advance from the candidate phase",
  adr = "docs/spec/obligation_semantics.md",
  introduced = "v39").} =
  ## Advance from Candidate to Analyzed.
  ## Rejects if already in Terminal or any non-Candidate phase.
  let g = assertNotTerminal(outcome)
  if not g.isOk: return errResult[ObligationOutcome]("state not candidate: cannot analyze")
  let base = g.value
  if base.phase != ppCandidate:
    return errResult[ObligationOutcome]("analyze requires phase=Candidate, got " & $base.phase)
  okResult(ObligationOutcome(
    phase: ppAnalyzed,
    terminal: none(ProofTerminal),
    detail: base.detail & "|analyzed"
  ))

# ---------------------------------------------------------------------------
# decideObligations — Analyzed → ObligationDecision OR Terminal
# ---------------------------------------------------------------------------

func decideObligations*(
  outcome: ObligationOutcome,
  genResult: ObligationGenerationResult
): TransitionResult[ObligationOutcome] {.axiomDecision(
  id = "DECISION-0815",
  reason = "Analyzed → ObligationDecision/Terminal 4-way routing from the generation-result classification",
  adr = "docs/spec/obligation_semantics.md",
  introduced = "v39").} =
  ## Route based on generation result variant.
  ##
  ## ogrGenerated        → phase=ObligationDecision, terminal=none
  ## ogrNoApplicable     → phase=Terminal, terminal=ptNoApplicableObligation
  ## ogrUnsupported      → phase=Terminal, terminal=ptUnsupported
  ## ogrIllFormed        → phase=Terminal, terminal=ptIllFormed
  let g = assertNotTerminal(outcome)
  if not g.isOk: return errResult[ObligationOutcome]("state not analyzed: cannot decide")
  let base = g.value
  if base.phase != ppAnalyzed:
    return errResult[ObligationOutcome]("decideObligations requires phase=Analyzed, got " & $base.phase)

  case genResult.kind
  of ogrGenerated:
    okResult(ObligationOutcome(
      phase: ppObligationDecision,
      terminal: none(ProofTerminal),
      detail: base.detail & "|generated:" & $genResult.obligations.len
    ))
  of ogrNoApplicableObligation:
    okResult(ObligationOutcome(
      phase: ppTerminal,
      terminal: some(ptNoApplicableObligation),
      detail: base.detail & "|noApplicable:" & genResult.provenance.derivationRule
    ))
  of ogrUnsupported:
    okResult(ObligationOutcome(
      phase: ppTerminal,
      terminal: some(ptUnsupported),
      detail: base.detail & "|unsupported:" & $genResult.unsupportedReason
    ))
  of ogrIllFormed:
    okResult(ObligationOutcome(
      phase: ppTerminal,
      terminal: some(ptIllFormed),
      detail: base.detail & "|illFormed:" & $genResult.illFormedReason
    ))

# ---------------------------------------------------------------------------
# attemptProof — ObligationDecision → ProofAttempted
# ---------------------------------------------------------------------------

func attemptProof*(outcome: ObligationOutcome): TransitionResult[ObligationOutcome] {.axiomDecision(
  id = "DECISION-0816",
  reason = "ObligationDecision → ProofAttempted transition — marks proof attempt initiation",
  adr = "docs/spec/obligation_semantics.md",
  introduced = "v39").} =
  ## Mark that a proof attempt has been initiated.
  ## Only valid from ppObligationDecision phase.
  let g = assertNotTerminal(outcome)
  if not g.isOk: return errResult[ObligationOutcome]("state not decision: cannot attempt proof")
  let base = g.value
  if base.phase != ppObligationDecision:
    return errResult[ObligationOutcome]("attemptProof requires phase=ObligationDecision, got " & $base.phase)
  okResult(ObligationOutcome(
    phase: ppProofAttempted,
    terminal: none(ProofTerminal),
    detail: base.detail & "|attempting"
  ))

# ---------------------------------------------------------------------------
# settleProof — ProofAttempted → Terminal
# ---------------------------------------------------------------------------

func settleProof*(
  outcome: ObligationOutcome,
  event: ProofEvent,
  errorInfo: InternalError = InternalError(code: "", detail: ""),
  artifactReason: ArtifactReason = arParseError,
  inconclusiveReason: InconclusiveReason = irUnknown
): TransitionResult[ObligationOutcome] {.axiomDecision(
  id = "DECISION-0817",
  reason = "ProofAttempted → Terminal verdict resolution; ptProved/ptRefuted reachable only via evidence-backed settle events",
  adr = "docs/spec/obligation_semantics.md",
  introduced = "v39").} =
  ## Resolve a proof attempt to a terminal verdict.
  ##
  ## peSettleProved          → terminal=ptProved
  ## peSettleRefuted         → terminal=ptRefuted
  ## peSettleError           → terminal=ptInconclusive + inconclusiveReason
  ## peSettleInvalidArtifact → terminal=ptInvalidArtifact + artifactReason
  ##
  ## Evidence guard: ptProved/ptRefuted are reachable ONLY via the
  ## peSettleProved/peSettleRefuted events.  Callers MUST raise those events
  ## only after validated evidence exists (kernel-replayed certificate accepted
  ## by the validation layer); this module never fabricates a positive verdict
  ## itself — the enforcement point is the caller.
  let g = assertNotTerminal(outcome)
  if not g.isOk: return errResult[ObligationOutcome]("state not attempted: cannot settle")
  let base = g.value
  if base.phase != ppProofAttempted:
    return errResult[ObligationOutcome]("settleProof requires phase=ProofAttempted, got " & $base.phase)

  var terminalVal: ProofTerminal
  case event
  of peSettleProved:
    terminalVal = ptProved
  of peSettleRefuted:
    terminalVal = ptRefuted
  of peSettleError:
    terminalVal = ptInconclusive
  of peSettleInvalidArtifact:
    terminalVal = ptInvalidArtifact

  var terminalReason: Option[TerminalReason]
  case event
  of peSettleError:
    terminalReason = some(TerminalReason(inconclusive: some(inconclusiveReason)))
  of peSettleInvalidArtifact:
    terminalReason = some(TerminalReason(artifact: some(artifactReason)))
  else:
    discard  # proved/refuted carry no typed reason

  var detail = base.detail & "|settled:" & $terminalVal
  if errorInfo.code.len > 0 or errorInfo.detail.len > 0:
    detail &= "(err:" & errorInfo.code & ":" & errorInfo.detail & ")"
  if event == peSettleInvalidArtifact:
    detail &= "(artifact:" & $artifactReason & ")"

  okResult(ObligationOutcome(
    phase: ppTerminal,
    terminal: some(terminalVal),
    detail: detail,
    reason: terminalReason
  ))

# ---------------------------------------------------------------------------
# Convenience: single-step pipeline from candidate through full lifecycle
# ---------------------------------------------------------------------------

func runPipeline*(
  genResult: ObligationGenerationResult,
  proofEvent: ProofEvent = peSettleProved,
  errorInfo: InternalError = InternalError(code: "", detail: ""),
  artifactReason: ArtifactReason = arParseError,
  inconclusiveReason: InconclusiveReason = irUnknown
): TransitionResult[ObligationOutcome] {.axiomDecision(
  id = "DECISION-0818",
  reason = "Single-step pipeline analyze → decide → attempt → settle with early-exit on non-generated terminal results",
  adr = "docs/spec/obligation_semantics.md",
  introduced = "v39").} =
  ## Execute the full pipeline: analyze → decide → attempt → settle.
  ## For non-generated results, settle steps are skipped (already terminal).
  ## proofEvent/errorInfo/artifactReason/inconclusiveReason are forwarded to
  ## settleProof for the generated path.
  var o = makeCandidate()

  # Step 1: analyze
  let a = analyze(o)
  if not a.isOk: return errResult[ObligationOutcome]("analyze failed: " & a.reason)
  o = a.value

  # Step 2: decide
  let d = decideObligations(o, genResult)
  if not d.isOk: return errResult[ObligationOutcome]("decide failed: " & d.reason)
  o = d.value

  # If already terminal (non-generated), stop here
  if o.phase == ppTerminal:
    return okResult(o)

  # Step 3: attempt proof
  let ap = attemptProof(o)
  if not ap.isOk: return errResult[ObligationOutcome]("attemptProof failed: " & ap.reason)
  o = ap.value

  # Step 4: settle
  let s = settleProof(o, proofEvent, errorInfo, artifactReason, inconclusiveReason)
  if not s.isOk: return errResult[ObligationOutcome]("settleProof failed: " & s.reason)
  okResult(s.value)

{.pop.}
