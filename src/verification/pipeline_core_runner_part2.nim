import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [CatchableError].}

import std/os
import std/strutils
import core/utils/file_utils
import core/utils/text_utils
import core/results
import core/domain_types
import core/pipeline_core_types
import verification/pipeline_core_runner_part1
import ../core/trusted/axiom_pragmas
# axiomIoBoundary

## Write Bdd Feature.
proc writeBddFeature*(
  req: UniversalPipelineRequest;
  initial: NegativeInvariantScan
): Result[string, AxiomError] {.raises: [CatchableError], axiom: ["(assert (and external_io_isolated))", "external_io_isolated"], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  try:
    ensureDirectoryTree(req.bddDir)
    let fileName = sanitizeToken(req.functionName) & "_uap_counterexamples.feature"
    let featurePath = joinPath(req.bddDir, fileName)
    var lines: seq[string] = @[]
    lines.add("Feature: UAP automatic counterexample fixation")
    for hit in initial.hits:
      lines.add("")
      lines.add("  Scenario: Fix " & $hit.hit.kind & " counterexample in " & req.functionName)
      lines.add("    Given target function is " & req.functionName & " from " & req.modulePath)
      lines.add("    And violated property is " & hit.violatedProperty)
      lines.add("    And counterexample input is " & hit.counterExampleInput)
      lines.add("    When UAP auto-fix and re-verification is performed")
      lines.add("    Then the vulnerability should be reproducible")
      lines.add("    And ASI should be 1.0000 after recovery")
    discard writeFileSafe(featurePath, lines.join("\n"))
    ok(normalizePathSeparators(featurePath))
  except CatchableError:
    err(axiomErrFileSystemError)
{.pop.}
