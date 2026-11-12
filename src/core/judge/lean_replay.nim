import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

import std/os
import std/strutils
import std/times
import core/types/results
import core/utils/io_utils
import core/utils/io_utils_isolation
import core/sync/sync_utils_process
import core/trusted/axiom_pragmas
import verification/lean_lsp_compiler
import verification/obligation/lean_kernel_boundary

## Lean 4 Compiler Replay — lightweight proof verification via subprocess.
## Creates temporary .lean file, runs `lake env lean <file>`, returns result.
## The kernel-check portion delegates to `canonicalLeanKernelCheck`
## (the single trust-boundary sink) so that kernel acceptance is
## produced by exactly one canonical path.

const
  leanDefaultTimeoutMs = 60000
  leanCommand = "lake"

type
  LeanReplayResult* = object
    isValid*: bool
    proofTerm*: string
    compilerOutput*: string   ## stdout from lean
    compilerStderr*: string   ## stderr from lean
    exitCode*: int            ## process exit code
    vacuityDetected*: bool
    theoremName*: string      ## Extracted theorem/lemma/def name
    hypotheses*: seq[string]  ## Extracted hypothesis binder names

## Sanitize a string for use in a filename.
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func safeFileName(s: string): string {.inline.} =
  for c in s:
    if c in {'a'..'z', 'A'..'Z', '0'..'9', '-', '_'}:
      result.add(c)
    else:
      result.add('_')

## Extract the theorem/lemma name from Lean source for `#print axioms` enforcement.
## Returns the name of the first theorem/lemma/def declared in the source.
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func extractTheoremName(leanSource: string): string {.inline.} =
  var inBlockComment = false
  for line in leanSource.splitLines():
    let stripped = line.strip()
    if stripped.contains("/-"):
      inBlockComment = true
    if stripped.contains("-/"):
      inBlockComment = false
      continue
    if inBlockComment:
      continue
    for keyword in ["theorem ", "lemma ", "def "]:
      if stripped.startsWith(keyword):
        let rest = stripped[keyword.len .. ^1]
        # Extract identifier (up to first non-identifier char)
        var idLen = 0
        for c in rest:
          if c.isAlphaAscii or c.isDigit or c == '_' or c == chr(39):
            inc idLen
          else:
            break
        if idLen > 0:
          return rest[0 ..< idLen]
        return rest
  ""

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func extractHypotheses*(leanSource: string): seq[string] =
  ## Extract hypothesis binder names from a Lean theorem/lemma/def signature.
  ## Parses patterns like:
  ##   theorem name (h0 : T0) (h1 : T1) : result := ...
  ##   lemma name {h0 : T0} (h_sys : T1) : result := ...
  ## Returns the list of binder identifiers in order.
  var inBlockComment = false
  for line in leanSource.splitLines():
    let stripped = line.strip()
    if stripped.contains("/-"): inBlockComment = true
    if stripped.contains("-/"): inBlockComment = false; continue
    if inBlockComment: continue
    var keyword = ""
    var kwLen = 0
    for kw in ["theorem ", "lemma ", "def "]:
      if stripped.startsWith(kw):
        keyword = kw
        kwLen = kw.len
        break
    if kwLen == 0: continue
    var pos = kwLen
    while pos < stripped.len and (stripped[pos].isAlphaAscii or stripped[pos].isDigit or stripped[pos] == '_' or stripped[pos] == chr(39)):
      pos += 1
    while pos < stripped.len:
      while pos < stripped.len and stripped[pos] in {' ', '\t'}:
        pos += 1
      if pos >= stripped.len: break
      if stripped[pos] in {'(', '{'}:
        pos += 1
        while pos < stripped.len and stripped[pos] in {' ', '\t'}:
          pos += 1
        var binder = ""
        while pos < stripped.len and (stripped[pos].isAlphaAscii or stripped[pos].isDigit or stripped[pos] == '_' or stripped[pos] == chr(39)):
          binder.add(stripped[pos])
          pos += 1
        if binder.len > 0 and binder notin result:
          result.add(binder)
        var depth = 1
        while pos < stripped.len and depth > 0:
          if stripped[pos] == '(': depth += 1
          elif stripped[pos] == ')': depth -= 1
          elif stripped[pos] == '{': depth += 1
          elif stripped[pos] == '}': depth -= 1
          pos += 1
      elif stripped[pos] == ':' and pos + 1 < stripped.len and stripped[pos+1] == '=':
        break
      elif stripped[pos] == ':':
        var nextPos = pos + 1
        while nextPos < stripped.len and stripped[nextPos] in {' ', '\t'}:
          nextPos += 1
        if nextPos < stripped.len and stripped[nextPos] != '=':
          break
        else:
          pos += 1
      else:
        pos += 1

## Builtin axiom allowlist — the only axioms a replay may legitimately depend on.
## Any other named axiom (notably `sorryAx` / `Lean.sorryAx`) triggers fail-closed
## rejection of the replay verdict. Mirrors ax_vacuity_check.lean (see
## docs/spec/lean_sorry_gate.md, DEBT#296 precedent).
const leanBuiltinAxiomAllowlist*: array[4, string] =
  ["Classical.choice", "Quot.sound", "propext", "funext"]

## Parse `#print axioms <thm>` output into a (sectionPresent, axiomNames) pair.
## Lean 4.29 renders the named command as either
##   "'name' does not depend on any axioms"          -> present, empty list
##   "'name' depends on axioms: [propext, Quot.sound]" -> present, listed names
## The section is considered present only when such a dependency line is found;
## otherwise the strict sorry/allowlist check is NOT applied (fail-open only for
## the absence of the section, never for a present sorry — see §lean_sorry_gate).
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func parsePrintedAxioms*(leanOutput: string): tuple[sectionPresent: bool, axioms: seq[string]] {.raises: [].} =
  result = (sectionPresent: false, axioms: @[])
  for line in leanOutput.splitLines():
    let stripped = line.strip()
    if "depend" in stripped and "axioms" in stripped:
      result.sectionPresent = true
      let openBracket = stripped.find('[')
      let closeBracket = stripped.rfind(']')
      if openBracket >= 0 and closeBracket > openBracket:
        for name in stripped[openBracket + 1 ..< closeBracket].split(','):
          let n = name.strip()
          if n.len > 0 and n notin result.axioms:
            result.axioms.add(n)

## Fail-closed sorry gate over a parsed `#print axioms` section.
## Returns false (reject) if ANY named axiom is `sorryAx`/`Lean.sorryAx` or is
## not on the builtin allowlist. Returns true only when no offending axiom exists.
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func sorryGateValid*(sectionPresent: bool; axioms: seq[string]): bool {.raises: [].} =
  if not sectionPresent:
    return true
  for ax in axioms:
    if ax == "sorryAx" or ax == "Lean.sorryAx":
      return false
    if ax notin leanBuiltinAxiomAllowlist:
      return false
  true

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func extractGoalName(leanSource: string): string =
  for line in leanSource.splitLines():
    let stripped = line.strip()
    if stripped.startsWith("abbrev") and "_inferred_safety_goal" in stripped:
      var startIdx = "abbrev".len
      while startIdx < stripped.len and (stripped[startIdx] == ' ' or stripped[startIdx] == '\t'):
        inc startIdx
      let rest = stripped[startIdx .. ^1]
      var idLen = 0
      for c in rest:
        if c.isAlphaAscii or c.isDigit or c == '_' or c == chr(39):
          inc idLen
        else: break
      if idLen > 0:
        return rest[0 ..< idLen]
  ""

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func isReduceResultVacuous(output: string, goalName: string): bool =
  let lowerGoal = goalName.toLowerAscii()
  for line in output.splitLines():
    let stripped = line.strip().toLowerAscii()
    if stripped == "true" or stripped == "prop" or stripped == "true.intro":
      return true
    if ":=" in stripped:
      let parts = stripped.split(":=")
      if parts.len == 2:
        let left = parts[0].strip()
        let right = parts[1].strip()
        if lowerGoal in left and (right == "true" or right == "true.intro"):
          return true
  false

## Write Lean source with linter suppression header for LLM-generated artifacts.
## Prevents unused variable warnings from causing kernel rejection.
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc sanitizeAndWriteLeanSource*(path: string, rawSource: string) {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  const lintGown = """-- Axiom Kernel Micro-Pass: Linter suppression for LLM-generated artifacts
set_option linter.unusedVariables false

"""
  isolatedWriteFile(path, lintGown & rawSource)

## Execute Lean 4 compiler on a proof script.
## Writes `leanSource` to a temporary file, runs `lean <file>`, captures output.
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc runLeanReplay*(nodeId: string; leanSource: string): Result[LeanReplayResult, string]  {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  var tmpFile = ""
  var tmpDir = ""
  ## DEBT#002: Force `#print axioms` to expose proof dependencies.
  ## This ensures vacuous proofs using only kernel reduction are detected.
  ## Deterministic boilerplate: ensure valid Lean 4 module structure.
  ## Note: Lean 4 base install does NOT include Mathlib. Only add imports
  ## if the source already contains them (LLM may include needed imports).
  ## Basic types (Nat, Int, List, etc.) are available without imports.
  var moduleParts: seq[string] = @[]
  moduleParts.add(leanSource)
  let thmName = extractTheoremName(leanSource)
  if thmName.len > 0:
    moduleParts.add("#print axioms " & thmName)
  else:
    moduleParts.add("#print axioms")
  # Vacuity reduction check — detect abbrev-wrapped True
  let goalName = extractGoalName(leanSource)
  if goalName.len > 0:
    moduleParts.add("set_option maxRecDepth 10000")
    moduleParts.add("set_option maxHeartbeats 200000")
    moduleParts.add("#reduce " & goalName)
  let augmentedSource = moduleParts.join("\n")
  try:
    ## Create temporary directory and file
    tmpDir = getTempDir() / "axiom_lean_replay_" & $epochTime().int
    discard existsOrCreateDirOpt(tmpDir) # axiom:best-effort(mkdir failure is caught downstream by sanitizeAndWriteLeanSource)
    tmpFile = tmpDir / "proof_" & safeFileName(nodeId) & ".lean"
    sanitizeAndWriteLeanSource(tmpFile, augmentedSource)
  except CatchableError:
    return err("Failed to create temporary Lean file")

  ## Run lean <file> via the canonical kernel-check sink.
  ## The sink handles executable resolution, artifact writing,
  ## actual execution, and receipt production.
  let sinkResult =
    try:
      canonicalLeanKernelCheck(augmentedSource, timeoutMs = leanDefaultTimeoutMs)
    except CatchableError as e:
      try:
        removeFile(tmpFile)
        removeDir(tmpDir)
      except CatchableError:
        discard  # axiom:best-effort(temp cleanup)
      return err("Lean kernel check launch failure: " & e.msg)

  var output = ""
  var exitCode = -1
  if sinkResult.isOk:
    let receipt = sinkResult.get()
    output = receiptKernelObservation(receipt)
    exitCode = 0
  else:
    let errMsg = sinkResult.error
    ## Cleanup temp files
    try:
      removeFile(tmpFile)
      removeDir(tmpDir)
    except CatchableError:
      discard  # axiom:best-effort(temp cleanup)
    ## Debug output
    try:
      let debugDir = getTempDir() / "axiom_lean_debug"
      discard existsOrCreateDirOpt(debugDir)
      let dbgBase = debugDir / "proof_" & safeFileName(nodeId) & "_" & $epochTime().int
      ## intentional-discard: debug dump is optional; failures never block compilation
      ## intentional-discard: debug dump is optional; failures never block compilation
      discard writeFileOpt(dbgBase & ".lean", augmentedSource)  # axiom:best-effort(debug dump is optional)
      ## intentional-discard: debug output is non-blocking; failures never block compilation
      discard writeFileOpt(dbgBase & ".stdout.txt", "")  # axiom:best-effort(debug dump is optional)
      ## intentional-discard: debug output is non-blocking; failures never block compilation
      discard writeFileOpt(dbgBase & ".stderr.txt", errMsg)  # axiom:best-effort(debug dump is optional)
      ## intentional-discard: debug output is non-blocking; failures never block compilation
      discard writeFileOpt(dbgBase & ".exitcode.txt", "-1")  # axiom:best-effort(debug dump is optional)
    except CatchableError:
      discard  # axiom:best-effort(debug dump is optional)
    return err("Lean compiler failed via canonical kernel check: " & errMsg)

  # Detect vacuous result from #reduce output
  let vacuityDetected = exitCode == 0 and extractGoalName(leanSource).len > 0 and isReduceResultVacuous(output, extractGoalName(leanSource))

  ## Cleanup temp files
  try:
    removeFile(tmpFile) # axiom:best-effort(cleanup; temp dir removal is best-effort)
    removeDir(tmpDir)
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)

  ## Debug: persist source + output for analysis
  try:
    let debugDir = getTempDir() / "axiom_lean_debug"
    discard existsOrCreateDirOpt(debugDir) # axiom:best-effort(debug output; non-critical)
    let dbgBase = debugDir / "proof_" & safeFileName(nodeId) & "_" & $epochTime().int
    ## intentional-discard: debug output is non-critical; failures never block analysis
    discard writeFileOpt(dbgBase & ".lean", leanSource) # axiom:best-effort(debug output; non-critical)
    ## intentional-discard: debug output is non-blocking; failures never block analysis
    discard writeFileOpt(dbgBase & ".stdout.txt", output) # axiom:best-effort(debug output; non-critical)
    ## intentional-discard: debug output is non-blocking; failures never block analysis
    discard writeFileOpt(dbgBase & ".stderr.txt", "") # axiom:best-effort(debug output; non-critical)
    ## intentional-discard: debug output is non-blocking; failures never block analysis
    discard writeFileOpt(dbgBase & ".exitcode.txt", $exitCode) # axiom:best-effort(debug output; non-critical)
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)

  ## Evaluate result
  if exitCode == 0:
    let thmName = extractTheoremName(leanSource)
    let hyps = extractHypotheses(leanSource)
    ## Fail-closed sorry gate: parse the collected `#print axioms` section and
    ## reject the replay verdict if it lists sorryAx/Lean.sorryAx or any axiom
    ## outside the builtin allowlist. See docs/spec/lean_sorry_gate.md (DEBT#296).
    let (axiomSectionPresent, printedAxioms) = parsePrintedAxioms(output)
    let replayIsValid = sorryGateValid(axiomSectionPresent, printedAxioms)
    ok(LeanReplayResult(isValid: replayIsValid, proofTerm: leanSource,
      compilerOutput: output, compilerStderr: "", exitCode: exitCode,
      vacuityDetected: vacuityDetected, theoremName: thmName, hypotheses: hyps))
  elif exitCode == -1:
    err("Lean compiler timed out after " & $leanDefaultTimeoutMs & "ms")
  else:
    let trimmed = output.strip()
    var msg = "Lean compiler error (exit " & $exitCode & ")"
    if trimmed.len > 0:
      msg &= ": " & trimmed
    err(msg)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc runNegativeMutationTest*(nodeId: string; leanSource: string): bool =
  let mutatedSource = buildNegativeTestSource(leanSource)
  if mutatedSource.len == 0:
    return false
  let replayResult = runLeanReplay(nodeId & "_negative", mutatedSource)
  if not replayResult.isOk:
    return false
  let replay = replayResult.get()
  if replay.isValid:
    return false
  let leanOutput: string = replay.compilerOutput.toLowerAscii()
  if find(leanOutput, "parser failed") >= 0 or
     find(leanOutput, "unexpected token") >= 0 or
     find(leanOutput, "unterminated string") >= 0:
    return false
  if find(leanOutput, "unsolved goals") >= 0 or
     find(leanOutput, "type mismatch") >= 0 or
     find(leanOutput, "application type mismatch") >= 0 or
     find(leanOutput, "unable to unify") >= 0 or
     find(leanOutput, "failed to synthesize instance") >= 0 or
     find(leanOutput, "unknown identifier") >= 0 or
     find(leanOutput, "maximum recursion depth") >= 0 or
     find(leanOutput, "declaration uses sorry") >= 0 or
     find(leanOutput, "function expected") >= 0 or
     find(leanOutput, "cannot unfold") >= 0:
    return true
  false

{.pop.}

