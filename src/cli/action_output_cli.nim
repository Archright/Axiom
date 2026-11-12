import core/trusted/layer_declaration
axiomLayer "presentation"
{.push raises: [CatchableError].}
# axiomIoBoundary

import core/results

import cli/cli_io_error
import cli/cli_types
import cli/report_cli
import ../core/trusted/axiom_pragmas

## Write Output Block.
  ## axiom-smt: (assert (and (= (str.len payload) 0) (forall ((linesIdx Int)) (=> (and (>= linesIdx 0) (< linesIdx (seq.len lines))) (>= (str.len (seq.nth lines linesIdx)) 0)))))
  ## axiom-lean: payload.length = 0 ∧ (∀ (linesIdx : Fin lines.size), (lines.get linesIdx).length ≥ 0)
proc writeOutputBlock*(output: File; lines: seq[string]) {.axiomTryImpl, axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let payload = renderOutputBlock(lines)
  if payload.len == 0:
    return
  output.write(payload)
  output.flushFile()

## Emit Ax Shortcut Result.
  ## axiom-smt: (assert (and (forall ((argsIdx Int)) (=> (and (>= argsIdx 0) (< argsIdx (seq.len args))) (>= (str.len (seq.nth args argsIdx)) 0)))))
  ## axiom-lean: (∀ (argsIdx : Fin args.size), (args.get argsIdx).length ≥ 0)
proc emitAxShortcutResult*(output: Result[AxCommandCliResult, string]; args: seq[string]) {.axiomTryImpl.} =
  if output.isErr():
    die(output.error)
  let result = output.get()
  writeOutputBlock(stderr, renderAxShortcutStderrLines(result, usesAxShortcutJsonFlag(args)))
  writeOutputBlock(stdout, renderAxShortcutStdoutLines(result, usesAxShortcutJsonFlag(args)))
  quit(result.exitCode)
{.pop.}
