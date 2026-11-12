import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

import std/os
import std/osproc
import std/streams
import std/strutils
import std/times
import core/lean_lsp_types
export lean_lsp_types
import verification/lean_lsp_protocol
import core/utils/file_utils
import core/proof/proof_budget
import core/sync/sync_utils_process
import core/logic/lean_diagnostic
import core/axiom_pragmas
# axiomIoBoundary
proc runLeanCompiler(artifactPath: string; leanExe: string = ""): LeanCompilerResult {.gcsafe, raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, TimeEffect, RootEffect].} =
  let normalizedArtifactPath = absolutePath(artifactPath)
  result.artifactPath = normalizedArtifactPath
  if normalizedArtifactPath.len == 0 or not fileExists(normalizedArtifactPath):
    result.exitCode = -1
    result.diagnostics = @[LeanDiagnostic(
      line: 0,
      character: 0,
      severity: 1,
      message: "missing lean artifact"
    )]
    return result
  try:
    let resolvedLeanCommand = tryResolveLeanExe(leanExe)
    var combinedOutput = ""
    var exitCode = 0
    if resolvedLeanCommand.len > 0:
      let isFullCommand = ' ' in resolvedLeanCommand
      # Lake-based commands need the project root (where lakefile.toml lives) as working dir
      var workingDir = ""
      if isFullCommand and resolvedLeanCommand.startsWith("lake "):
        var dir = parentDir(normalizedArtifactPath)
        for _ in 0 ..< 16:
          if fileExists(dir / "lakefile.toml") or fileExists(dir / "lakefile.lean"):
            workingDir = dir
            break
          let parent = parentDir(dir)
          if parent == dir:
            break
          dir = parent
      let process =
        if isFullCommand:
          startProcess(
            command = resolvedLeanCommand & " " & quoteShell(normalizedArtifactPath),
            options = {poEvalCommand, poStdErrToStdOut},
            workingDir = if workingDir.len > 0: workingDir else: ""
          )
        else:
          startProcess(
            command = resolvedLeanCommand,
            args = @[normalizedArtifactPath],
            options = {poUsePath, poStdErrToStdOut},
            workingDir = if workingDir.len > 0: workingDir else: ""
          )
      let timeoutMs = float(leanLspHardTimeoutMs)
      let startTime = epochTime() * 1000
      var timedOut = false
      while true:
        let code = peekExitCode(process)
        if code != -1:
          exitCode = code
          break
        if (epochTime() * 1000 - startTime) > timeoutMs:
          timedOut = true
          terminateProcessForce(process)
          exitCode = -9
          break
        sleep(50)
      if not timedOut:
        combinedOutput = process.outputStream().readAll()
      close(process)
      result.exitCode = exitCode
      result.output = combinedOutput
      if exitCode == 0:
        ## Fail-closed sorry gate: a successful compile is NOT sufficient.
        ## Reject if the combined output contains a `sorry` declaration or the
        ## sorryAx constants. See docs/spec/lean_sorry_gate.md (DEBT#296).
        let lowerOutput = combinedOutput.toLowerAscii()
        result.verified = not (
          "declaration uses 'sorry'" in lowerOutput or
          "sorryax" in lowerOutput or
          "lean.sorryax" in lowerOutput)
        if not result.verified:
          result.diagnostics = @[LeanDiagnostic(
            line: 0,
            character: 0,
            severity: 1,
            message: "Lean compiler rejected: sorry/sorryAx detected in output"
          )]
      else:
        result.verified = false
        result.diagnostics = @[LeanDiagnostic(
          line: 0,
          character: 0,
          severity: 1,
          message: (if timedOut: "Lean compiler timeout (>5s)" else: "Lean compiler failed: " & combinedOutput)
        )]
    else:
      result.exitCode = -1
      result.diagnostics = @[LeanDiagnostic(
        line: 0,
        character: 0,
        severity: 1,
        message: "lean.exe not found"
      )]
  except CatchableError as e:
    result.exitCode = -1
    result.diagnostics = @[LeanDiagnostic(
      line: 0,
      character: 0,
      severity: 1,
      message: "Lean compiler exception: " & e.msg
    )]

func findTacticConclusionAnchor(source: string): int {.raises: [].} =
  ## Index of the `:=` separating a theorem's type from its tactic proof,
  ## or -1. Renderer output uses either `:= by` (single line) or `:=\nby`
  ## (tactic block on the next line, cf. irFuncDefToTheorem), so the anchor
  ## accepts any whitespace run between `:=` and `by` and requires `by` to
  ## be the standalone keyword (not an identifier prefix such as `bytes`).
  ## Local port mirror: `lean_evidence.findTacticConclusionAnchor` — keep in
  ## sync (lean_evidence ports buildNegativeTestSource instead of importing
  ## this heavy module).
  var searchFrom = 0
  while true:
    let idx = source.find(":=", searchFrom)
    if idx < 0:
      return -1
    var after = idx + 2
    while after < source.len and source[after] in {' ', '\t', '\n', '\r'}:
      inc after
    if after + 2 <= source.len and source[after ..< after + 2] == "by" and
        (after + 2 == source.len or source[after + 2] notin IdentChars):
      return idx
    searchFrom = idx + 2

# @axiom-hint: lean="theoremSource.length ≥ 0" smt="(assert (and (>= (str.len theoremSource) 0)))"
# @axiom-hint: lean="idx < 0 ∧ colonIdx < 0 ∧ colonIdx = i ∧ (colonIdx ≥ 0)" smt="(assert (and (< idx 0) (< colonIdx 0) (= colonIdx i) (>= colonIdx 0)))"
func buildNegativeTestSource*(theoremSource: string): string {.raises: [].} =
  ## Builds a negative mutation of the theorem by replacing the conclusion
  ## with False. If the original theorem is sound, the negative version
  ## must fail to compile.
  let idx = findTacticConclusionAnchor(theoremSource)
  if idx < 0:
    return ""
  var colonIdx = -1
  var parenDepth = 0
  for i in countdown(idx - 1, 0):
    let c = theoremSource[i]
    if c == ')':
      parenDepth += 1
    elif c == '(':
      parenDepth -= 1
    elif c == ':' and parenDepth == 0:
      colonIdx = i
      break
  if colonIdx < 0:
    return ""
  theoremSource[0 ..< colonIdx + 1] & " False " & theoremSource[idx .. ^1]

# @axiom-hint: lean="theoremSource.length ≥ 0 ∧ artifactPath.length ≥ 0 ∧ leanExe.length ≥ 0 ∧ external_io_isolated" smt="(assert (and (>= (str.len theoremSource) 0) (>= (str.len artifactPath) 0) (>= (str.len leanExe) 0) external_io_isolated))"
# @axiom-hint: lean="artifactPath.length = 0 ∧ result ∧ artifactPath.length = 0 → result = result ∧ (result ≥ 0) ∧ external_io_isolated" smt="(assert (and (= (str.len artifactPath) 0) result (=> (= (str.len artifactPath) 0) (= result result)) (>= result 0) external_io_isolated))"
proc compileLeanSource(
  theoremSource: string;
  artifactPath: string;
 leanExe: string = ""
): LeanCompilerResult {.sideEffect, raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, TimeEffect, RootEffect].} =
  result.artifactPath = absolutePath(artifactPath)
  if artifactPath.len == 0:
    result.exitCode = -1
    result.diagnostics = @[LeanDiagnostic(
      line: 0,
      character: 0,
      severity: 1,
      message: "missing lean artifact path"
    )]
    return result
  const lintComment = "-- Axiom Kernel Micro-Pass: Linter suppression for LLM-generated artifacts\n"
  const lintOption = "set_option linter.unusedVariables false\n\n"
  ## Lean 4.29: set_option must come AFTER ALL imports; insert lintOption after last import block
  ## TODO(W1-A integration): removable once renderer emits header-only imports
  var postProcessed = lintComment & theoremSource
  let lastImportStart = postProcessed.rfind("import ")
  if lastImportStart >= 0:
    let importEnd = postProcessed.find('\n', lastImportStart)
    if importEnd > 0:
      postProcessed = postProcessed[0..importEnd] & lintOption & postProcessed[importEnd+1..^1]
  try:
    let artifactDir = parentDir(result.artifactPath)
    if artifactDir.len > 0 and not dirExists(artifactDir):
      discard existsOrCreateDir(artifactDir)
    if not writeFileSafe(result.artifactPath, postProcessed):
      result.exitCode = -1
      result.diagnostics = @[LeanDiagnostic(
        line: 0,
        character: 0,
        severity: 1,
        message: "Failed to write Lean artifact to " & result.artifactPath
      )]
      return result
  except CatchableError as e:
    result.exitCode = -1
    result.output = e.msg
    result.diagnostics = @[LeanDiagnostic(
      line: 0,
      character: 0,
      severity: 1,
      message: e.msg
    )]
    return result
  result = runLeanCompiler(result.artifactPath, leanExe)

func negativeMutationPassed*(compilerResult: LeanCompilerResult): bool {.raises: [].} =
  ## The negative mutation test genuinely validates non-vacuity:
  ## the original must compile (verified=true) while the mutated version
  ## MUST fail (negativeTestVerified=false). If negativeTestVerified is
  ## true, the negative test compiled — meaning the original proof is
  ## trivial/vacuous.
  ##
  ## This is the strongest available evidence chain for vacuityProven.
  ## Substring checks (e.g. sourceHasVacuityCheck) are NOT used as
  ## evidence — only the actual mutation test result.
  compilerResult.verified and not compilerResult.negativeTestVerified

## Verify Generated Lean Source With Compiler.
# @axiom-hint: lean="theoremSource.length ≥ 0 ∧ artifactPath.length ≥ 0 ∧ leanExe.length ≥ 0 ∧ external_io_isolated" smt="(assert (and (>= (str.len theoremSource) 0) (>= (str.len artifactPath) 0) (>= (str.len leanExe) 0) external_io_isolated))"
# @axiom-hint: lean="negSource.length = 0 ∨ negPath.length = 0 ∧ origFailed ∧ negFailed ∧ origFailed ∧ result ∧ negSource.length = 0 ∨ negPath.length = 0 → result = result ∧ (result ≥ 0) ∧ external_io_isolated" smt="(assert (and (or (= (str.len negSource) 0) (= (str.len negPath) 0)) (and origFailed negFailed) origFailed result (=> (or (= (str.len negSource) 0) (= (str.len negPath) 0)) (= result result)) (>= result 0) external_io_isolated))"
proc verifyGeneratedLeanSourceWithCompiler*(
  theoremSource: string;
  artifactPath: string;
 leanExe: string = ""
): LeanCompilerResult {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, TimeEffect, RootEffect].} =
  ## Verifies a Lean theorem source and performs a mandatory negative mutation test.
  ## The original theorem must compile successfully, while the mutated version
  ## MUST fail to compile. If the mutated version succeeds, the proof is trivial/vacuous.
  result = compileLeanSource(theoremSource, artifactPath, leanExe)

  # Vacuity ban: negative mutation test is now mandatory even for the 2-arity overload
  let negSource = buildNegativeTestSource(theoremSource)
  let negPath = artifactPath & ".negative.lean"
  if negSource.len == 0 or negPath.len == 0:
    result.diagnostics.add(LeanDiagnostic(
      line: 0,
      character: 0,
      severity: 1,
      message: "Vacuity ban: failed to build negative test source"
    ))
    result.verified = false
    return result

  try:
    let negDir = parentDir(absolutePath(negPath))
    if negDir.len > 0 and not dirExists(negDir):
      discard existsOrCreateDir(negDir)
    if not writeFileSafe(negPath, negSource):
      result.verified = false
      result.diagnostics.add(LeanDiagnostic(
        line: 0,
        character: 0,
        severity: 1,
        message: "Negative test file write failed"
      ))
      return result
  except CatchableError as e:
    result.verified = false
    result.diagnostics.add(LeanDiagnostic(
      line: 0,
      character: 0,
      severity: 1,
      message: "Negative test file write failed: " & e.msg
    ))
    return result

  let negResult = runLeanCompiler(negPath, leanExe)
  result.negativeTestVerified = negResult.verified

  let origFailed = not result.verified
  let negFailed = not negResult.verified

  # Check for timeout in negative mutation test (exitCode == -9 from runLeanCompiler)
  let negTimedOut = negResult.exitCode == -9

  if origFailed and negFailed:
    discard
  elif origFailed:
    discard
  elif negTimedOut:
    # Timeout in negative test — cannot determine vacuity. Mark as unverified (VKD exclusion).
    result.verified = false
    result.diagnostics.add(LeanDiagnostic(
      line: 0,
      character: 0,
      severity: 2,  # warning, not error
      message: "Vacuity ban: negative mutation test timed out — proof status unknown"
    ))
  elif not negFailed:
    # Vacuity ban: negative test passed means the original proof was trivial/vacuous
    result.verified = false
    result.diagnostics.add(LeanDiagnostic(
      line: 0,
      character: 0,
      severity: 1,
      message: "Vacuity ban: negative mutation test passed — proof is trivially true"
    ))
  else:
    discard

  result.vacuityProven = negativeMutationPassed(result)

## Verify Generated Lean Source With Compiler.
# @axiom-hint: lean="theoremSource.length >= 0 and artifactPath.length >= 0 and negativeTestSource.length >= 0 and negativeTestPath.length >= 0" smt="(assert (and (>= (str.len theoremSource) 0) (>= (str.len artifactPath) 0) (>= (str.len negativeTestSource) 0) (>= (str.len negativeTestPath) 0)))"
proc verifyGeneratedLeanSourceWithCompiler*(
  theoremSource: string;
  artifactPath: string;
  negativeTestSource: string;
  negativeTestPath: string;
  leanExe: string = ""
): LeanCompilerResult {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, TimeEffect, RootEffect].} =
  ## Verifies a Lean theorem source and performs a negative mutation test.
  ## The original theorem must compile successfully, while the mutated version
  ## MUST fail to compile. If the mutated version succeeds, the proof is trivial/vacuous.
  # Always compile original first
  result = compileLeanSource(theoremSource, artifactPath, leanExe)

  # Always compile negative test (even if original failed) - The Enforcer
  if negativeTestSource.len == 0 or negativeTestPath.len == 0:
    result.diagnostics.add(LeanDiagnostic(
      line: 0,
      character: 0,
      severity: 1,
      message: "Negative test source or path is empty"
    ))
    result.verified = false
    return result

  try:
    let negDir = parentDir(absolutePath(negativeTestPath))
    if negDir.len > 0 and not dirExists(negDir):
      discard existsOrCreateDir(negDir)
    if not writeFileSafe(negativeTestPath, negativeTestSource):
      result.verified = false
      result.diagnostics.add(LeanDiagnostic(
        line: 0,
        character: 0,
        severity: 1,
        message: "Negative test file write failed"
      ))
      return result
  except CatchableError as e:
    result.verified = false
    result.diagnostics.add(LeanDiagnostic(
      line: 0,
      character: 0,
      severity: 1,
      message: "Negative test file write failed: " & e.msg
    ))
    return result

  let negResult = runLeanCompiler(negativeTestPath, leanExe)
  result.negativeTestVerified = negResult.verified

  # Diagnosis: classify failure mode
  let origFailed = not result.verified
  let negFailed = not negResult.verified

  # Check for timeout in negative mutation test (exitCode == -9 from runLeanCompiler)
  let negTimedOut = negResult.exitCode == -9

  if origFailed and negFailed:
    discard
  elif origFailed:
    discard
  elif negTimedOut:
    # Timeout in negative test — cannot determine vacuity. Mark as unverified (VKD exclusion).
    result.verified = false
    result.diagnostics.add(LeanDiagnostic(
      line: 0,
      character: 0,
      severity: 2,  # warning, not error
      message: "Vacuity ban: negative mutation test timed out — proof status unknown"
    ))
  elif not negFailed:
    result.verified = false
    result.diagnostics.add(LeanDiagnostic(
      line: 0,
      character: 0,
      severity: 1,
      message: "Vacuity ban: negative mutation test passed — proof is trivially true"
    ))
  else:
    discard

  result.vacuityProven = negativeMutationPassed(result)

## Apply Lean Compiler Feedback.
# @axiom-hint: lean="compilerResult_verified = true ∨ compilerResult_verified = false ∧ compilerResult_negativeTestVerified = true ∨ compilerResult_negativeTestVerified = false ∧ compilerResult_exitCode ≥ -9223372036854775808 ∧ compilerResult_exitCode ≤ 9223372036854775807 ∧ compilerResult_diagnostics.size ≥ 0 ∧ compilerResult_output.length ≥ 0 ∧ compilerResult_artifactPath.length ≥ 0" smt="(assert (and (or (= compilerResult_verified true) (= compilerResult_verified false)) (or (= compilerResult_negativeTestVerified true) (= compilerResult_negativeTestVerified false)) (and (>= compilerResult_exitCode -9223372036854775808) (<= compilerResult_exitCode 9223372036854775807)) (>= (seq.len compilerResult_diagnostics) 0) (>= (str.len compilerResult_output) 0) (>= (str.len compilerResult_artifactPath) 0)))"
# @axiom-hint: lean="(leanTrack ≥ 0) ∧ compilerResult_verified = true ∨ compilerResult_verified = false ∧ compilerResult_negativeTestVerified = true ∨ compilerResult_negativeTestVerified = false" smt="(assert (and (>= leanTrack 0) (or (= compilerResult_verified true) (= compilerResult_verified false)) (or (= compilerResult_negativeTestVerified true) (= compilerResult_negativeTestVerified false))))"
func applyLeanCompilerFeedback*[T](leanTrack: var T; compilerResult: LeanCompilerResult) =
  when compiles(leanTrack.verified = compilerResult.verified):
    leanTrack.verified = compilerResult.verified
  when compiles(leanTrack.vacuityProven = compilerResult.vacuityProven):
    leanTrack.vacuityProven = compilerResult.vacuityProven
  when compiles(leanTrack.negativeMutationPass = compilerResult.negativeTestVerified):
    leanTrack.negativeMutationPass = compilerResult.negativeTestVerified

## Generate Context Aware Tactic.
# @axiom-hint: lean="diagnostics.size ≥ 0 ∧ goals.size ≥ 0 ∧ ∀ (i : Fin goals.size), (goals.get i).length ≥ 0 ∧ usedTactics.size ≥ 0 ∧ ∀ (i : Fin usedTactics.size), (usedTactics.get i).length ≥ 0" smt="(assert (and (>= (seq.len diagnostics) 0) (>= (seq.len goals) 0) (forall ((i Int)) (=> (and (>= i 0) (< i (seq.len goals))) (>= (str.len (seq.nth goals i)) 0))) (>= (seq.len usedTactics) 0) (forall ((i Int)) (=> (and (>= i 0) (< i (seq.len usedTactics))) (>= (str.len (seq.nth usedTactics i)) 0)))))"
{.pop.}

