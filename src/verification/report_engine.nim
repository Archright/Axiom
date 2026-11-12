import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [CatchableError].}

## Report Engine — Business logic for `ax report`.
##
## Extracted from src/cli/report_cli.nim to decouple CLI flag parsing
## (Presentation) from proof-state analysis (Infrastructure).

import std/json
import std/os
import core/results
import core/trusted/axiom_pragmas
import core/utils/decision_algebra
import verification/accounting/execution_context
import verification/accounting/run_accounting
import verification/obligation/verification_decision_authority
# axiomIoBoundary

proc loadReportProofState*(stateFilePath: string): Result[JsonNode, string] {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Load a proof-state JSON file and re-validate its recorded verdict against
  ## the CURRENT execution context before handing it out.
  ##
  ## A proof state is cache-derived state: it can be restored from a vault that
  ## outlived the run that produced it, and the file carries the run's own
  ## numbers — so reading it as-is would let a restored `[VERIFIED]` reach the
  ## verdict while the tree that would produce it fails. Read-time identity
  ## re-validation (execution_accounting_contract.md §15.3) is the gate: the
  ## state must carry the execution identity it was produced under AND that
  ## identity must equal the one measured now.
  ##
  ## Failure is NOT an error — the document is returned fail-closed by
  ## verification_decision_authority.evaluateRestoredStateRunOutcome: its
  ## REUSED-sourced units are demoted to PENDING, an anomaly is recorded, and
  ## the run verdict is re-decided there under §17 with the identity-binding
  ## precondition of §17.1. That authority — not this module — writes
  ## verdict/basis/gateVerdict; a state whose envelope cannot be bound reads
  ## INCONCLUSIVE even when it reused nothing, because an unbound identity can
  ## assert a satisfaction but never a PASS. Genuine fresh-execution rows are
  ## untouched, so a real fresh run still reads exactly as it recorded.
  ##
  ## The re-measurement is the IO half; the re-validation is a pure projection
  ## (revalidateRestoredStateIdentity) and the exit code stays the single §7
  ## run-exit rule over the summary — the verdict itself is carried by
  ## `runOutcome.gateVerdict`.
  if not fileExists(stateFilePath):
    return err("proof state not found: " & stateFilePath)
  var stateJson: JsonNode
  try:
    stateJson = parseFile(stateFilePath)
  except CatchableError as e:
    return err("failed to parse proof state: " & e.msg)
  # Fail-closed measurement: an unmeasurable context re-validates nothing, so a
  # catch here leaves the envelope unpinned and the state demoted below.
  let currentCtx = try: captureReuseVerificationContext()
                     except CatchableError: defaultReuseVerificationContext()
  let reval = revalidateRestoredStateIdentity(stateJson, currentCtx)
  if reval.established:
    ok(stateJson)
  else:
    ok(evaluateRestoredStateRunOutcome(stateJson, reval))

func computeReportExitCode*(stateJson: JsonNode): int {.raises: [].} =
  ## Thin exit-axis projection over the single run-exit rule.
  ## THE RULE is core/utils/decision_algebra.projectRunOutcome — a missing or
  ## malformed summary is UNRESOLVED there (fail-closed), so this function does
  ## not re-check it. The 3-value → exit-code case below is an adapter only:
  ## src/verification/ may not import src/cli/ (data/import_rules.json), so the
  ## mapping is expressed as int instead of calling cli/cli_outcome.
  ##
  ## Identity re-validation is NOT re-derived here: it produced the document
  ## (see loadReportProofState) and is carried by `runOutcome.verdict` /
  ## `gateVerdict`. `summary` stays raw telemetry — a stale state leaves the
  ## counts it recorded and reports them, while the verdict beside them reads
  ## FAIL.
  case projectRunOutcome(stateJson)
  of OutcomeContinue: 0
  of OutcomeBlock, OutcomeUnresolved: 1
  else: 1
{.pop.}
