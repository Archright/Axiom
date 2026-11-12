import std/unittest
import cli/cli_outcome
import core/utils/decision_algebra

suite "R7 CliOutcome 5-state gold matrix (design/r7_cli_outcome_contract.md)":

  test "SUCCESS maps to exit code 0":
    check exitCode(CliOutcome.SUCCESS) == 0

  test "NOT_CURRENT maps to exit code 4":
    check exitCode(CliOutcome.NOT_CURRENT) == 4

  test "VERIFICATION_FAILURE maps to exit code 1":
    check exitCode(CliOutcome.VERIFICATION_FAILURE) == 1

  test "INTERNAL_ERROR maps to exit code 2":
    check exitCode(CliOutcome.INTERNAL_ERROR) == 2

  test "INVALID_INPUT maps to exit code 3":
    check exitCode(CliOutcome.INVALID_INPUT) == 3

  test "INV-1: no internal error is ever mapped to SUCCESS(0)":
    check exitCode(CliOutcome.INTERNAL_ERROR) != 0

  test "INV-7: mapping is bijective within valid range {0,1,2,3,4}":
    let codes = @[exitCode(CliOutcome.SUCCESS),
                  exitCode(CliOutcome.NOT_CURRENT),
                  exitCode(CliOutcome.VERIFICATION_FAILURE),
                  exitCode(CliOutcome.INTERNAL_ERROR),
                  exitCode(CliOutcome.INVALID_INPUT)]
    check codes.len == 5
    for i in 0 ..< codes.high:
      for j in i+1 ..< codes.high:
        check codes[i] != codes[j]
    for c in codes:
      check c >= 0 and c <= 4

  test "severity order: INTERNAL_ERROR > INVALID_INPUT > VERIFICATION_FAILURE > NOT_CURRENT > SUCCESS":
    ## The documented precedence (r7 contract §State Precedence Rule) is the
    ## enum declaration order (ascending severity), machine-checked directly
    ## via ordinals: SUCCESS(0) < NOT_CURRENT(1) < VERIFICATION_FAILURE(2) <
    ## INVALID_INPUT(3) < INTERNAL_ERROR(4).
    check ord(CliOutcome.SUCCESS) < ord(CliOutcome.NOT_CURRENT)
    check ord(CliOutcome.NOT_CURRENT) < ord(CliOutcome.VERIFICATION_FAILURE)
    check ord(CliOutcome.VERIFICATION_FAILURE) < ord(CliOutcome.INVALID_INPUT)
    check ord(CliOutcome.INVALID_INPUT) < ord(CliOutcome.INTERNAL_ERROR)

  test "cliOutcomeForRun: CONTINUE -> SUCCESS(0), BLOCK/UNRESOLVED -> VERIFICATION_FAILURE(1)":
    ## The decision keeps the BLOCK/UNRESOLVED distinction; the exit axis is
    ## deliberately coarse — both are exit 1 (contract §7).
    check cliOutcomeForRun(OutcomeContinue) == CliOutcome.SUCCESS
    check cliOutcomeForRun(OutcomeBlock) == CliOutcome.VERIFICATION_FAILURE
    check cliOutcomeForRun(OutcomeUnresolved) == CliOutcome.VERIFICATION_FAILURE
    check exitCode(cliOutcomeForRun(OutcomeContinue)) == 0
    check exitCode(cliOutcomeForRun(OutcomeBlock)) == 1
    check exitCode(cliOutcomeForRun(OutcomeUnresolved)) == 1

  test "runExitCode: the single decision→exit collapse matches the two-step composition":
    ## runExitCode is the one body for decision→CliOutcome→exit; consumers
    ## (wf_runners) must not re-inline the composition (one path, one result).
    check runExitCode(OutcomeContinue) == 0
    check runExitCode(OutcomeBlock) == 1
    check runExitCode(OutcomeUnresolved) == 1
    check runExitCode("NOT_A_DECISION") == 1

  test "cliOutcomeForRun: an unknown decision is read as not established (fail-closed)":
    check cliOutcomeForRun("NOT_A_DECISION") == CliOutcome.VERIFICATION_FAILURE
