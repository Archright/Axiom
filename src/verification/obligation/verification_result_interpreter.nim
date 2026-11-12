import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

import verification/solver_adapter
import std/[options, sets, strutils]
import core/results
import core/trusted/axiom_pragmas

# ---------------------------------------------------------------------------
# QuerySemantics — controls how solver status maps to semantic outcome
# ---------------------------------------------------------------------------

type
  QuerySemantics* = enum
    qsStandard              # solver status → semantic verdict via standard mapping
    qsDirect                # pass-through for tests that supply status directly

  SemanticOutcome* = enum
    smOutcomeUnsat          # validity established
    smOutcomeSat            # counterexample (would be found)
    smOutcomeUnknown
    smOutcomeTimeout
    smOutcomeResourceLimit
    smOutcomeProcessError
    smOutcomeParseError
    smOutcomeNotExecuted    # no attempt reached a solver
    smOutcomeFailedClosed   # result absent → fail-closed unknown

  QuerySemanticsResult* = object
    rawSolverStatus*: string
    semanticOutcome*: SemanticOutcome
    failClosed*: bool        # true when input incomplete → failed-closed unknown

# ---------------------------------------------------------------------------
# parseSolverStatus — string → SolverStatus (local helper)
# ---------------------------------------------------------------------------

func parseSolverStatus*(s: string): SolverStatus {.raises: [].} =
  case s.toLowerAscii()
  of "unsat": sosUnsat
  of "sat": sosSat
  of "unknown": sosUnknown
  of "timeout": sosTimeout
  of "resourcelimit": sosResourceLimit
  of "processerror": sosProcessError
  of "parseerror": sosParseError
  else: sosUnknown

# ---------------------------------------------------------------------------
# interpretQueryResult — SolverStatus → SemanticOutcome (standard mapping)
# ---------------------------------------------------------------------------

func interpretQueryResult*(status: SolverStatus): SemanticOutcome {.raises: [].} =
  case status
  of sosUnsat: smOutcomeUnsat
  of sosSat: smOutcomeSat
  of sosUnknown: smOutcomeUnknown
  of sosTimeout: smOutcomeTimeout
  of sosResourceLimit: smOutcomeResourceLimit
  of sosProcessError: smOutcomeProcessError
  of sosParseError: smOutcomeParseError

# ---------------------------------------------------------------------------
# interpretQueryResult — fail-closed over Option[string]
# ---------------------------------------------------------------------------

func interpretQueryResult*(raw: Option[string]): QuerySemanticsResult {.axiomDecision, raises: [].} =
  if raw.isNone():
    QuerySemanticsResult(
      rawSolverStatus: "",
      semanticOutcome: smOutcomeFailedClosed,
      failClosed: true)
  else:
    let status = parseSolverStatus(raw.get())
    QuerySemanticsResult(
      rawSolverStatus: $status,
      semanticOutcome: interpretQueryResult(status),
      failClosed: false)

# ---------------------------------------------------------------------------
# Obligation Execution Ledger types — canonical definitions (v10)
# ---------------------------------------------------------------------------
# These are the single source of truth for the obligation execution ledger.
# ir_pipeline_runner.nim imports them from here (no duplicate definitions).

type
  ObligationExecutionRecord* = object
    generatedObligationIds*: seq[string]
    plans*: seq[PlanExecutionRecord]
    terminalOutcome*: Option[SemanticOutcome]
    droppedObligations*: seq[DroppedObligationRecord]

  PlanExecutionRecord* = object
    planRevision*: int
    obligationId*: string
    attempts*: seq[AttemptRecord]

  AttemptRecord* = object
    attemptNumber*: int
    solverInvocationId*: string
    solverInputDigest*: string
    canonicalEnvelopeDigest*: string
    transportPayloadDigest*: string
    rawSolverStatus*: string
    semanticAttemptOutcome*: SemanticOutcome
    derivationProvenance*: string

  DroppedObligationRecord* = object
    obligationId*: string
    dropReason*: string
    planRevision*: int

# ---------------------------------------------------------------------------
# checkTerminalAttribution — O11: terminal attribution completeness
# ---------------------------------------------------------------------------
## Verifies that every generated obligationId has exactly one terminal account
## (either a plan attempt or a drop record), and that drops are well-formed.
## Returns ok() if all rules pass, err(message) on the first violation.

func checkTerminalAttribution*(ledger: ObligationExecutionRecord): Result[void, string] {.axiomDecision, raises: [].} =
  let generated = ledger.generatedObligationIds
  let plans = ledger.plans
  let drops = ledger.droppedObligations

  # Build sets of obligationIds that appear in plans and drops.
  var planOblIds: HashSet[string]
  for plan in plans:
    planOblIds.incl(plan.obligationId)

  var dropOblIds: HashSet[string]
  for drop in drops:
    if drop.dropReason.len == 0:
      return err("drop without reason for obligationId: " & drop.obligationId)
    if dropOblIds.contains(drop.obligationId):
      return err("duplicate drop for obligationId: " & drop.obligationId)
    dropOblIds.incl(drop.obligationId)

  for oid in generated:
    let inPlan = planOblIds.contains(oid)
    let inDrop = dropOblIds.contains(oid)
    if not inPlan and not inDrop:
      return err("generatedObligationId has 0 terminal accounts: " & oid)
    if inPlan and inDrop:
      return err("generatedObligationId has both a terminal account and an explicit drop: " & oid)

  for drop in drops:
    if not generated.contains(drop.obligationId):
      return err("drop for unknown obligationId: " & drop.obligationId)

  result = Result[void, string](ok: true)

{.pop.}