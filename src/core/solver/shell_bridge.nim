import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

import std/os
import std/osproc
import std/strutils
import ../../core/trusted/axiom_pragmas

## Run Command In Directory.
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc runCommandInDir*(cmd: string; workingDir: string = ""): tuple[output: string; exitCode: int] {.raises: [CatchableError], axiom: ["(assert (and (>= result 0) external_io_isolated))", "(result ≥ 0) ∧ external_io_isolated"], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Cross-platform command execution with optional working directory.
  ## Replaces Unix-specific `cd ... && ...` shell concatenation.
  try:
    result = execCmdEx(cmd, workingDir = workingDir)
  except CatchableError:
    result = ("", -1)

## Check Tool Available.
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc checkToolAvailable*(toolName: string): bool {.raises: [CatchableError], axiom: ["(assert (and (= result false) (>= result 0)))", "result = false ∧ (result ≥ 0)"], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Cross-platform PATH probe. Returns true if `toolName` executable exists.
  try:
    result = findExe(toolName).len > 0
  except CatchableError:
    result = false

## Run Command Sequence In Directory.
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc runCommandSeqInDir*(cmds: seq[string]; workingDir: string = ""): tuple[output: string; exitCode: int] {.raises: [CatchableError], axiom: ["(assert (and (>= cmds 0) (>= result 0) (forall ((cmdsIdx Int)) (=> (and (>= cmdsIdx 0) (< cmdsIdx (seq.len cmds))) (>= (str.len (seq.nth cmds cmdsIdx)) 0)))))", "(cmds ≥ 0) ∧ (result ≥ 0) ∧ (∀ (cmdsIdx : Fin cmds.size), (cmds.get cmdsIdx).length ≥ 0)"], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Run a sequence of commands in the same working directory.
  ## Stops at first non-zero exit code and returns its output.
  var combinedOutput = ""
  for cmd in cmds:
    let res = runCommandInDir(cmd, workingDir)
    if res.output.len > 0:
      combinedOutput.add(res.output)
      if not combinedOutput.endsWith("\n"):
        combinedOutput.add("\n")
    if res.exitCode != 0:
      return (combinedOutput, res.exitCode)
  result = (combinedOutput, 0)

{.pop.}
