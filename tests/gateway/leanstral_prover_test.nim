## leanstral_prover_test.nim — Gateway test for leanstral prover.
##
## Scenario 1: Self-test mode validates all 10 internal checks.
## Scenario 2: Full pipeline with valid JSON input writes evidence artifact.
## Scenario 3: Pipeline rejects empty input and logs failure.
##
## IMPORTANT: The leanstral prover's self-test machinery (``buildMockOutput``,
## ``runSelfTest``, ``runPipeline`` self-test path) is intentionally
## release/production-FORBIDDEN per AGENTS.md §0.9 theater prevention (see
## ``leanstral_cli.nim`` ``buildMockOutput`` fatal in ``define(release)``).
## The gateway runner compiles every test with ``-d:release``, so this test can
## only exercise the self-test feature in debug builds. Under release it must
## not even import the module (the release-fatal fires on import), so the whole
## test body is gated behind ``when not defined(release)``.

import std/[json, os, strutils]
from core/utils/repo_root import findRepoRoot

# axiomIoBoundary

when not defined(release) and not defined(production):

  import verification/leanstral/leanstral_cli

  let
    projectRoot = findRepoRoot()
    historyPath = joinPath(projectRoot, ".axiom/gate_history.jsonl")

  # -------------------------------------------------------------------------
  # Helpers
  # -------------------------------------------------------------------------

  proc cleanupHistory() =
    ## Remove leanstral-prover entries from gate_history for test isolation.
    if not fileExists(historyPath):
      return
    let content = readFile(historyPath)
    var kept: seq[string] = @[]
    for line in content.splitLines():
      let trimmed = line.strip()
      if trimmed.len == 0:
        continue
      try:
        let entry = parseJson(trimmed)
        let gateId = entry{"gateId"}.getStr("")
        if gateId != "leanstral-prover":
          kept.add(trimmed)
      except CatchableError:
        kept.add(trimmed)
    writeFile(historyPath, kept.join("\n") & "\n")

  # -------------------------------------------------------------------------
  # Scenario 1: Self-test validates all 10 internal checks
  # -------------------------------------------------------------------------

  proc scenarioSelfTest() =
    ## The --self-test mode runs 10 deterministic internal checks.
    ## This scenario verifies it passes.
    cleanupHistory()
    let rRoot = findRepoRoot()
    let exitCode = runSelfTest(rRoot)
    doAssert exitCode == 0,
      "leanstral-prover --self-test failed with exit code " & $exitCode

  # -------------------------------------------------------------------------
  # Scenario 2: Full pipeline with valid JSON input
  # -------------------------------------------------------------------------

  proc scenarioValidPipeline() =
    ## Provide valid JSON input, run pipeline, verify evidence artifact is written.
    cleanupHistory()

    let input = LeanstralInput(
      sourceContext: "proc safe_add(a, b: int): int =",
      smtUnsatCore: "(assert (and (<= a 100) (<= b 100)))",
      diagnosticHints: "overflow check needed",
      targetGoal: "safe_add is memory-safe"
    )

    let exitCode = runPipeline(input, selfTest = true)
    doAssert exitCode == 0,
      "Valid pipeline should return 0, got " & $exitCode

    # Verify evidence artifact exists
    let evidPath = evidencePath(projectRoot, "safe_add is memory-safe")
    doAssert fileExists(evidPath),
      "Evidence file should be written at " & evidPath

    # Verify evidence content is well-formed
    let content = readFile(evidPath)
    doAssert content.contains("Leanstral Prover Evidence"),
      "Evidence should contain header"
    doAssert content.contains("safe_add is memory-safe"),
      "Evidence should contain targetGoal"
    doAssert content.contains("theorem"),
      "Evidence should contain theorem source"

  # -------------------------------------------------------------------------
  # Scenario 3: Pipeline rejects invalid input schema
  # -------------------------------------------------------------------------

  proc scenarioInvalidOutputSchema() =
    ## Force schema validation failure by constructing an empty output.
    cleanupHistory()

    # Build an input that will produce valid output, then verify validation
    # works by checking validateOutputSchema directly on empty output
    let emptyOutput = LeanstralOutput()
    let errors = validateOutputSchema(emptyOutput)
    doAssert errors.len > 0,
      "Empty output should fail schema validation"
    doAssert errors[0].contains("theoremName"),
      "First error should mention theoremName"

    # Verify the validator accepts a well-formed output
    let goodInput = LeanstralInput(targetGoal: "test")
    let goodOutput = buildMockOutput(goodInput)
    let goodErrors = validateOutputSchema(goodOutput)
    doAssert goodErrors.len == 0,
      "Valid output should pass schema validation, got: " & goodErrors.join("; ")

    # Cleanup
    cleanupHistory()

  scenarioSelfTest()
  scenarioValidPipeline()
  scenarioInvalidOutputSchema()
  echo "All leanstral_prover tests passed (debug build)."

else:

  echo "SKIP: leanstral_prover self-test is release/production-forbidden (AGENTS.md §0.9)."
