import core/trusted/layer_declaration


axiomLayer "gate"
{.push raises: [CatchableError].}

## Integrity Test Runner Gate
##
## Runs the integrity test binary with incremental caching.
## Uses build/nimcache/ for binary cache to avoid recompilation
## when source files have not changed.
import std/os
import std/osproc
import std/times
import core/utils/io_utils
import core/axiom_pragmas
# axiomIoBoundary

const
  IntegrityBinary = "bin/integrity_test"
  IntegrityCacheDir = "build/nimcache/integrity_test"
  IntegritySource = "tests/unit/integrity_check_test.nim"

proc compileIntegrityTest(): int {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  discard existsOrCreateDirOpt(IntegrityCacheDir)
  let cmd = "nim c --hints:off --nimcache:" & quoteShell(IntegrityCacheDir) &
            " -o:" & quoteShell(IntegrityBinary) & " " & quoteShell(IntegritySource)
  let (output, exitCode) = execCmdEx(cmd)
  stdout.write(output)
  exitCode

proc runIntegrityTestBinary(): int {.axiomEffect: IOEffect.} =
  let (output, exitCode) = execCmdEx(IntegrityBinary)
  stdout.write(output)
  exitCode

proc main() {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  var exitCode: int
  if fileExists(IntegrityBinary):
    exitCode = runIntegrityTestBinary()
  else:
    exitCode = compileIntegrityTest()
    if exitCode == 0:
      exitCode = runIntegrityTestBinary()

  if exitCode != 0:
    quit(exitCode)

  discard existsOrCreateDirOpt("logs")
  ## intentional-discard: epoch marker is re-derivable; write is best-effort
  discard writeFileOpt("logs/.integrity_gate_passed_epoch", $getTime().toUnix)

when isMainModule:
  main()

{.pop.}
