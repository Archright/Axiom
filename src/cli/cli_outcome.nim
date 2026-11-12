import core/trusted/layer_declaration
import core/utils/decision_algebra
axiomLayer "presentation"
{.push raises: [CatchableError].}

## CliOutcome — canonical CLI exit-state enum.
## One enum, one mapping function, one exit boundary.
## Declaration order IS the severity order (lowest ordinal first) — the r7
## contract §State Precedence Rule; machine-checked directly via `ord` in
## tests. Outcome aggregation precedence lives in the decision layer
## (core/utils/decision_algebra.projectRunOutcome), not here.
## See docs/design/r7_cli_outcome_contract.md for the full contract.

type
  CliOutcome* = enum
    SUCCESS              # Verification ran; no failures
    NOT_CURRENT          # Artifact is valid but not current product truth (stale toolchain / execution contract)
    VERIFICATION_FAILURE # Verification ran; >=1 failed node / 0 verified (artifact integrity violation)
    INVALID_INPUT        # CLI argument / schema error
    INTERNAL_ERROR       # Normal-classifiable internal error (Nim exception)

## exitCode — the single mapping from CliOutcome → process exit code.
## This is the ONLY place that maps CliOutcome → int.
## Exit code 4 is reserved for NOT_CURRENT: valid artifact but not current product truth.
func exitCode*(o: CliOutcome): int {.raises: [].} =
  case o
  of CliOutcome.SUCCESS:
    0
  of CliOutcome.NOT_CURRENT:
    4  # valid artifact, not current product truth — not a failure
  of CliOutcome.VERIFICATION_FAILURE:
    1
  of CliOutcome.INTERNAL_ERROR:
    2
  of CliOutcome.INVALID_INPUT:
    3

## cliOutcomeForRun — the exit projection of one run decision.
## The decision (core/utils/decision_algebra.projectRunOutcome) keeps the
## BLOCK / UNRESOLVED distinction — claims not established by a failure vs. by
## an incomplete run. The exit axis is deliberately coarse: both mean
## "verification claims not established" → exit 1 (contract §7).
func cliOutcomeForRun*(outcome: string): CliOutcome {.raises: [].} =
  if outcome == OutcomeContinue: CliOutcome.SUCCESS
  else: CliOutcome.VERIFICATION_FAILURE

## runExitCode — the single collapse of one run decision onto the exit axis:
## decision string → CliOutcome → process exit code. Run-report consumers call
## this instead of re-inlining the composition, so the collapse has one body.
func runExitCode*(outcome: string): int {.raises: [].} =
  exitCode(cliOutcomeForRun(outcome))

## CliError — a Result error payload that carries the outcome class alongside a
## diagnostic message.  Lets channel errors through Result[T, CliError] so that a
## downstream interpreter can map each error to the canonical exit code without
## collapsing distinct failure classes into a single INTERNAL_ERROR.
type
  CliError* = object
    kind*: CliOutcome     ## SUCCESS is never used as an error kind (callers set the real class).
    msg*: string

## exitWith — single choke-point for all CLI dispatch paths to terminate.
## Every CLI path that previously called quit() directly should route through
## this proc instead.  It applies the canonical mapping and then calls quit().
proc exitWith*(o: CliOutcome) {.noreturn, raises: [].} =
  quit(exitCode(o))

## exitWithCliError — terminate with the exit code of the given error's kind.
proc exitWithCliError*(e: CliError) {.noreturn, raises: [].} =
  exitWith(e.kind)

{.pop.}
